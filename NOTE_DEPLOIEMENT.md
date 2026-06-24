# Note de déploiement - BilletChain

## Réseau de test choisi

On déploierait sur **Sepolia**, c'est le testnet principal recommandé par Ethereum en ce moment. On peut récupérer des ETH de test gratuitement via des faucets (sepoliafaucet.com par exemple).

## Valeurs passées à la création

1. **D'abord déployer le `PriceOracle`** avec un taux initial. Par exemple 500000000000000 wei par euro, ce qui correspond à 1 ETH = 2000 EUR environ (un taux réaliste au moment où j'écris).

2. **Ensuite déployer `BilletChain`** avec :
   - `_nom` : `"Concert Rock 2026"`
   - `_symbole` : `"BLLT"`
   - `_maxBillets` : `500` (capacité de la salle)
   - `_prixEnEuroCentimes` : `5000` (soit 50,00 EUR)
   - `_oracle` : l'adresse du PriceOracle qu'on vient de déployer

## Où récupérer l'adresse de la source de taux de change

En vrai, pour un déploiement sérieux, on utiliserait un flux **Chainlink Price Feed** plutôt que notre oracle maison. Sur Sepolia, Chainlink met à disposition des flux de prix dont le ETH/USD (on peut convertir). Les adresses sont listées sur leur doc officielle :
https://docs.chain.link/data-feeds/price-feeds/addresses (filtrer par réseau Sepolia).

Pour notre TP, on garde notre `PriceOracle` simple et on pourrait avoir un petit script off-chain (en JavaScript par exemple) qui va lire le vrai prix sur une API (CoinGecko, Binance...) et qui appelle `updateRate()` toutes les 30 minutes. C'est suffisant pour un contexte de formation.

## Commandes de déploiement avec Foundry

```bash
export RPC_URL="https://sepolia.infura.io/v3/VOTRE_CLE"
export PRIVATE_KEY="votre_cle_privee"

# Deployer l'oracle
forge create src/PriceOracle.sol:PriceOracle \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args 500000000000000

# Deployer BilletChain (remplacer ORACLE_ADDRESS)
forge create src/BilletChain.sol:BilletChain \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args "Concert Rock 2026" "BLLT" 500 5000 ORACLE_ADDRESS
```
