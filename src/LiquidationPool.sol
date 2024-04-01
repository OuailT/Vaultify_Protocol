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
        uint256 tstTokens;
        uint256 eurosTokens;
    }

    struct PendingStake {
        address holder;
        uint256 createdAt;
        uint256 tstTokens;
        uint256 eurosTokens;
    }

    struct Rewards {
        bytes32 symbol;
        uint256 amount;
        uint8 dec;
    }

    address[] public holders;
    mapping(address => Position) private positions;
    mapping(bytes => uint256) private rewards;

    PendingStake[] private pendingStakes;

    address payable public poolManager;
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
        poolManager = payable(msg.sender);
    }

    // TODO Change tokens other tokens names
    function increasePosition(uint256 _tstVal, uint256 _eurosVal) external {
        require(_tstVal > 0 || _eurosVal > 0);

        // Check if the contract has allowance to transfer both tokens
        bool isTstApproved = IERC20(TST).allowance(msg.sender, address(this)) >=
            _tstVal;

        bool isEurosApproved = IERC20(EUROs).allowance(
            msg.sender,
            address(this)
        ) >= _eurosVal;

        if (!isEurosApproved) revert VaultifyErrors.NotEnoughEurosAllowance();
        if (!isTstApproved) revert VaultifyErrors.NotEnoughTstAllowance();

        consolidatePendingStakes(); // [x] TODO
        ILiquidationPoolManager(poolManager).distributeFees(); // [x] TODO

        if (_tstVal > 0) {
            IERC20(TST).safeTransferFrom(msg.sender, address(this), _tstVal);
        }

        if (_eurosVal > 0) {
            IERC20(EUROs).safeTransferFrom(
                msg.sender,
                address(this),
                _eurosVal
            );
        }

        // Push the stake request to pendingStake
        pendingStakes.push({
            holder: msg.sender,
            createdAt: block.timestamp,
            tstTokens: _tstVal,
            eurosTokens: _eurosVal
        });

        // Add the staker/holder as unique to avoid duplicate address
        addUniqueHolder(msg.sender); // TODO

        emit PositionIncreased(msg.sender, block.timestamp, _tstVal, _eurosVal);
    }

    // decrease position function
    function decreasePosition(uint256 _tstVal, uint256 _eurosVal) external {
        // READ from memory
        Position memory _userPosition = positions[msg.sender];
        // Check if the user has enough tst or Euros tokens to remove from it position

        if (
            _userPosition.tstTokens < _tstVal &&
            _userPosition.eurosTokens < _eurosVal
        ) revert VaultifyErrors.InvalidDecrementAmount();

        consolidatePendingStakes();
        ILiquidationPoolManager(poolManager).distributeFees();

        if (_tstVal > 0) {
            IERC20(TST).safeTransfer(msg.sender, _tstVal);
            unchecked {
                _userPosition.tstTokens -= _tstVal;
            }
        }

        if (_eurosVal > 0) {
            IERC20(EUROs).safeTransfer(msg.sender, _eurosVal);
            unchecked {
                _userPosition.eurosTokens -= _eurosVal;
            }
        }

        // create function to check if the positon is Empty
        if (userPosition.tstTokens == 0 && userPosition.eurosTokens == 0) {
            deletePosition(_userPosition);
        }

        emit positionDecreased(msg.sender, _tstVal, _eurosVal);
    }

    function deleteHolder(address _holder) private {
        for (uint256 i = 0; i < holders.length; ) {
            // the element to be deleted is found at index i
            if (holders[i] == _holder) {
                // replace the amount to be deleted with the last element in the array: to save gas
                holders[i] == holders[holders.length - 1];
                holders.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    // delete Positions and holders
    function deletePosition(Position memory _position) private {
        // delete holder
        deleteHolder(_position.holder);
        delete positions[_position.holder];
    }

    // deletePendingStake
    function deletePendingStake(uint256 _i) private {
        for (uint256 i = _i; i < pendingStakes.length - 1; ) {
            pendingStakes[i] = pendingStakes[i + 1];
            unchecked {
                ++i;
            }
        }
        pendingStakes.pop();
    }

    function addUniqueHolder(address _holder) private {
        for (uint256 i = 0; i < holders.length; ) {
            // Check for duplicate
            if (holders[i] == _holder) return;
            unchecked {
                ++i;
            }
        }
        holders.push(_holder);
    }

    // Deep work
    // function that allows pending stakes position to be consolidatin as position in the pool
    function consolidatePendingStakes() private {
        // Create a dealine variable to check the validity of the order
        uint256 deadline = block.timestamp - 1 days;

        for (int256 i = 0; uint256(i) < pendingStakes.length; i++) {
            // get the data at the index(i)
            PendingStake memory _stakePending = pendingStakes[uint256(i)];

            // To prevent front-runing attacks to take advantage of rewards
            if (_stakePending.createdAt < deadline) {
                // WRITE to STORAGE
                Position storage position = positions[_stakePending.holder];
                position.holder = _stakePending.holder;
                position.tstTokens += _stakePending.tstTokens;
                position.eurosTokens += _stakePending.eurosTokens;

                // Delete Pending Stakes of the users
                deletePendingStake(uint256(i));
                i--;
            }
        }
    }
}

/**

    positions[_stakePending.holder].holder = _stakePending.holder;
positions[_stakePending.holder].tstTokens += _stakePending.tstTokens;
positions[_stakePending.holder].eurosTokens += _stakePending.eurosTokens;


 */
