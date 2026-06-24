// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IPriceOracle} from "./PriceOracle.sol";

contract BilletChain is ERC721 {
    address public organisateur;
    IPriceOracle public oracle;

    uint256 public prixEnEuroCentimes; // prix en centimes d'euro (ex: 5000 = 50,00 EUR)
    uint256 public maxBillets;
    uint256 public billetsVendus;

    uint256 public constant MAX_ORACLE_AGE = 1 hours;
    uint256 public constant PLAFOND_REVENTE_BPS = 11000; // 110% en basis points (base 10000)

    struct Listing {
        bool enVente;
        uint256 prix; // prix en wei
    }

    mapping(uint256 => uint256) public prixInitial; // tokenId => prix payé en wei
    mapping(uint256 => Listing) public listings;
    mapping(address => uint256) public soldesRetirables;

    event BilletAchete(address indexed acheteur, uint256 indexed tokenId, uint256 prixWei);
    event BilletMisEnVente(uint256 indexed tokenId, uint256 prix);
    event BilletRetireDeLaVente(uint256 indexed tokenId);
    event BilletRevendu(address indexed vendeur, address indexed acheteur, uint256 indexed tokenId, uint256 prix);
    event FondsRetires(address indexed destinataire, uint256 montant);

    modifier seulOrganisateur() {
        require(msg.sender == organisateur, "BilletChain: pas l'organisateur");
        _;
    }

    constructor(
        string memory _nom,
        string memory _symbole,
        uint256 _maxBillets,
        uint256 _prixEnEuroCentimes,
        address _oracle
    ) ERC721(_nom, _symbole) {
        require(_maxBillets > 0, "BilletChain: nb billets invalide");
        require(_prixEnEuroCentimes > 0, "BilletChain: prix invalide");
        require(_oracle != address(0), "BilletChain: oracle invalide");

        organisateur = msg.sender;
        maxBillets = _maxBillets;
        prixEnEuroCentimes = _prixEnEuroCentimes;
        oracle = IPriceOracle(_oracle);
    }

    // --- VENTE INITIALE ---

    function getPrixEnWei() public view returns (uint256) {
        (uint256 tauxParEur, uint256 updatedAt) = oracle.getEurToWei();
        require(tauxParEur > 0, "BilletChain: taux oracle invalide");
        require(block.timestamp - updatedAt <= MAX_ORACLE_AGE, "BilletChain: taux oracle perime");
        return (prixEnEuroCentimes * tauxParEur) / 100;
    }

    function acheterBillet() external payable {
        require(billetsVendus < maxBillets, "BilletChain: complet");

        uint256 prix = getPrixEnWei();
        require(msg.value == prix, "BilletChain: montant incorrect");

        uint256 tokenId = billetsVendus;
        billetsVendus++;

        prixInitial[tokenId] = prix;
        soldesRetirables[organisateur] += prix;

        _safeMint(msg.sender, tokenId);

        emit BilletAchete(msg.sender, tokenId, prix);
    }

    // --- REVENTE (MARCHE SECONDAIRE) ---

    function mettreEnVente(uint256 _tokenId, uint256 _prix) external {
        require(ownerOf(_tokenId) == msg.sender, "BilletChain: pas proprietaire");
        require(
            _prix <= (prixInitial[_tokenId] * PLAFOND_REVENTE_BPS) / 10000,
            "BilletChain: prix depasse le plafond de 110%"
        );
        require(_prix > 0, "BilletChain: prix doit etre > 0");

        approve(address(this), _tokenId);

        listings[_tokenId] = Listing({enVente: true, prix: _prix});

        emit BilletMisEnVente(_tokenId, _prix);
    }

    function retirerDeLaVente(uint256 _tokenId) external {
        require(ownerOf(_tokenId) == msg.sender, "BilletChain: pas proprietaire");
        require(listings[_tokenId].enVente, "BilletChain: pas en vente");

        delete listings[_tokenId];

        emit BilletRetireDeLaVente(_tokenId);
    }

    function acheterRevente(uint256 _tokenId) external payable {
        Listing memory listing = listings[_tokenId];
        require(listing.enVente, "BilletChain: billet pas en vente");

        address vendeur = ownerOf(_tokenId);
        require(msg.value == listing.prix, "BilletChain: montant incorrect");

        delete listings[_tokenId];

        soldesRetirables[vendeur] += msg.value;

        this.safeTransferFrom(vendeur, msg.sender, _tokenId);

        emit BilletRevendu(vendeur, msg.sender, _tokenId, msg.value);
    }

    // --- ENCAISSEMENT (WITHDRAW PATTERN) ---

    function retirerFonds() external {
        uint256 montant = soldesRetirables[msg.sender];
        require(montant > 0, "BilletChain: rien a retirer");

        soldesRetirables[msg.sender] = 0;

        (bool succes,) = payable(msg.sender).call{value: montant}("");
        require(succes, "BilletChain: echec du transfert");

        emit FondsRetires(msg.sender, montant);
    }

    // --- CONSULTATION ---

    function compterBilletsEnVente(uint256[] calldata _tokenIds) external view returns (uint256 count) {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            if (listings[_tokenIds[i]].enVente) {
                count++;
            }
        }
    }
}
