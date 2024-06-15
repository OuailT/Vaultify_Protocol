// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

////// Import Interfaces //////
import {ISmartVaultManagerMock} from "src/mocks/ISmartVaultManagerMock.sol";
import {ILiquidationPoolManager} from "src/interfaces/ILiquidationPoolManager.sol";
import {ILiquidationPool} from "src/interfaces/ILiquidationPool.sol";
// import {ISmartVaultMock} from "src/interfaces/ISmartVaultMock.sol";
import {ISmartVault} from "src/interfaces/ISmartVault.sol";
import {ITokenManager} from "src/interfaces/ITokenManager.sol";
import {ISmartVaultDeployer} from "src/interfaces/ISmartVaultDeployer.sol";
import {ISmartVaultIndex} from "src/interfaces/ISmartVaultIndex.sol";
import {IEUROs} from "src/interfaces/IEUROs.sol";
import {AggregatorV3InterfaceMock} from "src/mocks/AggregatorV3InterfaceMock.sol";

////// Import Mock Contracts //////
import {ERC20Mock} from "src/mocks/ERC20Mock.sol";
import {IERC20Mock} from "src/mocks/IERC20Mock.sol";
import {EUROsMock} from "src/mocks/EUROsMock.sol";
import {TokenManagerMock} from "src/mocks/TokenManagerMock.sol";
import {SmartVaultDeployer} from "utils/SmartVaultDeployer.sol";
import {SmartVaultIndex} from "utils/SmartVaultIndex.sol";
import {ChainlinkMockForTest} from "src/mocks/ChainlinkMock.sol";

// Import contracts In the scope //
// import {SmartVaultManager} from "src/SmartVaultManager.sol";
import {SmartVaultManagerMock} from "src/mocks/SmartVaultManagerMock.sol";
import {LiquidationPoolManager} from "src/LiquidationPoolManager.sol";
import {LiquidationPool} from "src/LiquidationPool.sol";

// Import library
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";

// @audit-issue ASK chatGPT what cases I should test/cover

abstract contract HelperTest is Test {
    ISmartVault internal vault;
    // SETUP//
    ISmartVaultManagerMock public smartVaultManagerContract;
    ILiquidationPoolManager public liquidationPoolManagerContract;
    ILiquidationPool public liquidationPoolContract;

    ITokenManager public tokenManagerContract;
    ISmartVaultIndex public smartVaultIndexContract;

    /*********************** IMPLEMENTATION *****************************/
    address public smartVaultManagerImplementation; // Euros Admin as well
    address public liquidationPoolManagerImplementation;
    address public smartVaultIndexImplementation;
    address public pool;

    /*********************** PROXIES *****************************/
    SmartVaultManagerMock internal proxySmartVaultManager;
    LiquidationPoolManager internal proxyLiquidityPoolManager;
    SmartVaultIndex internal proxySmartVaultIndex;

    address public tokenManager;
    // address public smartVaultIndex;
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

    address public protocol;

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

    /*************ACCOUNTS */
    address internal admin = makeAddr("Admin");
    address internal alice = makeAddr("Alice");
    address internal treasury = payable(makeAddr("Treasury"));
    address internal liquidator = makeAddr("Liquidator");
    address internal vaultManager = makeAddr("SmartVaultManager");
    address internal poolManager = makeAddr("liquiditationPoolManager");

    /*********************** PROXIES *****************************/
    ProxyAdmin internal proxyAdmin;

    function setUp() public virtual {
        protocol = treasury;

        bytes32 _native = bytes32(abi.encodePacked("ETH"));
        native = _native;

        vm.startPrank(admin);

        // Deploy Collateral assets contracts //
        tst = address(new ERC20Mock("TST", "TST", 18));
        wbtc = address(new ERC20Mock("WBTC", "WBTC", 8));
        paxg = address(new ERC20Mock("PAXG", "PAXG", 18));

        vm.label(tst, "TST");
        vm.label(wbtc, "WBTC");
        vm.label(paxg, "PAXG");

        euros = address(new EUROsMock());
        EUROs = IEUROs(euros);

        // Asign contracts to their interface
        TST = IERC20Mock(tst);
        WBTC = IERC20Mock(wbtc);
        PAXG = IERC20Mock(paxg);

        // Deploy the proxy admin for all system contract
        proxyAdmin = new ProxyAdmin(address(admin));

        // Deploy Price Oracle contracts for assets;
        chainlinkNativeUsd = address(new ChainlinkMockForTest("ETH / USD"));
        chainlinkEurUsd = address(new ChainlinkMockForTest("EUR / USD"));
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

        // // deploy smartVaultIndex.sol
        // smartVaultIndex = address(new SmartVaultIndex());

        // smartVaultIndexContract = ISmartVaultIndex(smartVaultIndex);

        // Deploy implementation for all the system
        smartVaultManagerImplementation = address(new SmartVaultManagerMock());
        liquidationPoolManagerImplementation = address(
            new LiquidationPoolManager()
        );
        smartVaultIndexImplementation = address(new SmartVaultIndex());

        // Deploy proxies for all the system
        proxySmartVaultManager = SmartVaultManagerMock(
            address(
                new TransparentUpgradeableProxy(
                    smartVaultManagerImplementation,
                    address(proxyAdmin),
                    ""
                )
            )
        );

        // NOTE: When deploying the proxy and the implementation
        // at this stage liquidationPoolManager implementation is disables
        proxyLiquidityPoolManager = LiquidationPoolManager(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        liquidationPoolManagerImplementation,
                        address(proxyAdmin),
                        ""
                    )
                )
            )
        );

        proxySmartVaultIndex = SmartVaultIndex(
            address(
                new TransparentUpgradeableProxy(
                    smartVaultIndexImplementation,
                    address(proxyAdmin),
                    ""
                )
            )
        );

        // Initlize smartVaultManager implementation throught the proxies
        proxySmartVaultManager.initialize({
            _smartVaultIndex: address(proxySmartVaultIndex),
            _mintFeeRate: mintFeeRate,
            _burnFeeRate: burnFeeRate,
            _collateralRate: collateralRate,
            _protocol: protocol,
            _liquidator: liquidator,
            _tokenManager: tokenManager,
            _smartVaultDeployer: smartVaultDeployer
        });

        proxyLiquidityPoolManager.initialize({
            _TST: tst,
            _EUROs: euros,
            _smartVaultManager: address(proxySmartVaultManager),
            _eurUsdFeed: chainlinkEurUsd,
            _protocol: payable(protocol),
            _poolFeePercentage: poolFeePercentage
        });

        proxySmartVaultIndex.initialize(address(proxySmartVaultManager));

        // // deploy a new Pool
        pool = proxyLiquidityPoolManager.createLiquidityPool();

        liquidationPoolContract = ILiquidationPool(pool);

        // set liquidator to liquidation pool manager contract
        liquidator = address(proxyLiquidityPoolManager);

        // // // Set actors
        proxySmartVaultManager.setLiquidatorAddress(
            address(proxyLiquidityPoolManager)
        );

        proxySmartVaultIndex.setVaultManager(address(proxySmartVaultManager));

        vm.stopPrank();
    }

    function setInitialPrice() private {
        // Advance the block timestamp by 1 day
        vm.warp(block.timestamp + 86400);
        priceFeedNativeUsd.setPrice(2200 * 1e8); // $2200
        priceFeedEurUsd.setPrice(11037 * 1e4); // $1.1037
        priceFeedwBtcUsd.setPrice(42000 * 1e8); // $42000
        priceFeedPaxgUsd.setPrice(2000 * 1e8); // $2000
    }

    // Slow Down
    function setAcceptedCollateral() private {
        vm.startPrank(admin);
        // Add accepted collateral
        tokenManagerContract.addAcceptedToken(wbtc, chainlinkwBtcUsd);
        tokenManagerContract.addAcceptedToken(paxg, chainlinkPaxgUsd);
        vm.stopPrank();
    }

    function setUpHelper() internal virtual {
        setAcceptedCollateral();
        setInitialPrice();
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
        // address owner;
        address _vaultOwner;
        // ISmartVault vault;

        // Create a fixed sized array
        ISmartVault[] memory vaults = new ISmartVault[](_numOfOwners);

        for (uint256 i = 0; i < _numOfOwners; i++) {
            // create vault owners;
            _vaultOwner = createUser(i, 100);

            vm.startPrank(_vaultOwner);

            // 1- Mint a vault
            (uint256 tokenId, address vaultAddr) = proxySmartVaultManager
                .mintNewVault();

            vault = ISmartVault(vaultAddr);

            // 2- Transfer collateral (Native, WBTC, and PAXG) to the vault
            // Transfer 10 ETH @ $2200, 1 BTC @ $42000, 10 PAXG @ $2000
            // Total initial collateral value: $84,000 or EUR76,107
            // (bool sent, ) = payable(vaultAddr).call{value: 10 * 1e18}("");
            // require(sent, "Native ETH trx failed");
            // 10 ETH in EUROs based on the current price
            // 10 * 2200 / (1.1037) EUR/USD exchange rate =  10 ETH  == 19931.56 EUR; [x] correct

            WBTC.transfer(vaultAddr, 1 * 1e18);
            // PAXG.transfer(vaultAddr, 10 * 1e18);

            console.log("VaultAddress from helper", vaultAddr);

            // TODO  test if getTokenManaer.getacceptedTokens() is implemented correctly
            // returns the same TokenManager address

            VaultifyStructs.Token[] memory tokens = vault
                .getTokenManager()
                .getAcceptedTokens();

            // ETH
            VaultifyStructs.Token memory token = tokens[1];
            console.log("token address", token.addr);

            // [x]
            // VaultifyStructs.Token[] memory tokens = tokenManagerContract
            //     .getAcceptedTokens();
            // VaultifyStructs.Token memory token = tokens[1];
            // console.log("token address", token.addr);

            // uint256 balanceInWBTC = vault.getAssetBalance(
            //     token.symbol,
            //     token.addr
            // );
            // console.log("balance In WBTC ", balanceInWBTC);

            // TODO Get the price feed from the ChainLink Oracle price feeds[x]
            // NOTE maybe the price for Native is not SET as it not added as token so there is not address
            // WRONG : all price are well set.
            // to check every function @audit-info must call tokenToEuro function from price calculator

            /// $$$$$$$$$$$$$$$$$$$$$$ ///
            /// TODO: Set one collateral at the time and compare retrive it value in EUROs and add more
            // compare it to other and see from were the problem is comming from

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
