# Intent-Based Perpetual Exchange - Architecture Plan

## Overview

This document outlines the architecture plan for an intent-based perpetual exchange. The exchange consists of four main components: `PerpetualExchangeCore`, `AssetRegistry`, `PriceOracle`, and `SolverRegistry`. This plan focuses on understanding how user intents are handled, matched with solvers, and executed on the exchange.

## Plan

1.  **Intent-Based Architecture:** Focus on understanding how user intents are handled, matched with solvers, and executed on the exchange.
2.  **File Exploration:** Use `list_files` to explore the directory structure and identify files related to intent handling, solver interactions, and matching mechanisms.
3.  **Contract Analysis:** Use `list_code_definition_names` to extract definitions from contracts related to intents and solvers.
4.  **Workflow Diagram (Intent Lifecycle):** Create a Mermaid diagram illustrating the lifecycle of a user intent, from submission to execution.
5.  **Security Considerations (Solver Risks):** Analyze potential security risks associated with solvers, such as malicious bidding or front-running, and identify mitigation strategies.
6.  **Gas Optimization (Intent Execution):** Investigate gas optimization techniques specific to intent execution, considering the costs of matching, validation, and settlement.

## Intent Lifecycle Diagram

```mermaid
sequenceDiagram
    participant User
    participant IntentSubmission
    participant SolverRegistry
    participant Auctioneer
    participant PerpetualExchangeCore
    participant AssetRegistry

    User->>IntentSubmission: Submit Intent
    IntentSubmission->>SolverRegistry: Notify Solvers
    SolverRegistry->>Auctioneer: Solvers Bid
    Auctioneer->>PerpetualExchangeCore: Winning Bid
    PerpetualExchangeCore->>AssetRegistry: Transfer Collateral
    PerpetualExchangeCore->>PerpetualExchangeCore: Execute Trade
    PerpetualExchangeCore->>AssetRegistry: Transfer PnL
    AssetRegistry->>User: Settle Funds