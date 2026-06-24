// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPriceOracle {
    function getEurToWei() external view returns (uint256 rate, uint256 updatedAt);
}

contract PriceOracle is IPriceOracle {
    address public owner;
    uint256 public rate; // 1 EUR = combien de wei
    uint256 public updatedAt;

    event RateUpdated(uint256 newRate, uint256 timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "PriceOracle: pas le proprietaire");
        _;
    }

    constructor(uint256 _initialRate) {
        require(_initialRate > 0, "PriceOracle: taux invalide");
        owner = msg.sender;
        rate = _initialRate;
        updatedAt = block.timestamp;
    }

    function updateRate(uint256 _newRate) external onlyOwner {
        require(_newRate > 0, "PriceOracle: taux invalide");
        rate = _newRate;
        updatedAt = block.timestamp;
        emit RateUpdated(_newRate, block.timestamp);
    }

    function getEurToWei() external view returns (uint256, uint256) {
        return (rate, updatedAt);
    }
}
