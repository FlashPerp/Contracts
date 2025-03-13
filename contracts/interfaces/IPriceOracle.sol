// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IPriceOracle
 * @dev Interface for the PriceOracle contract that provides price feeds for the perpetual exchange
 */
interface IPriceOracle {
    /**
     * @dev Returns the current price of an asset pair
     * @param assetPair The hashed asset pair identifier (e.g., keccak256("ETH/USD"))
     * @return price The current price with 8 decimals precision
     */
    function getPrice(bytes32 assetPair) external view returns (uint256 price);
    
    /**
     * @dev Returns the mark price and index price for an asset pair
     * @param assetPair The hashed asset pair identifier
     * @return markPrice The current mark price with 8 decimals precision
     * @return indexPrice The current index price with 8 decimals precision
     */
    function getPrices(bytes32 assetPair) external view returns (uint256 markPrice, uint256 indexPrice);
    
    /**
     * @dev Checks if an asset pair is supported by the oracle
     * @param assetPair The hashed asset pair identifier
     * @return True if the asset pair is supported, false otherwise
     */
    function isAssetPairSupported(bytes32 assetPair) external view returns (bool);
}
