// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AssetRegistry is ReentrancyGuard {

    mapping(address => mapping(address => uint256)) public balances;
    mapping(address => bool) public supportedTokens;
    address public exchangeAddress;
    bool public paused;

    event Deposit(address user, address token, uint256 amount);
    event Withdrawal(address user, address token, uint256 amount);
    event TransferToExchange(address user, address token, uint256 amount);
    event TransferFromExchange(address user, address token, uint256 amount);
    event SupportedTokenAdded(address token);
    event SupportedTokenRemoved(address token);
    event ExchangeAddressUpdated(address newExchangeAddress);
    event Paused();
    event Unpaused();

    constructor(address _exchangeAddress) {
        exchangeAddress = _exchangeAddress;
    }

    function deposit(address token, uint256 amount) external nonReentrant {
        // ... implementation ...
        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external nonReentrant {
        // ... implementation ...
        emit Withdrawal(msg.sender, token, amount);
    }

    function transferToExchange(address user, address token, uint256 amount) external nonReentrant {
        require(msg.sender == exchangeAddress, "Unauthorized");
        // ... implementation ...
        emit TransferToExchange(user, token, amount);
    }

    function transferFromExchange(address user, address token, uint256 amount) external nonReentrant {
        require(msg.sender == exchangeAddress, "Unauthorized");
        // ... implementation ...
        emit TransferFromExchange(user, token, amount);
    }

    function addSupportedToken(address token) external {
        emit SupportedTokenAdded(token);
        supportedTokens[token] = true;
    }

    function removeSupportedToken(address token) external {
        emit SupportedTokenRemoved(token);
        supportedTokens[token] = false;
    }

    function setExchangeAddress(address newExchangeAddress) external {
        emit ExchangeAddressUpdated(newExchangeAddress);
        exchangeAddress = newExchangeAddress;
    }

    function pause() external {
        emit Paused();
        paused = true;
    }

    function unpause() external {
        emit Unpaused();
        paused = false;
    }
}