// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AssetRegistry.sol";
import "./PriceOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PerpetualExchangeCore is Ownable {

    address public oracle;
    address public assetRegistry;
    
    struct Position {
        uint256 positionId;
        address trader;
        bytes32 assetPair;
        bool isLong;
        uint256 collateral;
        uint256 size;
        uint256 entryPrice;
        uint256 lastFundingTimestamp;
        uint256 accumulatedFunding;
        uint256 leverage;
    }

    mapping(uint256 => Position) public positions;
    uint256 public nextPositionId;
    uint256 public fundingRateInterval;
    mapping(bytes32 => int256) public globalFundingRates;
    mapping(bytes32 => uint256) public lastFundingUpdateTime;
    uint256 public maintenanceMarginRate;
    uint256 public liquidationFeeRate;
    uint256 public takerFeeRate;
    uint256 public makerFeeRate;
    address public treasury;
    bool public paused;
    mapping(bytes32 => bool) public supportedAssets;

    event PositionOpened(uint256 positionId, address trader, bytes32 assetPair, bool isLong, uint256 collateral, uint256 size, uint256 entryPrice, uint256 leverage);
    event PositionClosed(uint256 positionId, address trader, uint256 realizedPnL);
    event PositionIncreased(uint256 positionId, address trader, uint256 addedCollateral, uint256 addedSize);
    event PositionDecreased(uint256 positionId, address trader, uint256 reducedSize);
    event FundingRatesUpdated(bytes32 assetPair, int256 fundingRate);
    event FundingApplied(uint256 positionId, address trader, int256 fundingAmount);
    event PositionLiquidated(uint256 positionId, address trader, uint256 remainingCollateral, uint256 liquidationFee);
    event OracleUpdated(address oldOracle, address newOracle);
    event AssetRegistryUpdated(address oldRegistry, address newRegistry);
    event ParametersUpdated();
    event Paused();
    event Unpaused();
    event SupportedAssetAdded(bytes32 assetPair);
    event SupportedAssetRemoved(bytes32 assetPair);

    constructor(address _oracle, address _assetRegistry) {
        oracle = _oracle;
        assetRegistry = _assetRegistry;
        nextPositionId = 1;
    }

    function openPosition(address trader, bytes32 assetPair, bool isLong, uint256 collateralAmount, uint256 size, uint256 leverage, uint256 maxFundingRate, uint256 slippageTolerance) external {
        // ... implementation ...
        emit PositionOpened(nextPositionId, trader, assetPair, isLong, collateralAmount, size, 0, leverage);
    }

    function closePosition(uint256 positionId, uint256 sizeToClose) external {
        // ... implementation ...
        emit PositionClosed(positionId, msg.sender, 0);
    }

    function increasePosition(uint256 positionId, uint256 additionalCollateral, uint256 additionalSize) external {
        // ... implementation ...
        emit PositionIncreased(positionId, msg.sender, additionalCollateral, additionalSize);
    }

    function decreasePosition(uint256 positionId, uint256 sizeToReduce) external {
        // ... implementation ...
        emit PositionDecreased(positionId, msg.sender, reducedSize);
    }

    function updateFundingRates() external {
        // ... implementation ...
        emit FundingRatesUpdated("ETH/USD", 0);
    }

    function applyFunding() external {
        // ... implementation ...
        emit FundingApplied(1, msg.sender, 0);
    }

    function liquidatePosition(uint256 positionId) external {
        // ... implementation ...
        emit PositionLiquidated(positionId, msg.sender, 0, 0);
    }

    function setOracle(address newOracle) external {
        emit OracleUpdated(oracle, newOracle);
        oracle = newOracle;
    }

    function setAssetRegistry(address newRegistry) external {
        emit AssetRegistryUpdated(assetRegistry, newRegistry);
        assetRegistry = newRegistry;
    }

    function setParameters(uint256 _maintenanceMarginRate, uint256 _liquidationFeeRate, uint256 _fundingRateInterval, uint256 _takerFeeRate, uint256 _makerFeeRate, address _treasury) external {
        maintenanceMarginRate = _maintenanceMarginRate;
        liquidationFeeRate = _liquidationFeeRate;
        fundingRateInterval = _fundingRateInterval;
        takerFeeRate = _takerFeeRate;
        makerFeeRate = _makerFeeRate;
        treasury = _treasury;
        emit ParametersUpdated();
    }

    function pause() external {
        emit Paused();
        paused = true;
    }

    function unpause() external {
        emit Unpaused();
        paused = false;
    }

    function addSupportedAsset(bytes32 assetPair) external {
        emit SupportedAssetAdded(assetPair);
        supportedAssets[assetPair] = true;
    }

    function removeSupportedAsset(bytes32 assetPair) external {
        emit SupportedAssetRemoved(assetPair);
        supportedAssets[assetPair] = false;
    }
}