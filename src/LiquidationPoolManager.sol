// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LiquidationPool} from "./LiquidationPool.sol";
import {ISmartVaultManager} from "./interfaces/ISmartVaultManager.sol";
import {ITokenManager} from "./interfaces/ITokenManager.sol";

import {VaultifyStructs} from "./libraries/VaultifyStructs.sol";
import {VaultifyErrors} from "./libraries/VaultifyErrors.sol";
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

    // TODO ADD EVENT for Important function in the protocol

    constructor(
        address _TST,
        address _EUROs,
        address _smartVaultManager,
        address _eurUsd,
        address payable _protocol,
        uint32 _poolFeePercentage
    ) Ownable(msg.sender) {
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

    function executeLiquidation(uint256 _tokenId) external {
        // 1- Liquidate the vault that is under collatralized
        // Liquidation poool manager receives assets that has being liquidated from smart vault
        ISmartVaultManager vaultManager = ISmartVaultManager(smartVaultManager);
        vaultManager.liquidateVault(_tokenId);

        // 2- Distribute penrcentage of Fees among stakers and to the protocol coming from mint/burn/Swap
        distributeFees();

        // get all the accepted array by the protocol
        VaultifyStructs.Token[] memory _tokens = ITokenManager(
            vaultManager.tokenManager()
        ).getAcceptedTokens();

        VaultifyStructs.Asset[] memory _assets = new VaultifyStructs.Asset[](
            _tokens.length
        );

        uint256 liquidatorEthBal;

        //Allocate all the assets received by the liquitor(address(this)) and distribute them to stakers
        for (uint256 i = 0; i < _tokens.length; i++) {
            // check if token.addr is address(0)
            VaultifyStructs.Token memory _token = _tokens[i];
            if (_token.addr == address(0)) {
                liquidatorEthBal = address(this).balance;
                if (liquidatorEthBal > 0) {
                    _assets[i] = VaultifyStructs.Asset(
                        _token,
                        liquidatorEthBal
                    );
                }
            } else {
                IERC20 ierc20Token = IERC20(_token.addr);
                uint256 liquidatorErcBal = ierc20Token.balanceOf(address(this));
                if (liquidatorErcBal > 0) {
                    _assets[i] = VaultifyStructs.Asset(
                        _token,
                        liquidatorErcBal
                    );
                    ierc20Token.approve(pool, liquidatorErcBal);
                }
            }
        }

        LiquidationPool(pool).distributeLiquatedAssets{value: liquidatorEthBal}(
            _assets,
            vaultManager.collateralRate(),
            vaultManager.HUNDRED_PRC()
        );

        // Fowards any token that the contract holds to the protocol address
        forwardsRemainingRewards(_tokens);
    }

    function forwardsRemainingRewards(
        VaultifyStructs.Token[] memory _tokens
    ) private {
        for (uint256 i = 0; i < _tokens.length; i++) {
            VaultifyStructs.Token memory token = _tokens[i];
            if (token.addr == address(0)) {
                uint256 ethBal = address(this).balance;
                if (ethBal > 0) {
                    (bool succeed, ) = protocol.call{value: ethBal}("");
                    if (!succeed) revert VaultifyErrors.NativeTxFailed();
                }
            } else {
                uint256 ercBal = IERC20(token.addr).balanceOf(address(this));
                if (ercBal > 0) {
                    IERC20(token.addr).transfer(protocol, ercBal);
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
