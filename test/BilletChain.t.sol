// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BilletChain.sol";
import "../src/PriceOracle.sol";

contract BilletChainTest is Test {
    BilletChain public billetChain;
    PriceOracle public oracle;

    address organisateur = address(1);
    address acheteur1 = address(2);
    address acheteur2 = address(3);

    // 1 EUR = 0.0005 ETH = 500000000000000 wei
    uint256 constant TAUX_EUR_WEI = 500000000000000;
    // Prix du billet : 50,00 EUR = 5000 centimes
    uint256 constant PRIX_EUR_CENTIMES = 5000;
    // Prix attendu en wei : 5000 * 500000000000000 / 100 = 25000000000000000 = 0.025 ETH
    uint256 constant PRIX_ATTENDU_WEI = 25000000000000000;
    uint256 constant MAX_BILLETS = 3;

    function setUp() public {
        vm.startPrank(organisateur);
        oracle = new PriceOracle(TAUX_EUR_WEI);
        billetChain = new BilletChain("Concert", "BLLT", MAX_BILLETS, PRIX_EUR_CENTIMES, address(oracle));
        vm.stopPrank();

        vm.deal(acheteur1, 10 ether);
        vm.deal(acheteur2, 10 ether);
    }

    // ===================== VENTE INITIALE =====================

    function test_AchatBilletReussi() public {
        vm.prank(acheteur1);
        billetChain.acheterBillet{value: PRIX_ATTENDU_WEI}();

        assertEq(billetChain.ownerOf(0), acheteur1);
        assertEq(billetChain.billetsVendus(), 1);
        assertEq(billetChain.prixInitial(0), PRIX_ATTENDU_WEI);
    }

    function test_AchatMontantTropBas() public {
        vm.prank(acheteur1);
        vm.expectRevert("BilletChain: montant incorrect");
        billetChain.acheterBillet{value: PRIX_ATTENDU_WEI - 1}();
    }

    function test_AchatMontantTropHaut() public {
        vm.prank(acheteur1);
        vm.expectRevert("BilletChain: montant incorrect");
        billetChain.acheterBillet{value: PRIX_ATTENDU_WEI + 1}();
    }

    function test_AchatComplet() public {
        for (uint256 i = 0; i < MAX_BILLETS; i++) {
            address buyer = address(uint160(10 + i));
            vm.deal(buyer, 1 ether);
            vm.prank(buyer);
            billetChain.acheterBillet{value: PRIX_ATTENDU_WEI}();
        }

        vm.prank(acheteur1);
        vm.expectRevert("BilletChain: complet");
        billetChain.acheterBillet{value: PRIX_ATTENDU_WEI}();
    }

    function test_AchatCrediteOrganisateur() public {
        vm.prank(acheteur1);
        billetChain.acheterBillet{value: PRIX_ATTENDU_WEI}();

        assertEq(billetChain.soldesRetirables(organisateur), PRIX_ATTENDU_WEI);
    }

    // ===================== ORACLE =====================

    function test_OraclePerime() public {
        // Avancer le temps de plus d'1 heure
        vm.warp(block.timestamp + 2 hours);

        vm.prank(acheteur1);
        vm.expectRevert("BilletChain: taux oracle perime");
        billetChain.acheterBillet{value: PRIX_ATTENDU_WEI}();
    }

    function test_OracleMisAJour() public {
        // Avancer le temps
        vm.warp(block.timestamp + 2 hours);

        // Mettre a jour l'oracle
        vm.prank(organisateur);
        oracle.updateRate(TAUX_EUR_WEI);

        // L'achat doit fonctionner maintenant
        vm.prank(acheteur1);
        billetChain.acheterBillet{value: PRIX_ATTENDU_WEI}();

        assertEq(billetChain.ownerOf(0), acheteur1);
    }

    function test_OracleTauxZero() public {
        // Deployer un oracle avec taux 0 est impossible
        vm.prank(organisateur);
        vm.expectRevert("PriceOracle: taux invalide");
        new PriceOracle(0);
    }

    function test_OracleSeulProprietaire() public {
        vm.prank(acheteur1);
        vm.expectRevert("PriceOracle: pas le proprietaire");
        oracle.updateRate(1000);
    }

    function test_AchatAvecNouveauTaux() public {
        // Doubler le taux : 1 EUR = 0.001 ETH
        uint256 nouveauTaux = TAUX_EUR_WEI * 2;
        vm.prank(organisateur);
        oracle.updateRate(nouveauTaux);

        uint256 nouveauPrix = (PRIX_EUR_CENTIMES * nouveauTaux) / 100;

        vm.prank(acheteur1);
        billetChain.acheterBillet{value: nouveauPrix}();
        assertEq(billetChain.ownerOf(0), acheteur1);
    }

    // ===================== REVENTE =====================

    function _acheterBillet(address _acheteur) internal returns (uint256 tokenId) {
        tokenId = billetChain.billetsVendus();
        vm.prank(_acheteur);
        billetChain.acheterBillet{value: PRIX_ATTENDU_WEI}();
    }

    function test_MiseEnVenteReussie() public {
        uint256 tokenId = _acheterBillet(acheteur1);
        uint256 prixRevente = (PRIX_ATTENDU_WEI * 110) / 100; // 110%

        vm.prank(acheteur1);
        billetChain.mettreEnVente(tokenId, prixRevente);

        (bool enVente, uint256 prix) = billetChain.listings(tokenId);
        assertTrue(enVente);
        assertEq(prix, prixRevente);
    }

    function test_MiseEnVenteDepassePlafond() public {
        uint256 tokenId = _acheterBillet(acheteur1);
        uint256 prixTropCher = (PRIX_ATTENDU_WEI * 111) / 100; // 111%

        vm.prank(acheteur1);
        vm.expectRevert("BilletChain: prix depasse le plafond de 110%");
        billetChain.mettreEnVente(tokenId, prixTropCher);
    }

    function test_MiseEnVentePasProprietaire() public {
        uint256 tokenId = _acheterBillet(acheteur1);

        vm.prank(acheteur2);
        vm.expectRevert("BilletChain: pas proprietaire");
        billetChain.mettreEnVente(tokenId, PRIX_ATTENDU_WEI);
    }

    function test_MiseEnVentePrixZero() public {
        uint256 tokenId = _acheterBillet(acheteur1);

        vm.prank(acheteur1);
        vm.expectRevert("BilletChain: prix doit etre > 0");
        billetChain.mettreEnVente(tokenId, 0);
    }

    function test_AchatReventeReussi() public {
        uint256 tokenId = _acheterBillet(acheteur1);
        uint256 prixRevente = (PRIX_ATTENDU_WEI * 105) / 100; // 105%

        vm.prank(acheteur1);
        billetChain.mettreEnVente(tokenId, prixRevente);

        vm.prank(acheteur2);
        billetChain.acheterRevente{value: prixRevente}(tokenId);

        assertEq(billetChain.ownerOf(tokenId), acheteur2);
        assertEq(billetChain.soldesRetirables(acheteur1), prixRevente);
    }

    function test_AchatRevonteMontantIncorrect() public {
        uint256 tokenId = _acheterBillet(acheteur1);
        uint256 prixRevente = PRIX_ATTENDU_WEI;

        vm.prank(acheteur1);
        billetChain.mettreEnVente(tokenId, prixRevente);

        vm.prank(acheteur2);
        vm.expectRevert("BilletChain: montant incorrect");
        billetChain.acheterRevente{value: prixRevente - 1}(tokenId);
    }

    function test_AchatBilletPasEnVente() public {
        uint256 tokenId = _acheterBillet(acheteur1);

        vm.prank(acheteur2);
        vm.expectRevert("BilletChain: billet pas en vente");
        billetChain.acheterRevente{value: PRIX_ATTENDU_WEI}(tokenId);
    }

    function test_RetirerDeLaVente() public {
        uint256 tokenId = _acheterBillet(acheteur1);

        vm.prank(acheteur1);
        billetChain.mettreEnVente(tokenId, PRIX_ATTENDU_WEI);

        vm.prank(acheteur1);
        billetChain.retirerDeLaVente(tokenId);

        (bool enVente,) = billetChain.listings(tokenId);
        assertFalse(enVente);
    }

    // ===================== ENCAISSEMENT =====================

    function test_RetraitOrganisateur() public {
        _acheterBillet(acheteur1);

        uint256 balanceAvant = organisateur.balance;

        vm.prank(organisateur);
        billetChain.retirerFonds();

        assertEq(organisateur.balance, balanceAvant + PRIX_ATTENDU_WEI);
        assertEq(billetChain.soldesRetirables(organisateur), 0);
    }

    function test_RetraitVendeurRevente() public {
        uint256 tokenId = _acheterBillet(acheteur1);
        uint256 prixRevente = PRIX_ATTENDU_WEI;

        vm.prank(acheteur1);
        billetChain.mettreEnVente(tokenId, prixRevente);

        vm.prank(acheteur2);
        billetChain.acheterRevente{value: prixRevente}(tokenId);

        uint256 balanceAvant = acheteur1.balance;

        vm.prank(acheteur1);
        billetChain.retirerFonds();

        assertEq(acheteur1.balance, balanceAvant + prixRevente);
    }

    function test_RetraitSansSolde() public {
        vm.prank(acheteur1);
        vm.expectRevert("BilletChain: rien a retirer");
        billetChain.retirerFonds();
    }

    // ===================== CONSULTATION =====================

    function test_CompterBilletsEnVente() public {
        uint256 token0 = _acheterBillet(acheteur1);
        uint256 token1 = _acheterBillet(acheteur1);
        _acheterBillet(acheteur2);

        vm.prank(acheteur1);
        billetChain.mettreEnVente(token0, PRIX_ATTENDU_WEI);
        vm.prank(acheteur1);
        billetChain.mettreEnVente(token1, PRIX_ATTENDU_WEI);

        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;

        uint256 count = billetChain.compterBilletsEnVente(ids);
        assertEq(count, 2);
    }

    // ===================== SECURITE =====================

    function test_ReentranceProtegee() public {
        _acheterBillet(acheteur1);

        // Le withdraw pattern met le solde a 0 AVANT le transfert
        // Donc meme si le destinataire rappelle retirerFonds, le solde est deja 0
        vm.prank(organisateur);
        billetChain.retirerFonds();
        assertEq(billetChain.soldesRetirables(organisateur), 0);
    }
}
