// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {LiquidityPool} from "./LiquidityPool.sol";
import {ILiquidityPool} from "src/interfaces/ILiquidityPool.sol";
import {ISmartVaultManager} from "./interfaces/ISmartVaultManager.sol";
import {ITokenManager} from "./interfaces/ITokenManager.sol";
import {ILiquidationPoolManager} from "./interfaces/ILiquidationPoolManager.sol";

import {VaultifyStructs} from "./libraries/VaultifyStructs.sol";
import {VaultifyErrors} from "./libraries/VaultifyErrors.sol";
contract LiquidationPoolManager is
    ILiquidationPoolManager,
    Initializable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    // used to represent 100% in scaled format
    uint32 public constant HUNDRED_PRC = 100000;

    address private TST;
    address private EUROs;
    address public smartVaultManager;
    address payable private protocolTreasury;
    address public pool;
    address private eurUsdFeed;

    // 5000 => 5% || 1000 => 1%
    uint32 public poolFeePercentage;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _TST,
        address _EUROs,
        address _smartVaultManager,
        address _eurUsdFeed,
        address payable _protocolTreasury,
        uint32 _poolFeePercentage
    ) external initializer {
        // Address check for zero address NOTE
        __Ownable_init(msg.sender);
        eurUsdFeed = _eurUsdFeed;
        TST = _TST;
        EUROs = _EUROs;
        smartVaultManager = _smartVaultManager;
        protocolTreasury = _protocolTreasury;
        poolFeePercentage = _poolFeePercentage;
    }

    receive() external payable {}

    function createLiquidityPool() external onlyOwner returns (address) {
        pool = address(
            new LiquidityPool(
                TST,
                EUROs,
                eurUsdFeed,
                ISmartVaultManager(smartVaultManager).tokenManager()
            )
        );
    }

    // @audit-info consolidateFees before feedistribution.
    function distributeEurosFees() public {
        IERC20 eurosTokens = IERC20(EUROs);
        uint256 totalEurosBal = eurosTokens.balanceOf(address(this));

        // Calculate the fees based on the available Euros in the LiquidityPool Manager
        uint256 _feesForPool = (totalEurosBal * poolFeePercentage) /
            HUNDRED_PRC;

        if (_feesForPool > 0) {
            // Approve the pool to send the amount
            eurosTokens.approve(pool, _feesForPool);
            LiquidityPool(pool).distributeRewardFees(_feesForPool);
        }

        uint256 remainingBalance = totalEurosBal - _feesForPool;
        eurosTokens.safeTransfer(protocolTreasury, remainingBalance);
    }

    // @audit-info NOTE: liquidator is liquidityPoolManager(TODO: set address of liquidator/protocol to address(thuis))
    function executeLiquidation(uint256 _tokenId) external {
        ILiquidityPool(pool).consolidatePendingStakes();
        distributeEurosFees();
        // 1- Liquidate the vault that is under collatralized
        // Liquidation poool manager receives assets that has being liquidated from smart vault
        ISmartVaultManager vaultManager = ISmartVaultManager(smartVaultManager);
        vaultManager.liquidateVault(_tokenId);
        relayLiquidatedAssetsToPool();
    }

    function relayLiquidatedAssetsToPool() internal {
        bool assetsAllocated;
        // 1- Liquidate the vault that is under collatralized
        // Liquidation poool manager receives assets that has being liquidated from smart vault
        ISmartVaultManager vaultManager = ISmartVaultManager(smartVaultManager);

        // get all the accepted array by the protocol
        VaultifyStructs.Token[] memory _tokens = ITokenManager(
            vaultManager.tokenManager()
        ).getAcceptedTokens();

        VaultifyStructs.Asset[] memory _assets = new VaultifyStructs.Asset[](
            _tokens.length
        );

        uint256 ethBalance;

        //Allocate all the assets received by the liquitor(address(this)) and distribute them to stakers
        for (uint256 i = 0; i < _tokens.length; i++) {
            // check if token.addr is address(0)
            VaultifyStructs.Token memory _token = _tokens[i];
            if (_token.addr == address(0)) {
                ethBalance = address(this).balance;
                if (ethBalance > 0) {
                    _assets[i] = VaultifyStructs.Asset(_token, ethBalance);
                    assetsAllocated = true;
                }
            } else {
                IERC20 ierc20Token = IERC20(_token.addr);
                uint256 liquidatorErcBal = ierc20Token.balanceOf(address(this));
                if (liquidatorErcBal > 0) {
                    _assets[i] = VaultifyStructs.Asset(
                        _token,
                        liquidatorErcBal
                    );
                    ierc20Token.safeIncreaseAllowance(pool, liquidatorErcBal);
                    assetsAllocated = true;
                }
            }
        }

        if (assetsAllocated) {
            LiquidityPool(pool).distributeLiquatedAssets{value: ethBalance}(
                _assets,
                vaultManager.collateralRate(),
                vaultManager.HUNDRED_PRC()
            );
        }
    }

    function allocateFeesAndAssetsToPool() external {
        ILiquidityPool(pool).consolidatePendingStakes();
        distributeEurosFees();
        relayLiquidatedAssetsToPool();
    }

    // Fowards any token that the contract holds to the protocol/Trasury address
    function forwardRemainingAssetsToTreasury() public onlyOwner {
        ISmartVaultManager vaultManager = ISmartVaultManager(smartVaultManager);

        // get all the accepted array by the protocol
        VaultifyStructs.Token[] memory _tokens = ITokenManager(
            vaultManager.tokenManager()
        ).getAcceptedTokens();

        for (uint256 i = 0; i < _tokens.length; i++) {
            VaultifyStructs.Token memory token = _tokens[i];
            if (token.addr == address(0)) {
                uint256 ethBal = address(this).balance;
                if (ethBal > 0) {
                    (bool succeed, ) = protocolTreasury.call{value: ethBal}("");
                    if (!succeed) revert VaultifyErrors.NativeTxFailed();
                }
            } else {
                uint256 ercBal = IERC20(token.addr).balanceOf(address(this));
                if (ercBal > 0) {
                    IERC20(token.addr).transfer(protocolTreasury, ercBal);
                }
            }
        }
    }

    function setPoolFeePercentage(
        uint32 _poolFeePercentrage
    ) external onlyOwner {
        poolFeePercentage = _poolFeePercentrage;
    }
}
