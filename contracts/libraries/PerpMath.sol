// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title PerpMath
 * @dev Library for math operations used in the perpetual exchange
 */
library PerpMath {
    // Constants for fixed-point calculations
    uint256 public constant PRICE_PRECISION = 1e8;  // 8 decimals for price
    uint256 public constant BASIS_POINTS_DIVISOR = 10000; // 100% = 10000 basis points
    
    /**
     * @dev Calculates the notional value of a position
     * @param size The size of the position
     * @param price The price of the asset
     * @return The notional value
     */
    function calculateNotionalValue(uint256 size, uint256 price) internal pure returns (uint256) {
        return (size * price) / PRICE_PRECISION;
    }
    
    /**
     * @dev Calculates the required margin for a position
     * @param notionalValue The notional value of the position
     * @param marginRate The margin rate in basis points
     * @return The required margin
     */
    function calculateRequiredMargin(uint256 notionalValue, uint256 marginRate) internal pure returns (uint256) {
        return (notionalValue * marginRate) / BASIS_POINTS_DIVISOR;
    }
    
    /**
     * @dev Calculates the PnL for a position
     * @param size The size of the position
     * @param entryPrice The entry price of the position
     * @param currentPrice The current price of the asset
     * @param isLong Whether the position is long or short
     * @return The PnL (positive for profit, negative for loss)
     */
    function calculatePnL(
        uint256 size,
        uint256 entryPrice,
        uint256 currentPrice,
        bool isLong
    ) internal pure returns (int256) {
        if (isLong) {
            if (currentPrice > entryPrice) {
                return int256((size * (currentPrice - entryPrice)) / PRICE_PRECISION);
            } else {
                return -int256((size * (entryPrice - currentPrice)) / PRICE_PRECISION);
            }
        } else {
            if (entryPrice > currentPrice) {
                return int256((size * (entryPrice - currentPrice)) / PRICE_PRECISION);
            } else {
                return -int256((size * (currentPrice - entryPrice)) / PRICE_PRECISION);
            }
        }
    }
    
    /**
     * @dev Calculates the funding rate
     * @param markPrice The mark price of the asset
     * @param indexPrice The index price of the asset
     * @param fundingRateFactor The funding rate factor
     * @return The funding rate in basis points
     */
    function calculateFundingRate(
        uint256 markPrice,
        uint256 indexPrice,
        uint256 fundingRateFactor
    ) internal pure returns (int256) {
        if (markPrice > indexPrice) {
            return int256((markPrice - indexPrice) * fundingRateFactor / indexPrice);
        } else {
            return -int256((indexPrice - markPrice) * fundingRateFactor / indexPrice);
        }
    }
    
    /**
     * @dev Calculates the funding payment for a position
     * @param size The size of the position
     * @param fundingRate The funding rate in basis points
     * @param isLong Whether the position is long or short
     * @return The funding payment (positive means the user pays, negative means the user receives)
     */
    function calculateFundingPayment(
        uint256 size,
        int256 fundingRate,
        bool isLong
    ) internal pure returns (int256) {
        int256 payment = (int256(size) * fundingRate) / int256(BASIS_POINTS_DIVISOR);
        
        // Long positions pay when funding rate is positive, receive when negative
        // Short positions receive when funding rate is positive, pay when negative
        return isLong ? payment : -payment;
    }
    
    /**
     * @dev Calculates the liquidation price for a position
     * @param size The size of the position
     * @param collateral The collateral amount
     * @param entryPrice The entry price of the position
     * @param maintenanceMarginRate The maintenance margin rate in basis points
     * @param isLong Whether the position is long or short
     * @return The liquidation price
     */
    function calculateLiquidationPrice(
        uint256 size,
        uint256 collateral,
        uint256 entryPrice,
        uint256 maintenanceMarginRate,
        bool isLong
    ) internal pure returns (uint256) {
        uint256 notionalValue = calculateNotionalValue(size, entryPrice);
        uint256 maintenanceMargin = calculateRequiredMargin(notionalValue, maintenanceMarginRate);
        
        if (isLong) {
            // For long positions, liquidation price is lower than entry price
            uint256 priceDrop = (collateral - maintenanceMargin) * PRICE_PRECISION / size;
            return priceDrop >= entryPrice ? 0 : entryPrice - priceDrop;
        } else {
            // For short positions, liquidation price is higher than entry price
            uint256 priceIncrease = (collateral - maintenanceMargin) * PRICE_PRECISION / size;
            return entryPrice + priceIncrease;
        }
    }
}
