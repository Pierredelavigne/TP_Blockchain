# Réponses théoriques - BilletChain

## Q1 - Pourquoi l'exécution d'un smart contract est-elle déterministe et répliquée ?

Sur Ethereum, tous les noeuds du réseau exécutent chaque transaction de leur côté pour vérifier que le résultat est bon. C'est ce qui permet d'arriver à un consensus sans avoir besoin de faire confiance à un seul acteur.

Pour que ça marche, il faut absolument que tout le monde obtienne le même résultat à partir des mêmes données d'entrée. C'est ça le déterminisme : mêmes inputs = même output, à chaque fois, sur chaque noeud.

Et c'est justement pour ça qu'un contrat ne peut pas aller chercher une donnée externe tout seul (comme un taux de change ou la météo). Si le contrat faisait un appel HTTP à une API, chaque noeud pourrait recevoir une réponse différente selon le timing, un timeout réseau, etc. Le consensus serait cassé.

La solution c'est l'oracle : quelqu'un (un service de confiance, ou un admin) envoie la donnée dans le contrat via une transaction classique. Cette transaction est répliquée partout, donc tous les noeuds voient la même valeur. Dans notre cas, c'est le PriceOracle qui stocke le taux EUR/ETH, et c'est l'organisateur qui le met à jour.

## Q2 - Rôle de la signature et de la clé privée

Quand quelqu'un achète un billet, il envoie une transaction signée avec sa clé privée. La signature sert à prouver deux choses : que c'est bien cette personne qui a envoyé la transaction (authenticité), et que personne n'a modifié la transaction en chemin (intégrité).

Le truc malin, c'est que le réseau arrive à vérifier tout ça sans jamais voir la clé privée. Ethereum utilise la cryptographie sur courbe elliptique (ECDSA). Concrètement, à partir de la signature et du contenu de la transaction, n'importe quel noeud peut recalculer la clé publique de l'émetteur, et donc retrouver son adresse Ethereum (qui est un hash de cette clé publique). Si ça correspond à l'adresse qui prétend envoyer la transaction, c'est validé.

L'opération inverse (retrouver la clé privée à partir de la clé publique) est mathématiquement infaisable. C'est ce qui fait que le système est sûr.

## Q3 - Pourquoi un token unique (ERC-721) plutôt qu'interchangeable (ERC-20) ?

Ici chaque billet correspond à une place précise dans la salle. Le billet n°5 n'est pas la même chose que le billet n°12 : ils ont chacun leur propre prix d'achat initial, leur propre historique de revente, leur propre propriétaire. On a besoin de pouvoir les distinguer et les suivre individuellement. C'est pile la définition d'un NFT (ERC-721) : chaque token a un identifiant unique.

Un token interchangeable (ERC-20) aurait du sens pour autre chose, par exemple des jetons de fidélité pour la salle de concert. 10 points de fidélité, c'est 10 points de fidélité, peu importe "lesquels". Ils sont tous pareils, comme des pièces de monnaie. Là un ERC-20 serait le bon choix.

## Q4 - Deux vulnérabilités et comment on s'en protège

### 1. La réentrance

C'est le grand classique. Le risque : quand on envoie de l'ETH à quelqu'un dans `retirerFonds`, si le destinataire est un contrat malveillant, il peut rappeler `retirerFonds` dans sa fonction `receive` avant que le solde soit mis à zéro. Il pourrait vider tout le contrat en boucle.

Notre protection : on applique le pattern Checks-Effects-Interactions. On met le solde à zéro AVANT d'envoyer l'argent :

```solidity
soldesRetirables[msg.sender] = 0;      // d'abord on met à zéro
(bool succes,) = payable(msg.sender).call{value: montant}(""); // ensuite on envoie
```

Si l'attaquant essaie de rappeler `retirerFonds`, le require échoue parce que son solde est déjà à 0.

### 2. Données oracle non fiables ou périmées

Le risque : si on ne vérifie pas la fraîcheur du taux de change, un attaquant pourrait attendre que l'oracle ait un vieux taux complètement décalé par rapport au marché, et acheter des billets pour presque rien (ou inversement, le prix pourrait être délirant).

Notre protection : on vérifie deux choses à chaque achat :

```solidity
require(block.timestamp - updatedAt <= MAX_ORACLE_AGE, "taux oracle perime");
require(tauxParEur > 0, "taux oracle invalide");
```

Si le taux a plus d'1 heure, l'achat est refusé. Et un taux à zéro est rejeté aussi. En plus, seul le propriétaire de l'oracle peut mettre à jour le taux, donc personne d'autre ne peut injecter une fausse valeur.

## Q5 - Deux décisions pour réduire le coût en gas

### 1. La fonction `compterBilletsEnVente` est en lecture seule (`view`)

Quand on veut savoir combien de billets sont en vente, on n'a pas besoin de modifier quoi que ce soit dans la blockchain. La fonction est déclarée `view`, ce qui fait qu'elle est gratuite quand on l'appelle depuis l'extérieur (un site web par exemple, via `eth_call`). La boucle qu'elle contient s'exécute uniquement sur le noeud local, pas dans une transaction payante. Si on avait stocké un compteur qu'on incrémente/décrémente à chaque mise en vente, on aurait payé du gas en écriture à chaque opération.

### 2. Des mappings plutôt que des tableaux pour les listings

On stocke les billets en vente dans un `mapping(uint256 => Listing)` plutôt que dans un tableau. L'avantage c'est que l'accès est en O(1) : on va directement à la bonne case sans parcourir quoi que ce soit. Ajouter un listing, le lire, ou le supprimer coûte toujours le même gas, quelle que soit la taille. Avec un tableau il faudrait chercher l'élément, le déplacer, réorganiser... tout ça coûte cher en gas. En plus, le `delete` d'une entrée de mapping remet les valeurs à zéro, ce qui donne un remboursement partiel de gas (storage refund).
