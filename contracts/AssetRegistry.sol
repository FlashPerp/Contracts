// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IAssetRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AssetRegistry
 * @dev Implementation of the asset registry for the perpetual exchange
 * This contract manages user assets and collateral
 */
contract AssetRegistry is IAssetRegistry, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // Exchange contract address
    address public exchangeAddress;
    
    // Mapping from user address to token address to balance
    mapping(address => mapping(address => uint256)) private balances;
    
    // Mapping from token address to whether it's supported
    mapping(address => bool) private supportedTokens;
    
    // Mapping from asset pair to collateral token
    mapping(bytes32 => address) private collateralTokens;
    
    // Events
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdrawal(address indexed user, address indexed token, uint256 amount);
    event TransferToExchange(address indexed user, address indexed token, uint256 amount);
    event TransferFromExchange(address indexed user, address indexed token, uint256 amount);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event CollateralTokenSet(bytes32 indexed assetPair, address indexed token);
    event ExchangeAddressUpdated(address indexed newExchangeAddress);
    
    /**
     * @dev Constructor
     */
    constructor() Ownable(msg.sender) {
        // Initialize contract
    }
    
    /**
     * @dev Modifier to restrict access to only the exchange contract
     */
    modifier onlyExchange() {
        require(msg.sender == exchangeAddress, "Caller is not the exchange");
        _;
    }
    
    /**
     * @dev Deposits tokens into the registry
     * @param token The address of the token to deposit
     * @param amount The amount to deposit
     */
    function deposit(address token, uint256 amount) external whenNotPaused nonReentrant {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than zero");
        
        // Transfer tokens from user to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Update user balance
        balances[msg.sender][token] += amount;
        
        emit Deposit(msg.sender, token, amount);
    }
    
    /**
     * @dev Withdraws tokens from the registry
     * @param token The address of the token to withdraw
     * @param amount The amount to withdraw
     */
    function withdraw(address token, uint256 amount) external whenNotPaused nonReentrant {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than zero");
        require(balances[msg.sender][token] >= amount, "Insufficient balance");
        
        // Update user balance
        balances[msg.sender][token] -= amount;
        
        // Transfer tokens from this contract to user
        IERC20(token).safeTransfer(msg.sender, amount);
        
        emit Withdrawal(msg.sender, token, amount);
    }
    
    /**
     * @dev Transfers tokens from a user to the exchange contract
     * @param user The address of the user
     * @param token The address of the token being transferred
     * @param amount The amount of tokens to transfer
     * @return success True if the transfer was successful
     */
    function transferToExchange(address user, address token, uint256 amount) 
        external 
        override 
        whenNotPaused 
        onlyExchange 
        returns (bool success) 
    {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than zero");
        require(balances[user][token] >= amount, "Insufficient balance");
        
        // Update user balance
        balances[user][token] -= amount;
        
        emit TransferToExchange(user, token, amount);
        
        return true;
    }
    
    /**
     * @dev Transfers tokens from the exchange contract to a user
     * @param user The address of the user
     * @param token The address of the token being transferred
     * @param amount The amount of tokens to transfer
     * @return success True if the transfer was successful
     */
    function transferFromExchange(address user, address token, uint256 amount) 
        external 
        override 
        whenNotPaused 
        onlyExchange 
        returns (bool success) 
    {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than zero");
        
        // Update user balance
        balances[user][token] += amount;
        
        emit TransferFromExchange(user, token, amount);
        
        return true;
    }
    
    /**
     * @dev Returns the balance of a specific token for a user
     * @param user The address of the user
     * @param token The address of the token
     * @return balance The user's balance of the specified token
     */
    function getBalance(address user, address token) 
        external 
        view 
        override 
        returns (uint256 balance) 
    {
        return balances[user][token];
    }
    
    /**
     * @dev Checks if a token is supported by the registry
     * @param token The address of the token
     * @return True if the token is supported, false otherwise
     */
    function isTokenSupported(address token) 
        external 
        view 
        override 
        returns (bool) 
    {
        return supportedTokens[token];
    }
    
    /**
     * @dev Gets the collateral token address for a specific asset pair
     * @param assetPair The hashed asset pair identifier
     * @return token The address of the collateral token
     */
    function getCollateralToken(bytes32 assetPair) 
        external 
        view 
        override 
        returns (address token) 
    {
        address collateralToken = collateralTokens[assetPair];
        require(collateralToken != address(0), "No collateral token set for asset pair");
        return collateralToken;
    }
    
    /**
     * @dev Adds a new supported token
     * @param token The address of the token to add
     */
    function addSupportedToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(!supportedTokens[token], "Token already supported");
        
        supportedTokens[token] = true;
        
        emit TokenAdded(token);
    }
    
    /**
     * @dev Removes a supported token
     * @param token The address of the token to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        require(supportedTokens[token], "Token not supported");
        
        supportedTokens[token] = false;
        
        emit TokenRemoved(token);
    }
    
    /**
     * @dev Sets the collateral token for an asset pair
     * @param assetPair The hashed asset pair identifier
     * @param token The address of the collateral token
     */
    function setCollateralToken(bytes32 assetPair, address token) external onlyOwner {
        require(assetPair != bytes32(0), "Invalid asset pair");
        require(token != address(0), "Invalid token address");
        require(supportedTokens[token], "Token not supported");
        
        collateralTokens[assetPair] = token;
        
        emit CollateralTokenSet(assetPair, token);
    }
    
    /**
     * @dev Sets the exchange address
     * @param newExchangeAddress The new exchange address
     */
    function setExchangeAddress(address newExchangeAddress) external onlyOwner {
        require(newExchangeAddress != address(0), "Invalid exchange address");
        
        exchangeAddress = newExchangeAddress;
        
        emit ExchangeAddressUpdated(newExchangeAddress);
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
