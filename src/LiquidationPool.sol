// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISmartVaultManager} from "./interfaces/ISmartVaultManager.sol";
import {IEUROs} from "./interfaces/IEUROs.sol";
import {IChainlinkAggregatorV3} from "../src/interfaces/IChainlinkAggregatorV3.sol";
import {ILiquidationPool} from "./interfaces/ILiquidationPool.sol";
import {ILiquidationPoolManager} from "./interfaces/ILiquidationPoolManager.sol";
import {ITokenManager} from "./interfaces/ITokenManager.sol";
import {VaultifyErrors} from "./libraries/VaultifyErrors.sol";

contract LiquidationPool is ILiquidationPool {
    using SafeERC20 for IERC20;

    address private immutable TST;
    address private immutable EUROs;
    address private immutable eurUsd;

    // struct
    struct Position {
        address holder;
        uint256 TstTokens;
        uint256 EurosTokens;
    }

    struct Rewards {
        bytes32 symbol;
        uint256 amount;
        uint8 dec;
    }

    struct PendingStake {
        address holder;
        uint256 createdAt;
        uint256 TstTokens;
        uint256 EurosTokens;
    }

    address[] public holders;
    mapping(address => Position) private positions;
    mapping(bytes => uint256) private rewards;

    PendingStake[] private pendingStakes;

    address payable public manager;
    address public tokenManager;

    /// @notice Initializes the Liquidation Pool.
    /// @param _TST Address of the TST token contract.
    /// @param _EUROs Address of the EUROs token contract.
    /// @param _eurUsd Address of the EUR/USD price feed contract.
    /// @param _tokenManager Address of the Token Manager contract.
    constructor(
        address _TST,
        address _EUROs,
        address _eurUsd,
        address _tokenManager
    ) {
        TST = _TST;
        EUROs = _EUROs;
        eurUsd = _eurUsd;
        tokenManager = _tokenManager;
        manager = payable(msg.sender);
    }

    // TODO Change tokens other tokens names
    function increasePosition(uint256 _tstVal, uint256 _eurosVal) external {
        // Check if the contract has allowance to transfer both tokens
        bool isTstApproved = IERC20(TST).allowance(msg.sender, address(this)) >=
            _tstVal;

        bool isEurosApproved = IERC20(EUROs).allowance(
            msg.sender,
            address(this)
        ) >= _eurosVal;

        if (!isEurosApproved) revert VaultifyErrors.NotEnoughEurosAllowance();
        if (!isTstApproved) revert VaultifyErrors.NotEnoughTstAllowance();

        consolidatePendingStakes(); // []
        ILiquidationPoolManager(manager).distributeFees();

        if (_tstVal > 0) {
            IERC20(TST).safeTransferFrom(msg.sender, address(this), _tstVal);
        }

        if (_eurosVal > 0) {
            IERC20(TST).safeTransferFrom(msg.sender, address(this), _eurosVal);
        }

        // Push the stake request to pendingStake
        pendingStakes.push({
            holder: msg.sender,
            createdAt: block.timestamp,
            TstTokens: _tstVal,
            EurosTokens: _eurosVal
        });

        // Add the staker/holder as unique to avoid duplicate address
        addUniqueHolder(msg.sender);

        emit PositionIncreased(msg.sender, block.timestamp, _tstVal, _eurosVal);
    }

    // Deep work
    // function that allows pending stakes position to be consolidatin as position in the pool
    function consolidatePendingStakes() private {
        // Create a dealine variable to check the validity of the order
        uint256 deadline = block.timestamp - 1 days;

        for (int256 = 0; uint256(i) < pendingStakes.length; i++) {
            // get the data at the index(i)
            PendingStake memory _stakePending = pendingStakes[uint256(i)];

            // check if the pending stake is valid
            if (_stakePending.createdAt < deadline) {
                positions[_stakePending.holder].holder = _stakePending.holder;
                positions[_stakePending.holder].TstTokens += _stakePending
                    .TstTokens;
                positions[_stakePending.holder].EurosTokens += _stakePending
                    .EurosTokens;

                // Delete Pending Stakes of the users
                deletePendingStake(uint256(i));
                i--;
            }
        }
    }
}
