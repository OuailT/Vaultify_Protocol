// SPDX-License-Identifier: MIT
// pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";

////// Import Interfaces //////
import {ISmartVaultManagerMock} from "../src/mocks/ISmartVaultManagerMock.sol";
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
import {SmartVaultManager} from "../src/SmartVaultManager.sol";
import {SmartVaultManagerMock} from "../src/mocks/SmartVaultManagerMock.sol";
import {LiquidationPoolManager} from "../src/LiquidationPoolManager.sol";
import {LiquidationPool} from "../src/LiquidationPool.sol";

// Import library
import {VaultifyStructs} from "./../src/libraries/VaultifyStructs.sol";

// @audit-issue ASK chatGPT what cases I should test/cover

contract HelperTest is Test {
    // SETUP//
    ISmartVaultManagerMock public smartVaultManagerContract;
    ILiquidationPoolManager public liquidationPoolManagerContract;
    ILiquidationPool public liquidationPoolContract;

    ITokenManager public tokenManagerContract;
    ISmartVaultIndex public smartVaultIndexContract;

    // To store contracts address on deployement
    address public smartVaultManager; // Euros Admin as well
    address public liquidationPoolManager;
    address public pool;

    address public tokenManager;
    address public smartVaultIndex;
    address public smartVaultDeployer;

    // Assets Interfaces
    IEUROs public EUROs;
    IERC20Mock public TST; // Standard protocol
    IERC20Mock public WBTC;
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
    AggregatorV3InterfaceMock priceFeedNativeUsd;
    AggregatorV3InterfaceMock priceFeedEurUsd;
    AggregatorV3InterfaceMock priceFeedwBtcUsd;
    AggregatorV3InterfaceMock priceFeedPaxgUsd;

    address public chainlinkNativeUsd;
    address public chainlinkEurUsd;
    address public chainlinkwBtcUsd;
    address public chainlinkPaxgUsd;

    uint256 public collateralRate = 110000; // 110%
    uint256 public mintFeeRate = 2000; // 2%;
    uint256 public burnFeeRate = 3000; // 3%
    uint32 public poolFeePercentage = 50000; // 50%;

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
        WBTC = IERC20Mock(wbtc);
        PAXG = IERC20Mock(paxg);

        // Deploy Price Oracle contracts for assets;
        chainlinkNativeUsd = address(new ChainlinkMock("ETH / USD"));
        chainlinkEurUsd = address(new ChainlinkMock("EUR / USD"));
        chainlinkwBtcUsd = address(new ChainlinkMock("WBTC / USD"));
        chainlinkPaxgUsd = address(new ChainlinkMock("PAXG / USD"));

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
        smartVaultManager = address(new SmartVaultManagerMock());
        vm.stopPrank();

        vm.startPrank(smartVaultManager);
        euros = address(new EUROsMock());
        EUROs = IEUROs(euros);
        vm.stopPrank();

        vm.startPrank(owner);

        liquidator = address(0x5); // set liquidator address later

        smartVaultManagerContract = ISmartVaultManagerMock(smartVaultManager);

        // Initlize smartVaultManager
        smartVaultManagerContract.initialize(
            smartVaultIndex,
            mintFeeRate,
            burnFeeRate,
            collateralRate,
            protocol,
            liquidator,
            euros,
            tokenManager,
            smartVaultDeployer
        );

        // Deploy liquidationPoolManager
        liquidationPoolManager = address(
            new LiquidationPoolManager(
                tst,
                euros,
                smartVaultManager,
                chainlinkEurUsd,
                treasury,
                poolFeePercentage
            )
        );

        liquidationPoolManagerContract = ILiquidationPoolManager(
            liquidationPoolManager
        );

        // set the pool
        pool = liquidationPoolManagerContract.pool();
        liquidationPoolContract = ILiquidationPool(pool);

        // set liquidator to liquidation pool manager contract
        liquidator = liquidationPoolManager;

        // Set actors
        smartVaultManagerContract.setLiquidatorAddress(liquidator);
        smartVaultIndexContract.setVaultManager(smartVaultManager);

        // Add accepted collateral
        tokenManagerContract.addAcceptedToken(wbtc, chainlinkwBtcUsd);
        tokenManagerContract.addAcceptedToken(paxg, chainlinkPaxgUsd);

        vm.stopPrank();
    }

    function setInitialPrice() internal {
        // set assets Initial prices
        priceFeedNativeUsd.setPrice(2200 * 1e8); // $2200
        priceFeedEurUsd.setPrice(11037 * 1e4); // $1.1037
        priceFeedwBtcUsd.setPrice(42_000 * 1e8); // $42000
        priceFeedPaxgUsd.setPrice(2000 * 1e8); // $2000
    }

    ////////// Function Utilities /////////////
    function createUser(
        uint256 _id,
        uint256 _balance
    ) internal returns (address) {
        address user = vm.addr(_id + _balance);
        vm.label(user, "User");

        vm.deal(user, _balance * 1e18);
        TST.mint(user, _balance * 1e18);
        WBTC.mint(user, _balance * 1e18);
        PAXG.mint(user, _balance * 1e18);

        return user;
    }

    function createVaultOwners(
        uint256 _numOfOwners
    ) public returns (ISmartVault[] memory) {
        address _vaultOwner;
        // address _vaultAddr;
        ISmartVault vault;

        // Create a fixed sized array
        ISmartVault[] memory vaults = new ISmartVault[](_numOfOwners);

        for (uint256 i = 0; i < _numOfOwners; i++) {
            // create vault owners;
            _vaultOwner = createUser(i, 100);

            vm.startPrank(_vaultOwner);

            // 1- Mint a vault
            (uint256 tokenId, address vaultAddr) = smartVaultManagerContract
                .createNewVault();

            vault = ISmartVault(vaultAddr);

            // 2- Transfer collateral (Native, WBTC, and PAXG) to the vault
            // Transfer 10 ETH @ $2200, 1 BTC @ $42000, 10 PAXG @ $2000
            // Total initial collateral value: $84,000 or EUR76,107
            (bool sent, ) = payable(vaultAddr).call{value: 10 * 1e18}("");
            require(sent, "Native ETH trx failed");
            WBTC.transfer(vaultAddr, 1 * 1e18);
            PAXG.transfer(vaultAddr, 10 * 1e18);

            // Max mintable = euroCollateral() * HUNDRED_PC / collateralRate
            // Max mintable = 76,107 * 100000/110000 = 69,188

            // mint/borrow Euros from the vault
            // Vault borrower can borrow up to // 69,188 EUR || 80%
            // vault.borrowMint(_vaultOwner, 50_350 * 1e18);

            vm.stopPrank();

            vaults[i] = vault;
        }

        return vaults;
    }
}
