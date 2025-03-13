const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Perpetual Exchange System", function () {
  let priceOracle;
  let assetRegistry;
  let perpExchange;
  let owner;
  let trader1;
  let trader2;
  let treasury;
  let mockToken;
  let ETH_USD;

  beforeEach(async function () {
    // Get signers
    [owner, trader1, trader2, treasury] = await ethers.getSigners();

    // Deploy a mock ERC20 token for testing
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("USD Coin", "USDC", 6);
    await mockToken.waitForDeployment();

    // Deploy the contracts
    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    priceOracle = await PriceOracle.deploy();
    await priceOracle.waitForDeployment();

    const AssetRegistry = await ethers.getContractFactory("AssetRegistry");
    assetRegistry = await AssetRegistry.deploy();
    await assetRegistry.waitForDeployment();

    const PerpetualExchangeCore = await ethers.getContractFactory("PerpetualExchangeCore");
    perpExchange = await PerpetualExchangeCore.deploy(
      await priceOracle.getAddress(),
      await assetRegistry.getAddress(),
      await treasury.getAddress()
    );
    await perpExchange.waitForDeployment();

    // Set the exchange address in the AssetRegistry
    await assetRegistry.setExchangeAddress(await perpExchange.getAddress());

    // Add the mock token to the AssetRegistry
    await assetRegistry.addSupportedToken(await mockToken.getAddress());

    // Create ETH/USD asset pair
    ETH_USD = ethers.keccak256(ethers.toUtf8Bytes("ETH/USD"));
    
    // Set initial price to $3,000 with 8 decimals precision
    const initialMarkPrice = ethers.parseUnits("3000", 8);
    const initialIndexPrice = ethers.parseUnits("3000", 8);
    
    // Add the asset pair to the PriceOracle
    await priceOracle.addAssetPair(ETH_USD, initialMarkPrice, initialIndexPrice);

    // Add the asset pair to the PerpetualExchangeCore
    await perpExchange.addAssetPair(ETH_USD);

    // Set the collateral token for ETH/USD
    await assetRegistry.setCollateralToken(ETH_USD, await mockToken.getAddress());

    // Mint some tokens to the traders
    await mockToken.mint(trader1.address, ethers.parseUnits("10000", 6)); // 10,000 USDC
    await mockToken.mint(trader2.address, ethers.parseUnits("10000", 6)); // 10,000 USDC
  });

  describe("Basic Setup", function () {
    it("Should set the correct initial values", async function () {
      expect(await perpExchange.oracle()).to.equal(await priceOracle.getAddress());
      expect(await perpExchange.assetRegistry()).to.equal(await assetRegistry.getAddress());
      expect(await perpExchange.treasury()).to.equal(await treasury.getAddress());
      expect(await perpExchange.supportedAssets(ETH_USD)).to.equal(true);
    });

    it("Should return the correct price for ETH/USD", async function () {
      const price = await priceOracle.getPrice(ETH_USD);
      expect(price).to.equal(ethers.parseUnits("3000", 8));
    });

    it("Should confirm the collateral token for ETH/USD", async function () {
      const collateralToken = await assetRegistry.getCollateralToken(ETH_USD);
      expect(collateralToken).to.equal(await mockToken.getAddress());
    });
  });

  describe("Asset Registry Operations", function () {
    it("Should allow a user to deposit tokens", async function () {
      // Approve the AssetRegistry to spend tokens
      await mockToken.connect(trader1).approve(
        await assetRegistry.getAddress(),
        ethers.parseUnits("1000", 6)
      );

      // Deposit tokens
      await assetRegistry.connect(trader1).deposit(
        await mockToken.getAddress(),
        ethers.parseUnits("1000", 6)
      );

      // Check balance
      const balance = await assetRegistry.getBalance(trader1.address, await mockToken.getAddress());
      expect(balance).to.equal(ethers.parseUnits("1000", 6));
    });

    it("Should allow a user to withdraw tokens", async function () {
      // Approve and deposit tokens
      await mockToken.connect(trader1).approve(
        await assetRegistry.getAddress(),
        ethers.parseUnits("1000", 6)
      );
      await assetRegistry.connect(trader1).deposit(
        await mockToken.getAddress(),
        ethers.parseUnits("1000", 6)
      );

      // Withdraw tokens
      await assetRegistry.connect(trader1).withdraw(
        await mockToken.getAddress(),
        ethers.parseUnits("500", 6)
      );

      // Check balance
      const balance = await assetRegistry.getBalance(trader1.address, await mockToken.getAddress());
      expect(balance).to.equal(ethers.parseUnits("500", 6));
    });
  });

  describe("Position Operations", function () {
    beforeEach(async function () {
      // Approve and deposit tokens for trader1
      await mockToken.connect(trader1).approve(
        await assetRegistry.getAddress(),
        ethers.parseUnits("5000", 6)
      );
      await assetRegistry.connect(trader1).deposit(
        await mockToken.getAddress(),
        ethers.parseUnits("5000", 6)
      );
    });

    it("Should allow opening a long position", async function () {
      // Open a long position
      const collateralAmount = ethers.parseUnits("1000", 6); // 1,000 USDC
      const size = ethers.parseUnits("1", 8); // 1 ETH
      const leverage = 3; // 3x leverage
      const maxFundingRate = 1000; // 10% in basis points
      const slippageTolerance = 100; // 1% in basis points

      await expect(
        perpExchange.connect(trader1).openPosition(
          trader1.address,
          ETH_USD,
          true, // long
          collateralAmount,
          size,
          leverage,
          maxFundingRate,
          slippageTolerance
        )
      ).to.emit(perpExchange, "PositionOpened");

      // Check position details
      const positionId = 1; // First position
      const position = await perpExchange.getPosition(positionId);
      
      expect(position.trader).to.equal(trader1.address);
      expect(position.assetPair).to.equal(ETH_USD);
      expect(position.isLong).to.equal(true);
      expect(position.collateral).to.equal(collateralAmount);
      expect(position.size).to.equal(size);
      expect(position.leverage).to.equal(leverage);
    });

    it("Should allow closing a position", async function () {
      // Open a position first
      const collateralAmount = ethers.parseUnits("1000", 6); // 1,000 USDC
      const size = ethers.parseUnits("1", 8); // 1 ETH
      const leverage = 3; // 3x leverage
      const maxFundingRate = 1000; // 10% in basis points
      const slippageTolerance = 100; // 1% in basis points

      await perpExchange.connect(trader1).openPosition(
        trader1.address,
        ETH_USD,
        true, // long
        collateralAmount,
        size,
        leverage,
        maxFundingRate,
        slippageTolerance
      );

      const positionId = 1; // First position

      // Close the position
      await expect(
        perpExchange.connect(trader1).closePosition(
          positionId,
          size // Close the entire position
        )
      ).to.emit(perpExchange, "PositionClosed");

      // Position should no longer exist
      const position = await perpExchange.getPosition(positionId);
      expect(position.trader).to.equal(ethers.ZeroAddress);
    });
  });

  describe("Price Oracle Operations", function () {
    it("Should allow updating the price", async function () {
      // Update the price
      const newMarkPrice = ethers.parseUnits("3100", 8); // $3,100
      const newIndexPrice = ethers.parseUnits("3100", 8); // $3,100
      
      await priceOracle.updatePrice(ETH_USD, newMarkPrice, newIndexPrice);
      
      // Check the new price
      const price = await priceOracle.getPrice(ETH_USD);
      expect(price).to.equal(newMarkPrice);
    });
  });

  // Additional tests for funding rates, liquidations, etc. would be added here
});

