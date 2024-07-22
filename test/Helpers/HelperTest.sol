// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

////// Import Interfaces //////
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";
import {ISmartVaultManagerMock} from "src/mocks/ISmartVaultManagerMock.sol";
import {ILiquidationPoolManager} from "src/interfaces/ILiquidationPoolManager.sol";
import {ILiquidityPool} from "src/interfaces/ILiquidityPool.sol";
// import {ISmartVaultMock} from "src/interfaces/ISmartVaultMock.sol";
import {ISmartVault} from "src/interfaces/ISmartVault.sol";
import {ITokenManager} from "src/interfaces/ITokenManager.sol";
import {ISmartVaultDeployer} from "src/interfaces/ISmartVaultDeployer.sol";
import {ISmartVaultIndex} from "src/interfaces/ISmartVaultIndex.sol";
import {IEUROs} from "src/interfaces/IEUROs.sol";
import {AggregatorV3InterfaceMock} from "src/mocks/AggregatorV3InterfaceMock.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";

////// Import Mock Contracts //////
import {SwapRouterMock} from "src/mocks/SwapRouterMock.sol";
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
import {LiquidityPool} from "src/LiquidityPool.sol";

// Import library
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";

// TODO: Create a function to mirror arbithrum.
// // replace the address of uniswap ROUTER, PAXG, WBTC, WETH, TST, EUROS with the mocks.

abstract contract HelperTest is Test {
    ISmartVault internal vault;
    // SETUP//
    ISmartVaultManagerMock public smartVaultManagerContract;
    ILiquidationPoolManager public liquidationPoolManagerContract;
    ILiquidityPool public liquidityPoolContract;

    ITokenManager public tokenManagerContract;
    ISmartVaultIndex public smartVaultIndexContract;
    ISwapRouter public swapRouterMockContract;

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

    address public swapRouterMock;

    // Assets Interfaces
    IEUROs public EUROs;
    address public weth;
    IERC20Mock public TST; // Standard protocol
    IERC20Mock public WBTC;
    IERC20Mock public PAXG; // tokenized gold

    address public euros;
    address public tst;
    address public wbtc;
    address public paxg;

    address public protocolTreasury;

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
    uint256 public burnFeeRate = 2000; // 2%
    uint32 public poolFeePercentage = 50000; // 50%;
    uint256 public swapFeeRate = 1000; // 1%

    bytes32 public native;

    /*************ACCOUNTS */
    address internal admin = makeAddr("Admin");
    address internal alice = makeAddr("Alice");
    address internal bob = makeAddr("Bob");
    address internal jack = makeAddr("Jack");
    address internal treasury = payable(makeAddr("Treasury"));
    address internal liquidator = makeAddr("Liquidator");
    address internal vaultManager = makeAddr("SmartVaultManager");
    address internal poolManager = makeAddr("liquiditationPoolManager");

    /*********************** PROXIES *****************************/
    ProxyAdmin internal proxyAdmin;

    function setUp() public virtual {
        // @audit-issue NOT SURE about the protocol address yeT? will set it to liquidatioPoolManager contract???
        protocolTreasury = treasury;

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

        // IEUROs(euros).grantRole(IEUROs(euros).MINTER_ROLE(), address(vault));

        // Asign contracts to their interface
        TST = IERC20Mock(tst);
        WBTC = IERC20Mock(wbtc);
        PAXG = IERC20Mock(paxg);

        weth = address(new WETH());

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

        // deploy SwapRouter Mock contract
        swapRouterMock = address(new SwapRouterMock());

        swapRouterMockContract = ISwapRouter(swapRouterMock);

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

        vm.stopPrank();

        // Deploy the EUROS conract by proxySmartVaultManager to set it ad DEFAULT_ADMIN as it the contract
        // were newMintVault is created and should grant Burner and Minter roles to new Created Vault;
        vm.startPrank(address(proxySmartVaultManager));
        euros = address(new EUROsMock());
        EUROs = IEUROs(euros);
        vm.stopPrank();

        vm.startPrank(address(admin));
        // Initlize smartVaultManager implementation throught the proxies
        proxySmartVaultManager.initialize({
            _smartVaultIndex: address(proxySmartVaultIndex),
            _mintFeeRate: mintFeeRate,
            _burnFeeRate: burnFeeRate,
            _swapFeeRate: swapFeeRate,
            _collateralRate: collateralRate,
            _protocolTreasury: protocolTreasury,
            _liquidator: liquidator,
            _tokenManager: tokenManager,
            _smartVaultDeployer: smartVaultDeployer,
            _euros: euros,
            _weth: weth
        });

        proxyLiquidityPoolManager.initialize({
            _TST: tst,
            _EUROs: euros,
            _smartVaultManager: address(proxySmartVaultManager),
            _eurUsdFeed: chainlinkEurUsd,
            _protocolTreasury: payable(protocolTreasury),
            _poolFeePercentage: poolFeePercentage
        });

        proxySmartVaultIndex.initialize(address(proxySmartVaultManager));

        // // deploy a new Pool
        proxyLiquidityPoolManager.createLiquidityPool();

        pool = proxyLiquidityPoolManager.pool();
        console.log("Created Pool", pool);

        liquidityPoolContract = ILiquidityPool(pool);

        // set liquidator to liquidation pool manager contract
        liquidator = address(proxyLiquidityPoolManager);

        // // // Set actors
        proxySmartVaultManager.setLiquidatorAddress(
            address(proxyLiquidityPoolManager)
        );
        proxySmartVaultManager.setSwapRouter2(swapRouterMock);

        proxySmartVaultIndex.setVaultManager(address(proxySmartVaultManager));

        vm.stopPrank();

        // grant liquidityPool contract the burnerRole to burn EUROs when distributing LiquidatedAsssets.
        vm.startPrank(address(proxySmartVaultManager));
        EUROs.grantRole(EUROs.BURNER_ROLE(), address(pool));
        vm.stopPrank();
    }

    function setInitialPrice() private {
        // Advance the block timestamp by 1 day
        vm.warp(block.timestamp + 86400); // @audit-info put this at the end of the setup in case the problem of eurocollateral isn't solved
        // standard precision provided by price oracles like Chainlink.
        priceFeedNativeUsd.setPrice(2200 * 1e8); // $2200
        priceFeedEurUsd.setPrice(11037 * 1e4); // $1.1037
        // priceFeedEurUsd.setPrice(50000 * 1e18); // $1.1037
        priceFeedwBtcUsd.setPrice(42000 * 1e8); // $42000
        priceFeedPaxgUsd.setPrice(2000 * 1e8); // $2000
    }

    // Slow Down
    function setAcceptedCollateral() private {
        vm.startPrank(admin);
        console.log("euros address", proxySmartVaultManager.euros());
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
    function fundUserWallet(
        uint256 _id,
        uint256 _balance
    ) public returns (address) {
        address _user = vm.addr(_id + _balance);
        vm.label(_user, "User");

        vm.deal(_user, _balance * 1e18);
        TST.mint(_user, _balance * 1e18);
        EUROs.mint(_user, _balance * 1e18);
        WBTC.mint(_user, _balance * 1e8);
        PAXG.mint(_user, _balance * 1e18);

        return _user;
    }

    function createVaultOwners(
        uint256 _numOfOwners
    ) public returns (ISmartVault[] memory, address _vaultOwner) {
        // Create a fixed sized array
        ISmartVault[] memory vaults = new ISmartVault[](_numOfOwners);

        for (uint256 i = 0; i < _numOfOwners; i++) {
            // create vault owners;
            _vaultOwner = fundUserWallet(i, 100);
            vm.startPrank(_vaultOwner);

            // 1- Mint a vault
            (uint256 tokenId, address vaultAddr) = proxySmartVaultManager
                .mintNewVault();

            vault = ISmartVault(vaultAddr);

            // 2- Transfer collateral (Native, WBTC, and PAXG) to the vault
            // Transfer 10 ETH @ $2200, 1 BTC @ $42000, 10 PAXG @ $2000
            // Total initial collateral value: $84,000 or EUR76,107
            (bool sent, ) = payable(vaultAddr).call{value: 10 * 1e18}("");
            require(sent, "Native ETH trx failed");

            //-----------------------------------------------//
            // 10 ETH in EUROs based on the current price
            // 10 * 2200 / (1.1037) EUR/USD exchange rate =  10 ETH  == 19931.56 EUR; [x] correct
            //-----------------------------------------------//

            //-----------------------------------------------//
            // 1 WBTC * 42000 / (1.1037) EUR/USD exchange rate = 1 WTBC == 38052.87 EUR [x] correct
            WBTC.transfer(vaultAddr, 1 * 1e8);
            //-----------------------------------------------//

            //-----------------------------------------------//
            PAXG.transfer(vaultAddr, 10 * 1e18);
            // 10 PAXG * $2000 / (1.1037) EUR/USD exchange rate =10 PAXG == 18119.60 EUR [x] correct
            //-----------------------------------------------//

            // ISwapRouter.MockSwapData memory swapData = SwapRouterMock(
            //     proxySmartVaultManager.swapRouter2()
            // ).receivedSwap();

            // assertEq(swapData.tokenIn, address(WBTC), "TokenIn should be WBTC");
            // Max mintable = euroCollateral() * HUNDRED_PC / collateralRate
            // Max mintable = 76,107 * 100000/110000 = 69,188

            // mint/borrow Euros from the vault
            // Vault borrower can borrow up to // 69,188 EUR || 80%
            // vault.borrowMint(_vaultOwner, 50_350 * 1e18);

            vm.stopPrank();

            vaults[i] = vault;
        }

        return (vaults, _vaultOwner);
    }
}
