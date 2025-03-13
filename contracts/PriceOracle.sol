// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IPriceOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PriceOracle
 * @dev Implementation of the price oracle for the perpetual exchange
 * This contract provides price feeds for various asset pairs
 */
contract PriceOracle is IPriceOracle, Ownable {
    // Mapping from asset pair hash to price data
    struct PriceData {
        uint256 markPrice;
        uint256 indexPrice;
        uint256 lastUpdateTimestamp;
        bool isSupported;
    }
    
    mapping(bytes32 => PriceData) private prices;
    
    // Events
    event PriceUpdated(bytes32 indexed assetPair, uint256 markPrice, uint256 indexPrice);
    event AssetPairAdded(bytes32 indexed assetPair);
    event AssetPairRemoved(bytes32 indexed assetPair);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Returns the current price of an asset pair (mark price)
     * @param assetPair The hashed asset pair identifier
     * @return price The current price with 8 decimals precision
     */
    function getPrice(bytes32 assetPair) external view override returns (uint256 price) {
        require(prices[assetPair].isSupported, "Asset pair not supported");
        return prices[assetPair].markPrice;
    }
    
    /**
     * @dev Returns the mark price and index price for an asset pair
     * @param assetPair The hashed asset pair identifier
     * @return markPrice The current mark price with 8 decimals precision
     * @return indexPrice The current index price with 8 decimals precision
     */
    function getPrices(bytes32 assetPair) external view override returns (uint256 markPrice, uint256 indexPrice) {
        require(prices[assetPair].isSupported, "Asset pair not supported");
        return (prices[assetPair].markPrice, prices[assetPair].indexPrice);
    }
    
    /**
     * @dev Checks if an asset pair is supported by the oracle
     * @param assetPair The hashed asset pair identifier
     * @return True if the asset pair is supported, false otherwise
     */
    function isAssetPairSupported(bytes32 assetPair) external view override returns (bool) {
        return prices[assetPair].isSupported;
    }
    
    /**
     * @dev Updates the price for an asset pair
     * @param assetPair The hashed asset pair identifier
     * @param markPrice The new mark price with 8 decimals precision
     * @param indexPrice The new index price with 8 decimals precision
     */
    function updatePrice(bytes32 assetPair, uint256 markPrice, uint256 indexPrice) external onlyOwner {
        require(prices[assetPair].isSupported, "Asset pair not supported");
        require(markPrice > 0 && indexPrice > 0, "Prices must be greater than zero");
        
        prices[assetPair].markPrice = markPrice;
        prices[assetPair].indexPrice = indexPrice;
        prices[assetPair].lastUpdateTimestamp = block.timestamp;
        
        emit PriceUpdated(assetPair, markPrice, indexPrice);
    }
    
    /**
     * @dev Adds support for a new asset pair
     * @param assetPair The hashed asset pair identifier
     * @param initialMarkPrice The initial mark price with 8 decimals precision
     * @param initialIndexPrice The initial index price with 8 decimals precision
     */
    function addAssetPair(bytes32 assetPair, uint256 initialMarkPrice, uint256 initialIndexPrice) external onlyOwner {
        require(!prices[assetPair].isSupported, "Asset pair already supported");
        require(initialMarkPrice > 0 && initialIndexPrice > 0, "Initial prices must be greater than zero");
        
        prices[assetPair] = PriceData({
            markPrice: initialMarkPrice,
            indexPrice: initialIndexPrice,
            lastUpdateTimestamp: block.timestamp,
            isSupported: true
        });
        
        emit AssetPairAdded(assetPair);
        emit PriceUpdated(assetPair, initialMarkPrice, initialIndexPrice);
    }
    
    /**
     * @dev Removes support for an asset pair
     * @param assetPair The hashed asset pair identifier
     */
    function removeAssetPair(bytes32 assetPair) external onlyOwner {
        require(prices[assetPair].isSupported, "Asset pair not supported");
        
        prices[assetPair].isSupported = false;
        
        emit AssetPairRemoved(assetPair);
    }
    
    /**
     * @dev Gets the last update timestamp for an asset pair
     * @param assetPair The hashed asset pair identifier
     * @return timestamp The timestamp of the last price update
     */
    function getLastUpdateTimestamp(bytes32 assetPair) external view returns (uint256 timestamp) {
        require(prices[assetPair].isSupported, "Asset pair not supported");
        return prices[assetPair].lastUpdateTimestamp;
    }
}
