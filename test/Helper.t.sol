// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

////// Import Interfaces //////
import {ISmartVaultManager} from "../src/interfaces/ISmartVaultManager.sol";
import {ILiquidationPoolManager} from "../src/interfaces/ILiquidationPoolManager.sol";
import {ILiquidationPool} from "../src/interfaces/ILiquidationPool.sol";
import {ISmartVault} from "../src/interfaces/ISmartVault.sol";
import {ITokenManager} from "../src/interfaces/ITokenManager.sol";
import {ISmartVaultDeployer} from "../src/interfaces/ISmartVaultDeployer.sol";
import {ISmartVaultIndex} from "../src/interfaces/ISmartVaultIndex.sol";
import {IEUROs} from "../src/interfaces/IEUROs.sol";
import {AggregatorV3InterfaceMock} from "../src/mocks/AggregatorV3InterfaceMock.sol";

////// Import Mock Contracts //////
import {ERC20Mock} from "../src/mocks/ERC20Mock.sol";
import {IERC20Mock} from "../src/mocks/IERC20Mock.sol";
import {EUROsMock} from "../src/mocks/EUROsMock.sol";
import {TokenManagerMock} from "../src/mocks/TokenManagerMock.sol";
import {SmartVaultDeployer} from "./../utils/SmartVaultDeployer.sol";
import {SmartVaultIndex} from "./../utils/SmartVaultIndex.sol";
import {ChainlinkMock} from "../src/mocks/ChainlinkMock.sol";

// Import contracts In the scope //
import {SmartVaultManager} from "./../src/SmartVaultManager.sol";
import {LiquidityPoolManager} from "./../src/LiquidityPoolManager.sol";
import {LiquidationPool} from "./../src/LiquidationPool.sol";

// @audit-issue ASK chatGPT what cases I should test/cover

contract Helper is Test {
    // SETUP//
    ISmartVaultManager public smartVaultManagerContract;
    ILiquidationPoolManager public liquidationPoolManagerContract;
    ILiquidationPool public liquidationPoolContract;

    ITokenManager public tokenManagerContract;
    ISmartVaultIndex public smartVaultIndexContract;

    // To store contracts address on deployement
    address public smartVaultManager;
    address public liquidationPoolManager;
    address public pool;

    address public tokenManager;
    address public smartVaultIndex;
    address public smartVaultDeployer;

    // Assets Interfaces
    IEUROs public EUROs;
    IERC20Mock public TST; // Standard protocol
    IERC20Mock public WTBC;
    IERC20Mock public PAXG; // tokenized gold

    address public euros;
    address public tst;
    address public wbtc;
    address public paxg;

    // Actors;
    address public owner;
    address public protocol;
    address public liquidator;
    address payable public treasury;

    ////// Oracle Contracts //////
    AggregatorV3InterfaceForTest priceFeedNativeUsd;
    AggregatorV3InterfaceForTest priceFeedEurUsd;
    AggregatorV3InterfaceForTest priceFeedwBtcUsd;
    AggregatorV3InterfaceForTest priceFeedPaxgUsd;

    address public chainlinkNativeUsd;
    address public chainlinkEurUsd;
    address public chainlinkwBtcUsd;
    address public chainlinkPaxgUsd;

    uint256 public collateral = 110000; // 110%
    uint256 public feeRate = 2000; // 2%;
    uint256 public poolFeePercentage = 50000; // 50%;

    bytes32 public native;

    function setUp() public virtual {
        // Create Actor //
        owner = vm.addr(0x1);
        treasury = payable(vm.addr(0x2));

        vm.label(owner, "Owner");
        vm.label(treasury, "Treasury");

        protocol = treasury;

        bytes32 _native = bytes32(abi.encodePacked("ETH"));
        native = _native;

        vm.startPrank(owner);
        // Deploy Collateral assets contracts //
        tst = address(new ERC20Mock("TST", "TST", 18));
        wbtc = address(new ERC20Mock("WBTC", "WBTC", 8));
        paxg = address(new ERC20Mock("PAXG", "PAXG", 18));

        // Asign contracts to their interface
        TST = IERC20Mock(tst);
        WTBC = IERC20Mock(wbtc);
        PAXG = IERC20Mock(paxg);

        // Deploy Price Oracle contracts for assets;
        chainlinkNativeUsd = address(new ChainlinkMock("ETH / USD"));
        chainlinkEurUsd = address(new ChainlinkMock("EUR / USD"));
        chainlinkwBtcUsd = address(new ChainlinkMockForTest("WBTC / USD"));
        chainlinkPaxgUsd = address(new ChainlinkMockForTest("PAXG / USD"));

        // Asign contracts to their interface
        priceFeedNativeUsd = AggregatorV3InterfaceMock(chainlinkNativeUsd);
        priceFeedEurUsd = AggregatorV3InterfaceMock(chainlinkEurUsd);
        priceFeedwBtcUsd = AggregatorV3InterfaceMock(chainlinkwBtcUsd);
        priceFeedPaxgUsd = AggregatorV3InterfaceMock(chainlinkPaxgUsd);

        // deploy tokenManager.sol contract
        tokenManager = address(
            new TokenManagerMock(native, address(chainlinkNativeUsd))
        );
        tokenManagerContract = ITokenManager(tokenManager);

        // deploy smartvaultdeployer.sol
        smartVaultDeployer = address(
            new SmartVaultDeployer(native, address(chainlinkEurUsd))
        );

        // deploy smartVaultIndex.sol
        smartVaultIndex = address(new SmartVaultIndex());
        smartVaultIndexContract = ISmartVaultIndex(smartVaultIndex);

        // deploy SmartVaultManager
        smartVaultManager = address(new SmartVaultManager());
        vm.stopPrank();
    }
}
