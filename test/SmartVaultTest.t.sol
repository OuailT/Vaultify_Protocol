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
        (_vaults, alice) = createVaultOwners(1);
        vault = _vaults[0];

        vaultBalanceHelper(address(vault));

        // get the current status of the vault after sending collaterals to the vault;
        VaultifyStructs.Status memory oldStatus = vault.status();
        address vaultAddress = oldStatus.vaultAddress;
        uint256 oldMinted = oldStatus.minted;
        uint256 oldMaxMintableEuro = oldStatus.maxMintable; // 69,188 EUROS
        uint256 oldEuroCollateral = oldStatus.totalCollateralValue; // 76,107 EUROS
        bool oldliquidated = oldStatus.liquidated;
        // NOTE: I CAN BORROW 90.86% of EUROS out of 76.107 EUROS

        //---------------------------------------------------------//
        //     "--------------------Vault Status Before Borrow------------------"
        // );
        console.log("Vault Address: ", vaultAddress);
        console.log("oldMinted: ", oldMinted);
        console.log("oldMaxMintableEuro: ", oldMaxMintableEuro);
        console.log("oldEuroCollateral: ", oldEuroCollateral);
        console.log("oldliquidated: ", oldliquidated);
        console.log("-----------------------------------------------------");

        vm.startPrank(alice);
        //******** BORROW maxMintable */

        vault.borrowMint(55 * 1e18);

        // get the current status of the vault after sending collaterals to the vault;
        VaultifyStructs.Status memory newStatus = vault.status();
        uint256 newMinted = newStatus.minted;
        uint256 newMaxMintable = newStatus.maxMintable; // 69,188 EUROS
        uint256 newEurosCollateral = newStatus.totalCollateralValue; // 76,107 EUROS
        bool newLiquidated = newStatus.liquidated;
        // NOTE: I CAN BORROW 90.86% of EUROS out of 76.107 EUROS

        console.log("newMinted: ", newMinted);
        console.log("newMaxMintable: ", newMaxMintable);
        console.log("newEurosCollateral: ", newEurosCollateral);
        console.log("newLiquidated: ", newLiquidated);

        vm.stopPrank();
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
