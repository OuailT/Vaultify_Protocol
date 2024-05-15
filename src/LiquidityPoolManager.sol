// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LiquidationPool} from "./LiquidationPool.sol";
import {ISmartVaultManager} from "./interfaces/ISmartVaultManager.sol";

contract LiquidationPoolManager is Ownable {
    using SafeERC20 for IERC20;
    // used to represent 100% in scaled format
    uint32 public constant HUNDRED_PRC = 100000;

    address private immutable TST;
    address private immutable EUROs;
    address public immutable smartVaultManager;
    address payable private immutable protocol;
    address public immutable pool;

    // 5000 => 5% || 1000 => 1%
    uint32 public poolFeePercentage;

    constructor(
        address _TST,
        address _EUROs,
        address _smartVaultManager,
        address _eurUsd,
        address payable _protocol,
        uint32 _poolFeePercentage
    ) {
        pool = address(
            new LiquidationPool(
                _TST,
                _EUROs,
                _eurUsd,
                ISmartVaultManager(_smartVaultManager).tokenManager()
            )
        );

        TST = _TST;
        EUROs = _EUROs;
        smartVaultManager = _smartVaultManager;
        protocol = _protocol;
        poolFeePercentage = _poolFeePercentage;
    }

    receive() external payable {}

    function distributeFees() public onlyOwner {
        IERC20 eurosTokens = IERC20(EUROs);
        uint256 totalEurosBal = eurosTokens.balanceOf(address(this));

        // Calculate the fees based on the available Euros in the liquidationPool Manager
        uint256 _feesForPool = (totalEurosBal * poolFeePercentage) /
            HUNDRED_PRC;

        if (_feesForPool > 0) {
            // Approve the pool to send the amount
            eurosTokens.approve(pool, _feesForPool);
            LiquidationPool(pool).distributeRewardFees(_feesForPool);
        }

        eurosTokens.safeTransfer(protocol, totalEurosBal);
    }
}
