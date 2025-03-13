// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IPerpetualExchangeCore
 * @dev Interface for the PerpetualExchangeCore contract that handles perpetual positions
 */
interface IPerpetualExchangeCore {
    /**
     * @dev Struct representing a perpetual position
     */
    struct Position {
        uint256 positionId;      // Unique ID for the position
        address trader;          // Address of the user who owns the position
        bytes32 assetPair;       // Hash of the asset pair (e.g., keccak256("ETH/USD"))
        bool isLong;             // True if long, false if short
        uint256 collateral;      // Amount of collateral deposited (in the collateral token's smallest unit)
        uint256 size;            // Size of the position (in units of the underlying asset)
        uint256 entryPrice;      // Average entry price of the position
        uint256 lastFundingTimestamp; // Timestamp of the last funding payment
        int256 accumulatedFunding;  // Accumulated funding owed (positive or negative)
        uint256 leverage;        // The leverage
    }
    
    /**
     * @dev Opens a new perpetual position
     * @param trader The address of the user who submitted the intent
     * @param assetPair The asset pair being traded (hashed using keccak256)
     * @param isLong True for a long position, false for a short position
     * @param collateralAmount The amount of collateral being deposited
     * @param size The desired size of the position
     * @param leverage The user's requested leverage
     * @param maxFundingRate The maximum acceptable funding rate
     * @param slippageTolerance The maximum allowable slippage
     * @return positionId The ID of the newly created position
     */
    function openPosition(
        address trader,
        bytes32 assetPair,
        bool isLong,
        uint256 collateralAmount,
        uint256 size,
        uint256 leverage,
        uint256 maxFundingRate,
        uint256 slippageTolerance
    ) external returns (uint256 positionId);
    
    /**
     * @dev Closes part or all of a position
     * @param positionId The ID of the position to close
     * @param sizeToClose The amount of the position to close
     * @return realizedPnl The realized profit or loss from closing the position
     */
    function closePosition(uint256 positionId, uint256 sizeToClose) external returns (int256 realizedPnl);
    
    /**
     * @dev Increases an existing position
     * @param positionId The ID of the position to increase
     * @param additionalCollateral The additional collateral to add
     * @param additionalSize The additional size to add
     */
    function increasePosition(uint256 positionId, uint256 additionalCollateral, uint256 additionalSize) external;
    
    /**
     * @dev Decreases an existing position without closing it
     * @param positionId The ID of the position to decrease
     * @param sizeToReduce The amount of the position to reduce
     * @return realizedPnl The realized profit or loss from reducing the position
     */
    function decreasePosition(uint256 positionId, uint256 sizeToReduce) external returns (int256 realizedPnl);
    
    /**
     * @dev Updates the global funding rates for all supported asset pairs
     */
    function updateFundingRates() external;
    
    /**
     * @dev Applies accumulated funding to a specific position
     * @param positionId The ID of the position
     * @return fundingPayment The amount of funding paid or received
     */
    function applyFunding(uint256 positionId) external returns (int256 fundingPayment);
    
    /**
     * @dev Liquidates an undercollateralized position
     * @param positionId The ID of the position to liquidate
     * @return liquidationFee The fee earned for liquidating the position
     */
    function liquidatePosition(uint256 positionId) external returns (uint256 liquidationFee);
    
    /**
     * @dev Gets information about a position
     * @param positionId The ID of the position
     * @return The position struct
     */
    function getPosition(uint256 positionId) external view returns (Position memory);
    
    /**
     * @dev Checks if a position is liquidatable
     * @param positionId The ID of the position
     * @return True if the position can be liquidated, false otherwise
     */
    function isLiquidatable(uint256 positionId) external view returns (bool);
}
