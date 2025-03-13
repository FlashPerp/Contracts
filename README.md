# Smart Contracts

**I. `PerpetualExchangeCore` (Execution Layer)**

*   **Purpose:** This is the heart of your perpetual exchange. It handles the core logic of perpetual contracts:
    *   Creating and managing positions (opening, closing, increasing, decreasing).
    *   Calculating and applying funding rates.
    *   Handling liquidations.
    *   Interacting with the `AssetRegistry` to manage collateral.
    *   Interacting with the `PriceOracle` to get price feeds.

*   **Variables:**

    *   `oracle`: `address` (The address of the `PriceOracle` contract.  This is set during deployment or via an admin function).
    *   `assetRegistry`: `address` (The address of the `AssetRegistry` contract. Set during deployment or via an admin function).
    *   `positions`: `mapping(uint256 => Position)` (Maps a unique position ID to a `Position` struct. This is the core data structure storing all open positions).
    *   `nextPositionId`: `uint256` (A counter to generate unique IDs for new positions.  Starts at 1 and increments with each new position).
    *   `fundingRateInterval`: `uint256` (The time interval (in seconds) between funding rate updates.  e.g., 8 hours = 28800 seconds).
    *   `globalFundingRates`: `mapping(bytes32 => int256)` (Maps an asset pair hash (e.g., `keccak256("ETH/USD")`) to the current global funding rate.  Expressed in a fixed-point format, e.g., parts per million or basis points).
    *   `lastFundingUpdateTime`: `mapping(bytes32 => uint256)` (Maps an asset pair hash to the timestamp of the last funding rate update).
    *   `maintenanceMarginRate`: `uint256` (The percentage of the notional value of a position that must be maintained as collateral. e.g., 2% = 200 basis points, if using basis points representation).
    *   `liquidationFeeRate`: `uint256` (The percentage of the liquidated position's value taken as a fee. e.g., 0.1% = 10 basis points).
    *   `takerFeeRate`: `uint256` (The fee rate charged to takers [users who submit the intent that is matched]).
    *   `makerFeeRate`: `uint256` (The fee rate charged to makers [solvers who fill the intent], this can be lower or even negative to incentivize filling).
    *   `treasury`: `address` (The address where fees are collected).
    *   `paused`: `bool` (A flag to pause the exchange in emergencies.  If `true`, most functions should revert).
    *   `supportedAssets`: `mapping(bytes32 => bool)` (A mapping indicating which asset pairs are supported for trading).

*   **Structs:**

    ```
    struct Position {
        uint256 positionId;      // Unique ID for the position
        address trader;          // Address of the user who owns the position
        bytes32 assetPair;     // Hash of the asset pair (e.g., keccak256("ETH/USD"))
        bool isLong;           // True if long, false if short
        uint256 collateral;    // Amount of collateral deposited (in the collateral token's smallest unit)
        uint256 size;          // Size of the position (in units of the underlying asset)
        uint256 entryPrice;    // Average entry price of the position
        uint256 lastFundingTimestamp; // Timestamp of the last funding payment
        uint256 accumulatedFunding;  // Accumulated funding owed (positive or negative)
        uint256 leverage; // The leverage.
    }
    ```

*   **Functions:**

    *   **`openPosition(address trader, bytes32 assetPair, bool isLong, uint256 collateralAmount, uint256 size, uint256 leverage, uint256 maxFundingRate, uint256 slippageTolerance)`:**
        *   **Purpose:** Opens a new perpetual position.  This is called by the *winning solver*, *not* directly by the user.
        *   **Inputs:**
            *   `trader`: The address of the user who submitted the intent.
            *   `assetPair`: The asset pair being traded (e.g., "ETH/USD").  Hashed using `keccak256`.
            *   `isLong`: `true` for a long position, `false` for a short position.
            *   `collateralAmount`: The amount of collateral being deposited (in the collateral token's smallest unit).
            *   `size`: The desired size of the position (in units of the underlying asset).
            *   `leverage`: The user's requested leverage.
            *   `maxFundingRate`:  The maximum acceptable funding rate (from the user's intent).
            *   `slippageTolerance`: The maximum allowable slippage.
        *   **Logic:**
            1.  **Input Validation:**
                *   Check if the exchange is paused (`paused == false`).
                *   Check if the asset pair is supported (`supportedAssets[assetPair] == true`).
                *   Check if `trader` is a valid address.
                *   Check if `collateralAmount`, `size`, and `leverage` are greater than zero.
                *   Check if `leverage` is within the allowed range.
                * Verify that there isn't a position already open.
            2.  **Price and Feasibility Checks:**
                *   Get the current price of the asset pair from the `PriceOracle` (`oracle.getPrice(assetPair)`).
                *   Calculate the notional value of the position (`size * price`).
                *   Calculate the required initial margin based on the notional value and leverage. This should roughly match (or exceed) `collateralAmount` considering possible slippage.
                *   Check if the current funding rate exceeds `maxFundingRate`.
                *   Enforce the `slippageTolerance`.
            3.  **Collateral Transfer:**
                *   Call `assetRegistry.transferToExchange(trader, collateralToken, collateralAmount)` to transfer the collateral from the user's account to the exchange.  The `collateralToken` needs to be determined based on the `assetPair` (e.g., USDC for ETH/USD).
            4.  **Create Position:**
                *   Generate a new `positionId` (`nextPositionId++`).
                *   Create a new `Position` struct and populate its fields.
                *   Store the new position in the `positions` mapping: `positions[positionId] = newPosition;`
            5.  **Update State:**
                *   Increment `nextPositionId`.
            6.  **Emit Event:** Emit a `PositionOpened` event.

    *   **`closePosition(uint256 positionId, uint256 sizeToClose)`:**
        *   **Purpose:** Allows a user to close part or all of their position.  Called by a solver (or potentially directly by a user, though this is less common in a pure intent-based system).
        *   **Inputs:**
            *   `positionId`: The ID of the position to close.
            *   `sizeToClose`: The amount of the position to close (in units of the underlying asset). If `sizeToClose` is equal to the position's total size, the position is fully closed.
        *   **Logic:**
            1.  **Input Validation:**
                *   Check if the exchange is paused.
                *   Check if `positionId` is valid (i.e., `positions[positionId].trader != address(0)`).
                *   Check if the caller is the solver or the owner.
                *   Check if `sizeToClose` is greater than zero and less than or equal to the position's size.
            2.  **Apply Funding:** Call `applyFunding()` *before* closing the position to ensure that any outstanding funding payments are settled.
            3.  **Calculate Realized PnL:**
                *   Get the current price from the `PriceOracle`.
                *   Calculate the realized profit or loss (PnL) based on the difference between the entry price and the current price, multiplied by `sizeToClose`.
            4.  **Update Position:**
                *   Reduce the position's `size` by `sizeToClose`.
                *   Reduce the position's `collateral` proportionally (taking into account the realized PnL).
                *   If `sizeToClose` is equal to the position's total size, remove the position from the `positions` mapping (or mark it as closed).
            5.  **Transfer Funds:**
                *   Call `assetRegistry.transferFromExchange` to return the remaining collateral (plus PnL or minus loss) to the user.
            6.  **Emit Event:** Emit a `PositionClosed` event.

    *   **`increasePosition(uint256 positionId, uint256 additionalCollateral, uint256 additionalSize)`:**
        *  **Purpose:** Adds to the position.
        * **Logic:**
            1. **Input Validation:** Checks that exist, is not paused, and the caller is the solver.
            2. **Apply Funding:** Apply the funding up to this point.
            3. **Collateral Transfer:**  Call `assetRegistry.transferToExchange` to transfer the additional collateral to the exchange.
            4.  **Update position**.
            5. **Event:** Emit event.

    *   **`decreasePosition(uint256 positionId, uint256 sizeToReduce)`:**
        * **Purpose:** Reduces a position, but without closing it.
        *  **Logic:** Similar to closing, but without fully removing the position.

    *   **`updateFundingRates()`:**
        *   **Purpose:** Calculates and updates the global funding rates for each supported asset pair. This function is *not* called on every trade.  It's called periodically (e.g., every `fundingRateInterval`).
        *   **Logic:**
            1.  **Check Time:** Check if enough time has passed since the last update (`block.timestamp >= lastFundingUpdateTime[assetPair] + fundingRateInterval`).
            2.  **Get Prices:**
                *   Get the *mark price* (typically from your `PriceOracle`).
                *   Get the *index price* (this might be the same as the mark price, or it might be an average of prices from multiple sources – for this MVP, keep it simple and use the oracle price).
            3.  **Calculate Funding Rate:** Calculate the funding rate based on the difference between the mark price and the index price. The specific formula can vary, but a common approach is:
                ```
                fundingRate = (markPrice - indexPrice) / indexPrice * (1 / periodsPerYear)
                ```
                Where `periodsPerYear` is the number of funding periods in a year (e.g., if `fundingRateInterval` is 8 hours, `periodsPerYear` would be 365 * 24 / 8 = 1095).
            4.  **Update State:**
                *   Store the new `fundingRate` in `globalFundingRates[assetPair]`.
                *   Update `lastFundingUpdateTime[assetPair]` to `block.timestamp`.
            5.  **Emit Event:** Emit a `FundingRatesUpdated` event.

    *   **`applyFunding()`:**
        *   **Purpose:** Applies funding payments to all open positions. This function can be called:
            *   **Periodically:** By a "keeper" bot (similar to Chainlink Keepers or Gelato Network).
            *   **Before Trade Execution:** As part of the `openPosition`, `closePosition`, `increasePosition` and `decreasePosition` functions to ensure funding is up-to-date.  This is the recommended approach for your MVP.
        *   **Logic:**
            1.  **Iterate:** Loop through all open positions in the `positions` mapping.  *Important Note:* Iterating through a mapping in Solidity can be expensive (gas costs). For a production system with many positions, you would need a more efficient data structure (e.g., a doubly-linked list) to avoid excessive gas consumption.  For your MVP, iterating through the mapping is acceptable, as you'll have a limited number of positions.
            2.  **Calculate Funding:** For each position:
                *   Calculate the time elapsed since the last funding payment (`timeElapsed = block.timestamp - position.lastFundingTimestamp`).
                *   Calculate the funding amount: `fundingAmount = position.size * globalFundingRates[position.assetPair] * timeElapsed`.
                *   Note: handle long/short funding correctly. If the funding rate is positive, longs pay shorts. If it's negative, shorts pay longs.
            3.  **Update Position:**
                *   Update the `position.collateral`:
                    *   If the user *owes* funding, subtract `fundingAmount` from `position.collateral`.
                    *   If the user *receives* funding, add `fundingAmount` to `position.collateral`.
                *   Update `position.lastFundingTimestamp` to `block.timestamp`.
                *   Update `position.accumulatedFunding`.
            4.  **Emit Event:** Emit a `FundingApplied` event for each position.

    *   **`liquidatePosition(uint256 positionId)`:**
        *   **Purpose:** Liquidates an under-margined position. This function is typically called by a "keeper" bot that monitors positions off-chain.
        *   **Logic:**
            1.  **Check Margin:**
                *   Get the current price from the `PriceOracle`.
                *   Calculate the notional value of the position (`position.size * price`).
                *   Calculate the maintenance margin requirement (`notionalValue * maintenanceMarginRate`).
                *   Check if `position.collateral < maintenanceMarginRequirement`.
            2.  **Liquidation:** If the position is under-margined:
                *   Close the position at the current market price (similar to `closePosition`, but without allowing partial closes).
                *   Calculate the liquidation fee (`notionalValue * liquidationFeeRate`).
                *   Transfer the remaining collateral (after losses and fees) to the user and the fee to the `treasury`.
                *   Remove the position from the `positions` mapping.
            3.  **Emit Event:** Emit a `PositionLiquidated` event.

    *   **Admin Functions:**
        *   `setOracle(address newOracle)`: Updates the `PriceOracle` address.
        *   `setAssetRegistry(address newRegistry)`: Updates the `AssetRegistry` address.
        *   `setParameters(...)`: Updates exchange parameters (e.g., `maintenanceMarginRate`, `liquidationFeeRate`, `fundingRateInterval`, `takerFeeRate`, `makerFeeRate`, `treasury`).
        *   `pause()`: Pauses the exchange.
        *   `unpause()`: Unpauses the exchange.
        *   `addSupportedAsset(bytes32 assetPair)`
        *   `removeSupportedAsset(bytes32 assetPair)`
        *   **Access Control:** These functions should be restricted to an owner address (or a multi-sig wallet) using OpenZeppelin's `Ownable` or a similar access control mechanism.

*   **Events:**

    *   `PositionOpened(uint256 positionId, address trader, bytes32 assetPair, bool isLong, uint256 collateral, uint256 size, uint256 entryPrice, uint256 leverage)`
    *   `PositionClosed(uint256 positionId, address trader, uint256 realizedPnL)`
    *   `PositionIncreased(uint256 positionId, address trader, uint256 addedCollateral, uint256 addedSize)`
    *   `PositionDecreased(uint256 positionId, address trader, uint256 reducedSize)`
    *   `FundingRatesUpdated(bytes32 assetPair, int256 fundingRate)`
    *   `FundingApplied(uint256 positionId, address trader, int256 fundingAmount)`
    *   `PositionLiquidated(uint256 positionId, address trader, uint256 remainingCollateral, uint256 liquidationFee)`
    *   `OracleUpdated(address oldOracle, address newOracle)`
    *   `AssetRegistryUpdated(address oldRegistry, address newRegistry)`
    *   `ParametersUpdated(...)`
    *   `Paused()`
    *   `Unpaused()`
    *   `SupportedAssetAdded(bytes32 assetPair)`
    *    `SupportedAssetRemoved(bytes32 assetPair)`

*   **Important Considerations:**

    *   **Gas Optimization:**  Be *extremely* mindful of gas costs.  Perpetual exchanges are gas-intensive.
        *   Minimize storage writes.
        *   Use efficient data structures.
        *   Avoid unnecessary calculations.
        *   Consider using assembly for critical sections (but only if you're *very* experienced with Solidity).
    *   **Security:**  This contract handles user funds and is a high-value target for attackers.
        *   Follow best practices for secure Solidity development.
        *   Use OpenZeppelin libraries where appropriate.
        *   Get multiple independent security audits.
    *   **Upgradability:** Consider using a proxy pattern (e.g., OpenZeppelin's Transparent Proxy or UUPS Proxy) to make the contract upgradable. This allows you to fix bugs or add features without migrating user funds.
    *   **Error Handling:** Use `require` statements to validate inputs and revert on errors.  Provide informative error messages.
    *   **Reentrancy Protection:**  Use OpenZeppelin's `ReentrancyGuard` or a similar mechanism to prevent reentrancy attacks.  This is particularly important if you interact with external contracts (like the `AssetRegistry`).
    *   **Fixed-Point Arithmetic:**  Solidity doesn't have native support for floating-point numbers.  You'll need to use fixed-point arithmetic to represent prices, funding rates, and other fractional values.  Use a library like ABDKMath64x64 or implement your own fixed-point logic carefully.

**II. `AssetRegistry` (Settlement Layer)**

*   **Purpose:** This contract manages user funds (collateral). It acts as a secure escrow, holding the collateral tokens and handling deposits, withdrawals, and transfers to/from the `PerpetualExchangeCore` contract.

*   **Variables:**

    *   `balances`: `mapping(address => mapping(address => uint256))` (Maps a user's address to a token address to their balance of that token.  `balances[user][token]` is the user's balance of the given token).
    *   `supportedTokens`: `mapping(address => bool)` (Indicates whether a token is supported for deposits and withdrawals).
    *   `exchangeAddress`: `address` (The address of the `PerpetualExchangeCore` contract. This is set during deployment or via an admin function).
    *   `paused`: `bool` (A flag to pause deposits and withdrawals in emergencies).

*   **Functions:**

    *   `deposit(address token, uint256 amount)`:
        *   **Purpose:** Allows a user to deposit a supported token.
        *   **Inputs:**
            *   `token`: The address of the token being deposited (e.g., USDC contract address).
            *   `amount`: The amount of the token to deposit (in the token's smallest unit).
        *   **Logic:**
            1.  **Input Validation:**
                *   Check if the contract is paused.
                *   Check if the token is supported (`supportedTokens[token] == true`).
                *   Check if `amount` is greater than zero.
            2.  **ERC-20 Transfer:**
                *   The user must have *already approved* the `AssetRegistry` contract to spend their tokens.  This is done via a separate ERC-20 `approve` transaction (typically handled by the UI).
                *   Use the ERC-20 `transferFrom` function to transfer the tokens *from the user* to the `AssetRegistry` contract:
                    ```solidity
                    IERC20(token).transferFrom(msg.sender, address(this), amount);
                    ```
            3.  **Update Balance:**
                *   Increment the user's balance in the `balances` mapping: `balances[msg.sender][token] += amount;`
            4.  **Emit Event:** Emit a `Deposit` event.

    *   `withdraw(address token, uint256 amount)`:
        *   **Purpose:** Allows a user to withdraw their funds.
        *   **Inputs:**
            *   `token`: The address of the token to withdraw.
            *   `amount`: The amount of the token to withdraw.
        *   **Logic:**
            1.  **Input Validation:**
                *   Check if the contract is paused.
                *   Check if the token is supported.
                *   Check if `amount` is greater than zero.
                *   Check if the user has sufficient balance: `balances[msg.sender][token] >= amount`.
            2.  **ERC-20 Transfer:**
                *   Use the ERC-20 `transfer` function to transfer the tokens *from the `AssetRegistry` contract* to the user:
                    ```solidity
                    IERC20(token).transfer(msg.sender, amount);
                    ```
            3.  **Update Balance:**
                *   Decrement the user's balance: `balances[msg.sender][token] -= amount;`
            4.  **Emit Event:** Emit a `Withdrawal` event.

    *   `transferToExchange(address user, address token, uint256 amount)`:
        *   **Purpose:** Transfers collateral from a user's account to the `PerpetualExchangeCore` contract when a position is opened.  This function is called *only* by the `PerpetualExchangeCore` contract.
        *   **Inputs:**
            *   `user`: The address of the user whose collateral is being transferred.
            *   `token`: The address of the collateral token.
            *   `amount`: The amount of collateral to transfer.
        *   **Logic:**
            1.  **Access Control:** *Crucially*, check that the caller is the `PerpetualExchangeCore` contract: `require(msg.sender == exchangeAddress, "Unauthorized");`
            2.  **Input Validation:**
                *   Check if the token is supported.
                *   Check if `amount` is greater than zero.
                *   Check if the user has sufficient balance: `balances[user][token] >= amount`.
            3.  **Update Balance:**
                *   Decrement the user's balance: `balances[user][token] -= amount;`
            4.  **Emit Event:** Emit a `TransferToExchange` event.

    *   `transferFromExchange(address user, address token, uint256 amount)`:
        *   **Purpose:** Transfers collateral (and PnL) back to a user's account when a position is closed or liquidated.  This function is called *only* by the `PerpetualExchangeCore` contract.
        *   **Inputs:**
            *   `user`: The address of the user receiving the funds.
            *   `token`: The address of the collateral token.
            *   `amount`: The amount of collateral to transfer.
        *   **Logic:**
            1.  **Access Control:** *Crucially*, check that the caller is the `PerpetualExchangeCore` contract: `require(msg.sender == exchangeAddress, "Unauthorized");`
            2.  **Input Validation:**
                *   Check if the token is supported.
                *   Check if `amount` is greater than zero.
            3.  **Update Balance:**
                *   Increment the user's balance:  `balances[user][token] += amount;`
            4.  **Emit Event:** Emit a `TransferFromExchange` event.
    *    **Admin Functions:**
            * `addSupportedToken(address token)`: Adds a new supported token.
            * `removeSupportedToken(address token)`: Removes a supported token (should only be done if no users have balances of that token, check this).
            * `setExchangeAddress(address newExchangeAddress)`: Set the address.
            * `pause()`: Pause the contract.
            *`unpause()`: Unpause the contract.
            *   **Access Control:** These functions should have restricted access (e.g., using OpenZeppelin's `Ownable`).

*   **Events:**

    *   `Deposit(address user, address token, uint256 amount)`
    *   `Withdrawal(address user, address token, uint256 amount)`
    *   `TransferToExchange(address user, address token, uint256 amount)`
    *   `TransferFromExchange(address user, address token, uint256 amount)`
    *   `SupportedTokenAdded(address token)`
    *   `SupportedTokenRemoved(address token)`
    * `ExchangeAddressUpdated(address newExchangeAddress)`
    *   `Paused()`
    *   `Unpaused()`

*   **Important Considerations:**

    *   **Security:** This contract is *extremely* security-critical, as it holds all user funds.
        *   Follow best practices for secure Solidity development *meticulously*.
        *   Use OpenZeppelin's ERC-20 implementation (or a well-audited alternative) for token interactions.
        *   Get *multiple, independent* security audits.
        *   Consider using a formal verification tool.
    *   **Reentrancy Protection:** Use OpenZeppelin's `ReentrancyGuard` to prevent reentrancy attacks.
    *   **Upgradability:**  Use a proxy pattern for upgradability.
    *   **Gas Optimization:** While less critical than `PerpetualExchangeCore`, optimize for gas where possible.
    * **ERC-20 Compliance:** Ensure strict adherence to the ERC-20 standard for all token interactions.

**III. `PriceOracle` (Execution Layer - External, but Essential)**

*   **Purpose:** Provides reliable price feeds for the underlying assets traded on the perpetual exchange.  This is *essential* for:
    *   Calculating the notional value of positions.
    *   Determining liquidation prices.
    *   Calculating funding rates.

*   **Options (Discussed Previously):**

    *   **Chainlink Price Feeds (Recommended for MVP):** The easiest and most secure option for your MVP. Chainlink provides decentralized, tamper-proof price feeds for a wide range of assets.
    *   **Custom Oracle (More Complex):** You could build your own oracle, but this is significantly more complex and introduces additional security risks.  Only consider this if you have a very specific need that Chainlink can't meet.
    *   **Oracle Aggregation (Advanced):** You could aggregate data from multiple oracles (e.g., Chainlink, MakerDAO's oracle, Uniswap TWAP) to increase robustness.

*   **Implementation (Using Chainlink):**

    *   **Interface:** Your `PerpetualExchangeCore` contract interacts with the Chainlink Price Feed through a standard interface (typically the `AggregatorV3Interface`).
    *   **`getPrice(bytes32 assetPair)`:** This is the main function you'll use. It takes the asset pair (e.g., "ETH/USD") as input and returns the latest price.  The Chainlink Price Feed contract handles the underlying data aggregation and security.
    *   **Data Validation:** Even with Chainlink, it's good practice to perform some basic sanity checks on the returned price (e.g., check for stale data, ensure the price is within reasonable bounds).

* **Example (Conceptual - using Chainlink):**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PriceOracle {
    mapping(bytes32 => AggregatorV3Interface) public priceFeeds;

    // Admin function to set the address of a Chainlink Price Feed
    function setPriceFeed(bytes32 assetPair, address feed) external onlyOwner { // Assume Ownable
        priceFeeds[assetPair] = AggregatorV3Interface(feed);
    }

    function getPrice(bytes32 assetPair) external view returns (int256) {
        require(address(priceFeeds[assetPair]) != address(0), "Price feed not set");
        (, int256 price, , uint256 updatedAt, ) = priceFeeds[assetPair].latestRoundData();

        // Basic sanity checks (optional but recommended)
        require(price > 0, "Invalid price");
        require(block.timestamp - updatedAt <= 3600, "Price data is stale"); // 1 hour staleness check

        return price;
    }

	// ... (Other functions, if needed) ...
    // Events
    event PriceFeedSet(bytes32 assetPair, address feed);

}

```

* **Important Considerations:**
    *   **Decentralization:** Chainlink provides a decentralized oracle network.  If you build a custom oracle, ensure it's also decentralized to avoid a single point of failure.
    *   **Data Quality:** Monitor the oracle's data quality and performance.  Have a plan for handling stale data or oracle malfunctions.
    *   **Cost:** Using Chainlink Price Feeds involves a small cost (paid in LINK).

**IV. `SolverRegistry` (Management Layer)**

*   **Purpose:** Manages the registration, staking, and (optionally) reputation of solvers.  This contract helps ensure the security and integrity of the solver network.

*   **Variables:**

    *   `solvers`: `mapping(address => Solver)` (Maps a solver's address to a `Solver` struct. This stores information about each registered solver).
    *   `minimumStake`: `uint256` (The minimum amount of tokens a solver must stake to register. This is set during deployment or via an admin function).
    *  `stakingToken` : `address` (the address to the token used for staking).
    *   `totalStaked`: `uint256` (The total amount of tokens staked by all solvers.  This can be useful for governance or other mechanisms).

*   **Structs:**

    ```solidity
    struct Solver {
        address solverAddress;  // The solver's Ethereum address
        uint256 stake;          // The amount of tokens the solver has staked
        bool isActive;       // Whether the solver is currently active (can participate in auctions)
        int256 reputation;   // (Optional) The solver's reputation score
    }
    ```

*   **Functions:**

    *   `registerSolver(uint256 stakeAmount)`:
        *   **Purpose:** Allows a new solver to register with the system.
        *   **Inputs:**
            *   `stakeAmount`: The amount of tokens the solver wants to stake.
        *   **Logic:**
            1.  **Input Validation:**
                *   Check if the solver is already registered (`solvers[msg.sender].solverAddress == address(0)`).
                *   Check if `stakeAmount` is greater than or equal to `minimumStake`.
            2.  **ERC-20 Transfer:**
                *   The solver must have *already approved* the `SolverRegistry` contract to spend their staking token.
                *   Use the ERC-20 `transferFrom` function to transfer the `stakeAmount` from the solver to the `SolverRegistry` contract.
            3.  **Create Solver Record:**
                *   Create a new `Solver` struct and populate its fields:
                    ```solidity
                    solvers[msg.sender] = Solver({
                        solverAddress: msg.sender,
                        stake: stakeAmount,
                        isActive: true,
                        reputation: 0 // Or an initial reputation value
                    });
                    ```
            4.  **Update State:**
                *  Increment `totalStaked`.
            5.  **Emit Event:** Emit a `SolverRegistered` event.

    *   `unregisterSolver()`:
        *   **Purpose:** Allows a solver to unregister and withdraw their stake.
        *   **Logic:**
            1.  **Input Validation:**
                *   Check if the solver is registered (`solvers[msg.sender].solverAddress != address(0)`).
                * Check if the solver is active (`solvers[msg.sender].isActive == true`)
            2.  **Stake Transfer:**
                *   Use the ERC-20 `transfer` function to transfer the solver's stake back to them.
            3.  **Update Solver Record:**
                *   Mark the solver as inactive (`solvers[msg.sender].isActive = false`).
                *   Set the solver stake to zero (`solvers[msg.sender].stake = 0`).  (Or you could completely remove the solver from the `solvers` mapping).
            4.  **Update State:**
              * Decrement `totalStaked`
            5.  **Emit Event:** Emit a `SolverUnregistered` event.
        *   **Considerations:**
            *   **Unbonding Period (Optional):** You might want to implement an "unbonding period" – a delay between when a solver unregisters and when they can withdraw their stake. This prevents solvers from quickly withdrawing their stake after submitting a malicious bid.

    *   `slashSolver(address solverAddress, uint256 amount)`:
        *   **Purpose:** Allows the exchange (or a governance mechanism) to slash a solver's stake for malicious behavior (e.g., submitting invalid bids, failing to execute winning bids).
        *   **Inputs:**
            *   `solverAddress`: The address of the solver to slash.
            *   `amount`: The amount of tokens to slash.
        *   **Logic:**
            1.  **Access Control:** *Crucially*, this function should have *very* restricted access.  It should only be callable by:
                *   The contract owner (for emergencies).
                *   A governance mechanism (e.g., a DAO).
                *   Another contract (e.g., an "Arbitrator" contract) that handles disputes.
            2.  **Input Validation:**
                *   Check if the solver is registered.
                *   Check if `amount` is greater than zero and less than or equal to the solver's stake.
            3.  **Update Solver Record:**
                *   Reduce the solver's stake: `solvers[solverAddress].stake -= amount;`
            4. **Update State:**
                * Decrease `totalStaked`.
            5.  **Transfer Slashed Funds:** Transfer the slashed tokens to a designated address (e.g., a treasury, a burn address, or a reward pool for other solvers).
            6.  **Emit Event:** Emit a `SolverSlashed` event.
            7.  **Deactivation (Optional):**  If the solver's stake falls below `minimumStake`, mark them as inactive.

    * **`increaseStake(uint256 additionalStake)` (Optional):** Allows solvers to increase their existing stake.
    * **`decreaseStake(uint256 amountToWithdraw)` (Optional):** Allows to decrease stake, potentially with a delay.
    *   `updateReputation(address solverAddress, int256 delta)`: (Optional)
        *   **Purpose:** Updates a solver's reputation score. This function would be called by other components of the system (e.g., the Auctioneer, a dispute resolution mechanism) based on the
