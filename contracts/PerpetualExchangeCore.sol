// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IPerpetualExchangeCore.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IAssetRegistry.sol";
import "./libraries/PerpMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PerpetualExchangeCore
 * @dev Core contract for the perpetual exchange that handles positions
 */
contract PerpetualExchangeCore is IPerpetualExchangeCore, Ownable, Pausable, ReentrancyGuard {
    // External contracts
    IPriceOracle public oracle;
    IAssetRegistry public assetRegistry;
    
    // Position storage
    mapping(uint256 => Position) public positions;
    uint256 public nextPositionId = 1;
    
    // Funding rate variables
    uint256 public fundingRateInterval = 8 hours; // 8 hours = 28800 seconds
    mapping(bytes32 => int256) public globalFundingRates;
    mapping(bytes32 => uint256) public lastFundingUpdateTime;
    uint256 public fundingRateFactor = 100; // Multiplier for funding rate calculation
    
    // Fee variables
    uint256 public maintenanceMarginRate = 200; // 2% = 200 basis points
    uint256 public liquidationFeeRate = 10; // 0.1% = 10 basis points
    uint256 public takerFeeRate = 10; // 0.1% = 10 basis points
    uint256 public makerFeeRate = 5; // 0.05% = 5 basis points
    address public treasury;
    
    // Asset pair support
    mapping(bytes32 => bool) public supportedAssets;
    
    // Max leverage allowed
    uint256 public maxLeverage = 100; // 100x
    
    // Events
    event PositionOpened(uint256 indexed positionId, address indexed trader, bytes32 indexed assetPair, bool isLong, uint256 collateral, uint256 size, uint256 entryPrice, uint256 leverage);
    event PositionClosed(uint256 indexed positionId, address indexed trader, bytes32 indexed assetPair, uint256 sizeReduced, int256 realizedPnl);
    event PositionIncreased(uint256 indexed positionId, address indexed trader, uint256 additionalCollateral, uint256 additionalSize);
    event PositionDecreased(uint256 indexed positionId, address indexed trader, uint256 sizeReduced, int256 realizedPnl);
    event FundingRateUpdated(bytes32 indexed assetPair, int256 fundingRate);
    event FundingApplied(uint256 indexed positionId, address indexed trader, int256 fundingPayment);
    event PositionLiquidated(uint256 indexed positionId, address indexed trader, address indexed liquidator, uint256 liquidationFee);
    event AssetPairAdded(bytes32 indexed assetPair);
    event AssetPairRemoved(bytes32 indexed assetPair);
    event OracleUpdated(address indexed newOracle);
    event AssetRegistryUpdated(address indexed newAssetRegistry);
    event TreasuryUpdated(address indexed newTreasury);
    event FeeRateUpdated(string feeType, uint256 newRate);
    event MaxLeverageUpdated(uint256 newMaxLeverage);
    
    /**
     * @dev Constructor
     * @param _oracle The address of the price oracle
     * @param _assetRegistry The address of the asset registry
     * @param _treasury The address of the treasury
     */
    constructor(
        address _oracle,
        address _assetRegistry,
        address _treasury
    ) Ownable(msg.sender) {
        require(_oracle != address(0), "Invalid oracle address");
        require(_assetRegistry != address(0), "Invalid asset registry address");
        require(_treasury != address(0), "Invalid treasury address");
        
        oracle = IPriceOracle(_oracle);
        assetRegistry = IAssetRegistry(_assetRegistry);
        treasury = _treasury;
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
    ) external override whenNotPaused nonReentrant returns (uint256 positionId) {
        // Input validation
        require(supportedAssets[assetPair], "Asset pair not supported");
        require(trader != address(0), "Invalid trader address");
        require(collateralAmount > 0, "Collateral must be greater than zero");
        require(size > 0, "Size must be greater than zero");
        require(leverage > 0 && leverage <= maxLeverage, "Invalid leverage");
        
        // Get current price from oracle
        uint256 currentPrice = oracle.getPrice(assetPair);
        
        // Calculate notional value
        uint256 notionalValue = PerpMath.calculateNotionalValue(size, currentPrice);
        
        // Check if collateral is sufficient based on leverage
        uint256 requiredCollateral = notionalValue / leverage;
        require(collateralAmount >= requiredCollateral, "Insufficient collateral for leverage");
        
        // Check funding rate
        int256 currentFundingRate = globalFundingRates[assetPair];
        if (currentFundingRate > 0) {
            require(uint256(currentFundingRate) <= maxFundingRate, "Funding rate exceeds maximum");
        }
        
        // Get collateral token for the asset pair
        address collateralToken = assetRegistry.getCollateralToken(assetPair);
        
        // Transfer collateral from user to exchange
        require(
            assetRegistry.transferToExchange(trader, collateralToken, collateralAmount),
            "Collateral transfer failed"
        );
        
        // Create new position
        positionId = nextPositionId++;
        
        positions[positionId] = Position({
            positionId: positionId,
            trader: trader,
            assetPair: assetPair,
            isLong: isLong,
            collateral: collateralAmount,
            size: size,
            entryPrice: currentPrice,
            lastFundingTimestamp: block.timestamp,
            accumulatedFunding: 0,
            leverage: leverage
        });
        
        // Take taker fee
        uint256 takerFee = (notionalValue * takerFeeRate) / PerpMath.BASIS_POINTS_DIVISOR;
        
        // Emit event
        emit PositionOpened(
            positionId,
            trader,
            assetPair,
            isLong,
            collateralAmount,
            size,
            currentPrice,
            leverage
        );
        
        return positionId;
    }
    
    /**
     * @dev Closes part or all of a position
     * @param positionId The ID of the position to close
     * @param sizeToClose The amount of the position to close
     * @return realizedPnl The realized profit or loss from closing the position
     */
    function closePosition(uint256 positionId, uint256 sizeToClose) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        returns (int256 realizedPnl) 
    {
        // Input validation
        Position storage position = positions[positionId];
        require(position.trader != address(0), "Position does not exist");
        require(msg.sender == position.trader, "Not position owner");
        require(sizeToClose > 0 && sizeToClose <= position.size, "Invalid size to close");
        
        // Apply funding before closing
        applyFunding(positionId);
        
        // Get current price from oracle
        uint256 currentPrice = oracle.getPrice(position.assetPair);
        
        // Calculate realized PnL
        realizedPnl = PerpMath.calculatePnL(
            sizeToClose,
            position.entryPrice,
            currentPrice,
            position.isLong
        );
        
        // Calculate proportion of collateral to return
        uint256 collateralToReturn = (position.collateral * sizeToClose) / position.size;
        
        // Get collateral token for the asset pair
        address collateralToken = assetRegistry.getCollateralToken(position.assetPair);
        
        // Update position
        if (sizeToClose == position.size) {
            // Full close - delete position
            delete positions[positionId];
        } else {
            // Partial close - update position
            position.size -= sizeToClose;
            position.collateral -= collateralToReturn;
        }
        
        // Calculate final amount to return (collateral +/- PnL)
        uint256 amountToReturn;
        if (realizedPnl >= 0) {
            amountToReturn = collateralToReturn + uint256(realizedPnl);
        } else {
            uint256 loss = uint256(-realizedPnl);
            amountToReturn = loss >= collateralToReturn ? 0 : collateralToReturn - loss;
        }
        
        // Transfer funds back to user
        if (amountToReturn > 0) {
            require(
                assetRegistry.transferFromExchange(position.trader, collateralToken, amountToReturn),
                "Return transfer failed"
            );
        }
        
        // Emit event
        emit PositionClosed(
            positionId,
            position.trader,
            position.assetPair,
            sizeToClose,
            realizedPnl
        );
        
        return realizedPnl;
    }
    
    /**
     * @dev Increases an existing position
     * @param positionId The ID of the position to increase
     * @param additionalCollateral The additional collateral to add
     * @param additionalSize The additional size to add
     */
    function increasePosition(
        uint256 positionId,
        uint256 additionalCollateral,
        uint256 additionalSize
    ) external override whenNotPaused nonReentrant {
        // Input validation
        Position storage position = positions[positionId];
        require(position.trader != address(0), "Position does not exist");
        require(msg.sender == position.trader, "Not position owner");
        require(additionalSize > 0, "Additional size must be greater than zero");
        
        // Apply funding before increasing
        applyFunding(positionId);
        
        // Get current price from oracle
        uint256 currentPrice = oracle.getPrice(position.assetPair);
        
        // Calculate additional notional value
        uint256 additionalNotional = PerpMath.calculateNotionalValue(additionalSize, currentPrice);
        
        // Check if additional collateral is sufficient based on leverage
        uint256 requiredAdditionalCollateral = additionalNotional / position.leverage;
        require(additionalCollateral >= requiredAdditionalCollateral, "Insufficient additional collateral");
        
        // Get collateral token for the asset pair
        address collateralToken = assetRegistry.getCollateralToken(position.assetPair);
        
        // Transfer additional collateral from user to exchange
        if (additionalCollateral > 0) {
            require(
                assetRegistry.transferToExchange(position.trader, collateralToken, additionalCollateral),
                "Collateral transfer failed"
            );
        }
        
        // Calculate new average entry price
        uint256 totalSize = position.size + additionalSize;
        uint256 newEntryPrice = (position.entryPrice * position.size + currentPrice * additionalSize) / totalSize;
        
        // Update position
        position.collateral += additionalCollateral;
        position.size += additionalSize;
        position.entryPrice = newEntryPrice;
        
        // Emit event
        emit PositionIncreased(
            positionId,
            position.trader,
            additionalCollateral,
            additionalSize
        );
    }
    
    /**
     * @dev Decreases an existing position without closing it
     * @param positionId The ID of the position to decrease
     * @param sizeToReduce The amount of the position to reduce
     * @return realizedPnl The realized profit or loss from reducing the position
     */
    function decreasePosition(uint256 positionId, uint256 sizeToReduce) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        returns (int256 realizedPnl) 
    {
        // Input validation
        Position storage position = positions[positionId];
        require(position.trader != address(0), "Position does not exist");
        require(msg.sender == position.trader, "Not position owner");
        require(sizeToReduce > 0 && sizeToReduce < position.size, "Invalid size to reduce");
        
        // Apply funding before decreasing
        applyFunding(positionId);
        
        // Get current price from oracle
        uint256 currentPrice = oracle.getPrice(position.assetPair);
        
        // Calculate realized PnL
        realizedPnl = PerpMath.calculatePnL(
            sizeToReduce,
            position.entryPrice,
            currentPrice,
            position.isLong
        );
        
        // Calculate proportion of collateral to return
        uint256 collateralToReturn = (position.collateral * sizeToReduce) / position.size;
        
        // Get collateral token for the asset pair
        address collateralToken = assetRegistry.getCollateralToken(position.assetPair);
        
        // Update position
        position.size -= sizeToReduce;
        position.collateral -= collateralToReturn;
        
        // Calculate final amount to return (collateral +/- PnL)
        uint256 amountToReturn;
        if (realizedPnl >= 0) {
            amountToReturn = collateralToReturn + uint256(realizedPnl);
        } else {
            uint256 loss = uint256(-realizedPnl);
            amountToReturn = loss >= collateralToReturn ? 0 : collateralToReturn - loss;
        }
        
        // Transfer funds back to user
        if (amountToReturn > 0) {
            require(
                assetRegistry.transferFromExchange(position.trader, collateralToken, amountToReturn),
                "Return transfer failed"
            );
        }
        
        // Emit event
        emit PositionDecreased(
            positionId,
            position.trader,
            sizeToReduce,
            realizedPnl
        );
        
        return realizedPnl;
    }
    
    /**
     * @dev Updates the global funding rates for all supported asset pairs
     */
    function updateFundingRates() external override whenNotPaused {
        bytes32[] memory assetPairs = getSupportedAssetPairs();
        
        for (uint256 i = 0; i < assetPairs.length; i++) {
            bytes32 assetPair = assetPairs[i];
            
            // Check if enough time has passed since the last update
            if (block.timestamp >= lastFundingUpdateTime[assetPair] + fundingRateInterval) {
                // Get prices from oracle
                (uint256 markPrice, uint256 indexPrice) = oracle.getPrices(assetPair);
                
                // Calculate new funding rate
                int256 newFundingRate = PerpMath.calculateFundingRate(
                    markPrice,
                    indexPrice,
                    fundingRateFactor
                );
                
                // Update global funding rate and timestamp
                globalFundingRates[assetPair] = newFundingRate;
                lastFundingUpdateTime[assetPair] = block.timestamp;
                
                // Emit event
                emit FundingRateUpdated(assetPair, newFundingRate);
            }
        }
    }
    
    /**
     * @dev Applies accumulated funding to a specific position
     * @param positionId The ID of the position
     * @return fundingPayment The amount of funding paid or received
     */
    function applyFunding(uint256 positionId) public override whenNotPaused returns (int256 fundingPayment) {
        Position storage position = positions[positionId];
        require(position.trader != address(0), "Position does not exist");
        
        // If no time has passed, no funding to apply
        if (block.timestamp <= position.lastFundingTimestamp) {
            return 0;
        }
        
        // Get the global funding rate for this asset pair
        int256 fundingRate = globalFundingRates[position.assetPair];
        
        // Calculate time elapsed since last funding payment
        uint256 timeElapsed = block.timestamp - position.lastFundingTimestamp;
        
        // Calculate number of funding intervals passed
        uint256 intervals = timeElapsed / fundingRateInterval;
        
        if (intervals > 0) {
            // Calculate funding payment
            fundingPayment = PerpMath.calculateFundingPayment(
                position.size,
                fundingRate * int256(intervals),
                position.isLong
            );
            
            // Update position's accumulated funding
            position.accumulatedFunding += fundingPayment;
            
            // Update last funding timestamp
            position.lastFundingTimestamp = block.timestamp;
            
            // Emit event
            emit FundingApplied(positionId, position.trader, fundingPayment);
        }
        
        return fundingPayment;
    }
    
    /**
     * @dev Liquidates an undercollateralized position
     * @param positionId The ID of the position to liquidate
     * @return liquidationFee The fee earned for liquidating the position
     */
    function liquidatePosition(uint256 positionId) 
        external 
        override 
        whenNotPaused 
        nonReentrant 
        returns (uint256 liquidationFee) 
    {
        // Check if position is liquidatable
        require(isLiquidatable(positionId), "Position not liquidatable");
        
        Position storage position = positions[positionId];
        
        // Apply funding before liquidation
        applyFunding(positionId);
        
        // Get current price from oracle
        uint256 currentPrice = oracle.getPrice(position.assetPair);
        
        // Calculate PnL
        int256 pnl = PerpMath.calculatePnL(
            position.size,
            position.entryPrice,
            currentPrice,
            position.isLong
        );
        
        // Calculate liquidation fee
        uint256 notionalValue = PerpMath.calculateNotionalValue(position.size, currentPrice);
        liquidationFee = (notionalValue * liquidationFeeRate) / PerpMath.BASIS_POINTS_DIVISOR;
        
        // Get collateral token for the asset pair
        address collateralToken = assetRegistry.getCollateralToken(position.assetPair);
        
        // Calculate remaining collateral after PnL
        uint256 remainingCollateral;
        if (pnl >= 0) {
            remainingCollateral = position.collateral + uint256(pnl);
        } else {
            uint256 loss = uint256(-pnl);
            remainingCollateral = loss >= position.collateral ? 0 : position.collateral - loss;
        }
        
        // Transfer liquidation fee to liquidator
        if (liquidationFee > 0 && liquidationFee <= remainingCollateral) {
            require(
                assetRegistry.transferFromExchange(msg.sender, collateralToken, liquidationFee),
                "Liquidation fee transfer failed"
            );
        }
        
        // Transfer remaining collateral to trader
        uint256 remainingAmount = remainingCollateral > liquidationFee ? remainingCollateral - liquidationFee : 0;
        if (remainingAmount > 0) {
            require(
                assetRegistry.transferFromExchange(position.trader, collateralToken, remainingAmount),
                "Remaining collateral transfer failed"
            );
        }
        
        // Emit event
        emit PositionLiquidated(
            positionId,
            position.trader,
            msg.sender,
            liquidationFee
        );
        
        // Delete position
        delete positions[positionId];
        
        return liquidationFee;
    }
    
    /**
     * @dev Gets information about a position
     * @param positionId The ID of the position
     * @return The position struct
     */
    function getPosition(uint256 positionId) 
        external 
        view 
        override 
        returns (Position memory) 
    {
        return positions[positionId];
    }
    
    /**
     * @dev Checks if a position is liquidatable
     * @param positionId The ID of the position
     * @return True if the position can be liquidated, false otherwise
     */
    function isLiquidatable(uint256 positionId) public view override returns (bool) {
        Position storage position = positions[positionId];
        if (position.trader == address(0)) {
            return false;
        }
        
        // Get current price from oracle
        uint256 currentPrice = oracle.getPrice(position.assetPair);
        
        // Calculate PnL
        int256 pnl = PerpMath.calculatePnL(
            position.size,
            position.entryPrice,
            currentPrice,
            position.isLong
        );
        
        // Calculate effective collateral (collateral + PnL)
        uint256 effectiveCollateral;
        if (pnl >= 0) {
            effectiveCollateral = position.collateral + uint256(pnl);
        } else {
            uint256 loss = uint256(-pnl);
            effectiveCollateral = loss >= position.collateral ? 0 : position.collateral - loss;
        }
        
        // Calculate required maintenance margin
        uint256 notionalValue = PerpMath.calculateNotionalValue(position.size, currentPrice);
        uint256 requiredMargin = PerpMath.calculateRequiredMargin(notionalValue, maintenanceMarginRate);
        
        // Position is liquidatable if effective collateral is less than required margin
        return effectiveCollateral < requiredMargin;
    }
    
    /**
     * @dev Gets all supported asset pairs
     * @return An array of supported asset pairs
     */
    function getSupportedAssetPairs() public view returns (bytes32[] memory) {
        // Count supported assets
        uint256 count = 0;
        bytes32[] memory tempPairs = new bytes32[](100); // Temporary array with arbitrary size
        
        // Iterate through all asset pairs (this is a simplified approach)
        // In a production environment, you would maintain a separate array or mapping for efficient retrieval
        for (uint256 i = 0; i < 100; i++) {
            bytes32 assetPair = bytes32(i);
            if (supportedAssets[assetPair]) {
                tempPairs[count] = assetPair;
                count++;
            }
        }
        
        // Create correctly sized array
        bytes32[] memory result = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tempPairs[i];
        }
        
        return result;
    }
    
    // Admin functions
    
    /**
     * @dev Adds support for a new asset pair
     * @param assetPair The asset pair to add
     */
    function addAssetPair(bytes32 assetPair) external onlyOwner {
        require(!supportedAssets[assetPair], "Asset pair already supported");
        require(oracle.isAssetPairSupported(assetPair), "Asset pair not supported by oracle");
        
        supportedAssets[assetPair] = true;
        lastFundingUpdateTime[assetPair] = block.timestamp;
        
        emit AssetPairAdded(assetPair);
    }
    
    /**
     * @dev Removes support for an asset pair
     * @param assetPair The asset pair to remove
     */
    function removeAssetPair(bytes32 assetPair) external onlyOwner {
        require(supportedAssets[assetPair], "Asset pair not supported");
        
        supportedAssets[assetPair] = false;
        
        emit AssetPairRemoved(assetPair);
    }
    
    /**
     * @dev Sets the oracle address
     * @param newOracle The new oracle address
     */
    function setOracle(address newOracle) external onlyOwner {
        require(newOracle != address(0), "Invalid oracle address");
        
        oracle = IPriceOracle(newOracle);
        
        emit OracleUpdated(newOracle);
    }
    
    /**
     * @dev Sets the asset registry address
     * @param newAssetRegistry The new asset registry address
     */
    function setAssetRegistry(address newAssetRegistry) external onlyOwner {
        require(newAssetRegistry != address(0), "Invalid asset registry address");
        
        assetRegistry = IAssetRegistry(newAssetRegistry);
        
        emit AssetRegistryUpdated(newAssetRegistry);
    }
    
    /**
     * @dev Sets the treasury address
     * @param newTreasury The new treasury address
     */
    function setTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury address");
        
        treasury = newTreasury;
        
        emit TreasuryUpdated(newTreasury);
    }
    
    /**
     * @dev Sets the maintenance margin rate
     * @param newRate The new maintenance margin rate in basis points
     */
    function setMaintenanceMarginRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Invalid maintenance margin rate");
        
        maintenanceMarginRate = newRate;
        
        emit FeeRateUpdated("MaintenanceMargin", newRate);
    }
    
    /**
     * @dev Sets the liquidation fee rate
     * @param newRate The new liquidation fee rate in basis points
     */
    function setLiquidationFeeRate(uint256 newRate) external onlyOwner {
        liquidationFeeRate = newRate;
        
        emit FeeRateUpdated("LiquidationFee", newRate);
    }
    
    /**
     * @dev Sets the taker fee rate
     * @param newRate The new taker fee rate in basis points
     */
    function setTakerFeeRate(uint256 newRate) external onlyOwner {
        takerFeeRate = newRate;
        
        emit FeeRateUpdated("TakerFee", newRate);
    }
    
    /**
     * @dev Sets the maker fee rate
     * @param newRate The new maker fee rate in basis points
     */
    function setMakerFeeRate(uint256 newRate) external onlyOwner {
        makerFeeRate = newRate;
        
        emit FeeRateUpdated("MakerFee", newRate);
    }
    
    /**
     * @dev Sets the funding rate interval
     * @param newInterval The new funding rate interval in seconds
     */
    function setFundingRateInterval(uint256 newInterval) external onlyOwner {
        require(newInterval > 0, "Invalid funding rate interval");
        
        fundingRateInterval = newInterval;
    }
    
    /**
     * @dev Sets the funding rate factor
     * @param newFactor The new funding rate factor
     */
    function setFundingRateFactor(uint256 newFactor) external onlyOwner {
        require(newFactor > 0, "Invalid funding rate factor");
        
        fundingRateFactor = newFactor;
    }
    
    /**
     * @dev Sets the maximum allowed leverage
     * @param newMaxLeverage The new maximum leverage
     */
    function setMaxLeverage(uint256 newMaxLeverage) external onlyOwner {
        require(newMaxLeverage > 0, "Invalid max leverage");
        
        maxLeverage = newMaxLeverage;
        
        emit MaxLeverageUpdated(newMaxLeverage);
    }
    
    /**
     * @dev Pauses the contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev Unpauses the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
