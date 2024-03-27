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

contract LiquidationPool is ILiquidationPool {
    using SafeERC20 for IERC20;
    
}
