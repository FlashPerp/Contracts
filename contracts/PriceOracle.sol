// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { PythStructs } from "@pythnetwork/pyth-sdk-solidity/contracts/PythStructs.sol";
import { Pyth } from "@pythnetwork/pyth-sdk-solidity/contracts/Pyth.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PriceOracle is Ownable {
    Pyth public pyth;

    // Address of the Pyth contract
    constructor(address _pythAddress) {
        pyth = Pyth(_pythAddress);
    }

    event PriceFeedSet(bytes32 assetPair, bytes32 priceFeedId);

    mapping(bytes32 => bytes32) public priceFeedIds;

    function setPriceFeed(bytes32 assetPair, bytes32 priceFeedId) external onlyOwner {
        priceFeedIds[assetPair] = priceFeedId;
        emit PriceFeedSet(assetPair, assetPair);
    }

    function getPrice(bytes32 assetPair) external view returns (int256 price) {
        bytes32 priceFeedId = priceFeedIds[assetPair];
        require(priceFeedId != bytes32(0), "Price feed not set");

        PythStructs.Price memory priceData = pyth.getLatestPrice(priceFeedId);
        require(priceData.publishTime != 0, "Price data is stale");

        price = priceData.price;
    }
}