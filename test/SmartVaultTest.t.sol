// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {HelperTest} from "./HelperTest.t.sol";
import {ISmartVault} from "src/interfaces/ISmartVault.sol";
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";

import "forge-std/console.sol";

// TODOs  SLOW DOWN//
// [] Remove add address from createNewVault

contract SmartVaultTest is HelperTest {
    function setUp() public override {
        super.setUp();
        super.setUpHelper();
    }

    ////////////// Mint/Euros functions by Owner /////////////////

    /**
     - testSuccessfulMintingWithSufficientCollateral 
     - testMintingWithoutSufficientCollateral
    */

    function test_SuccessfulMintingWithSufficientCollateral() public {
        console.log("Hello from the ocean!!");
        // // 1-- mint a vault
        ISmartVault[] memory _vaults = new ISmartVault[](1);
        _vaults = createVaultOwners(1);
        vault = _vaults[0];

        vaultBalanceHelper(address(vault));

        // TODO
        // return the address of the getTokenManager from smart vault to check of it return the correct address of
        // Return the tokenManager from the smartVaultManager

        // Token manager from the proxy;
        // address tokenManagerV = proxySmartVaultManager.tokenManager();
        // console.log("tokenManager addreess", tokenManagerV);

        // get tokenManager address from smart vault;

        // get token by symbol(WBTC)
        // VaultifyStructs.Token memory _token = vault.getToken(
        //     bytes32(
        //         0x5742544300000000000000000000000000000000000000000000000000000000
        //     )
        // );

        // console.logBytes32(_token.symbol);
        // console.log("token decimals", _token.dec);

        // get the current status of the vault after sending collateral to the vault;
        VaultifyStructs.Status memory oldStatus = vault.status();
        address vaultAddress = oldStatus.vaultAddress;
        uint256 oldMinted = oldStatus.minted;
        uint256 oldMaxMintableEuro = oldStatus.maxMintable;
        uint256 oldEuroCollateral = oldStatus.totalCollateralValue;
        bool oldliquidated = oldStatus.liquidated;
        //---------------------------------------------------------//
        //     "--------------------Vault Status Before Borrow------------------"
        // );
        console.log("Vault Address: ", vaultAddress);
        console.log("oldMinted: ", oldMinted);
        console.log("oldMaxMintableEuro: ", oldMaxMintableEuro);
        console.log("oldEuroCollateral: ", oldEuroCollateral);
        console.log("oldliquidated: ", oldliquidated);
        console.log("-----------------------------------------------------");

        // // Test getAssetBalance
        // uint256 Balance = vault.euroCollateral(address(vault));
        // console.log("balance", Balance);
    }

    function vaultBalanceHelper(address _vault) public {
        console.log(
            "----------------------Vault balance in Collateral-------------------------------"
        );

        console.log("Vault ETH balance: ", _vault.balance / 1e18, "ETH");
        console.log(
            "Vault WBTC balance: ",
            WBTC.balanceOf(_vault) / 1e18,
            "WTBC"
        );
        console.log(
            "Vault WBTC balance: ",
            PAXG.balanceOf(_vault) / 1e18,
            "PAXG"
        );
    }
}
