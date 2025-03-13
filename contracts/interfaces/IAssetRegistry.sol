// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IAssetRegistry
 * @dev Interface for the AssetRegistry contract that manages user assets and collateral
 */
interface IAssetRegistry {
    /**
     * @dev Transfers tokens from a user to the exchange contract
     * @param user The address of the user
     * @param token The address of the token being transferred
     * @param amount The amount of tokens to transfer
     * @return success True if the transfer was successful
     */
    function transferToExchange(address user, address token, uint256 amount) external returns (bool success);
    
    /**
     * @dev Transfers tokens from the exchange contract to a user
     * @param user The address of the user
     * @param token The address of the token being transferred
     * @param amount The amount of tokens to transfer
     * @return success True if the transfer was successful
     */
    function transferFromExchange(address user, address token, uint256 amount) external returns (bool success);
    
    /**
     * @dev Returns the balance of a specific token for a user
     * @param user The address of the user
     * @param token The address of the token
     * @return balance The user's balance of the specified token
     */
    function getBalance(address user, address token) external view returns (uint256 balance);
    
    /**
     * @dev Checks if a token is supported by the registry
     * @param token The address of the token
     * @return True if the token is supported, false otherwise
     */
    function isTokenSupported(address token) external view returns (bool);
    
    /**
     * @dev Gets the collateral token address for a specific asset pair
     * @param assetPair The hashed asset pair identifier
     * @return token The address of the collateral token
     */
    function getCollateralToken(bytes32 assetPair) external view returns (address token);
}
