// Scripts for deploying the FlashPerp contracts
const { ethers } = require("hardhat");

async function main() {
  console.log("Starting deployment of FlashPerp contracts...");

  // Get the contract factories
  const PriceOracle = await ethers.getContractFactory("PriceOracle");
  const AssetRegistry = await ethers.getContractFactory("AssetRegistry");
  const PerpetualExchangeCore = await ethers.getContractFactory("PerpetualExchangeCore");

  // Deploy the contracts
  console.log("Deploying PriceOracle...");
  const priceOracle = await PriceOracle.deploy();
  await priceOracle.waitForDeployment();
  console.log("PriceOracle deployed to:", await priceOracle.getAddress());

  console.log("Deploying AssetRegistry...");
  const assetRegistry = await AssetRegistry.deploy();
  await assetRegistry.waitForDeployment();
  console.log("AssetRegistry deployed to:", await assetRegistry.getAddress());

  // Deploy treasury (in a real scenario, this would be a multisig wallet)
  const [deployer] = await ethers.getSigners();
  const treasuryAddress = deployer.address;
  console.log("Using treasury address:", treasuryAddress);

  console.log("Deploying PerpetualExchangeCore...");
  const perpExchange = await PerpetualExchangeCore.deploy(
    await priceOracle.getAddress(),
    await assetRegistry.getAddress(),
    treasuryAddress
  );
  await perpExchange.waitForDeployment();
  console.log("PerpetualExchangeCore deployed to:", await perpExchange.getAddress());

  // Set the exchange address in the AssetRegistry
  console.log("Setting exchange address in AssetRegistry...");
  const setExchangeTx = await assetRegistry.setExchangeAddress(await perpExchange.getAddress());
  await setExchangeTx.wait();
  console.log("Exchange address set in AssetRegistry");

  // Add a sample asset pair to the PriceOracle
  const ETH_USD = ethers.keccak256(ethers.toUtf8Bytes("ETH/USD"));
  console.log("Adding ETH/USD asset pair to PriceOracle...");
  
  // Set initial price to $3,000 with 8 decimals precision (300000000000)
  const initialMarkPrice = ethers.parseUnits("3000", 8);
  const initialIndexPrice = ethers.parseUnits("3000", 8);
  
  const addAssetPairTx = await priceOracle.addAssetPair(ETH_USD, initialMarkPrice, initialIndexPrice);
  await addAssetPairTx.wait();
  console.log("ETH/USD asset pair added to PriceOracle");

  // Add the asset pair to the PerpetualExchangeCore
  console.log("Adding ETH/USD asset pair to PerpetualExchangeCore...");
  const addAssetPairToExchangeTx = await perpExchange.addAssetPair(ETH_USD);
  await addAssetPairToExchangeTx.wait();
  console.log("ETH/USD asset pair added to PerpetualExchangeCore");

  console.log("Deployment completed successfully!");
}

// Execute the deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
