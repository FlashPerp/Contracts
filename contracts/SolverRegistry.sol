// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SolverRegistry is Ownable {

    struct Solver {
        address solverAddress;
        uint256 stake;
        bool isActive;
        int256 reputation;
    }

    mapping(address => Solver) public solvers;
    uint256 public minimumStake;
    address public stakingToken;
    uint256 public totalStaked;

    event SolverRegistered(address solverAddress, uint256 stakeAmount);
    event SolverUnregistered(address solverAddress);
    event SolverSlashed(address solverAddress, uint256 amount);

    constructor(uint256 _minimumStake, address _stakingToken) Ownable(msg.sende) {
        super();
        minimumStake = _minimumStake;
        stakingToken = _stakingToken;
    }

    function registerSolver(uint256 stakeAmount) external {
        // ... implementation ...
        emit SolverRegistered(msg.sender, stakeAmount);
    }

    function unregisterSolver() external {
        // ... implementation ...
        emit SolverUnregistered(msg.sender);
    }

    function slashSolver(address solverAddress, uint256 amount) external onlyOwner {
        // ... implementation ...
        emit SolverSlashed(solverAddress, amount);
    }
}