// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {HelperTest} from "./HelperTest.t.sol";
import {ISmartVault} from "../src/interfaces/ISmartVault.sol";
import {VaultifyStructs} from "../src/libraries/VaultifyStructs.sol";

import "forge-std/console.sol";

// TODOs  SLOW DOWN//
// [] Remove add address from createNewVault

contract SmartVaultTest is HelperTest {
    ISmartVault vault;

    function setUp() public override {
        super.setUp();
        super.setUpHelper();
    }

    ////////////// Mint/Euros functions by Owner /////////////////

    /**
     - testSuccessfulMintingWithSufficientCollateral 
     - testMintingWithoutSufficientCollateral
    */

    // function test_SuccessfulMintingWithSufficientCollateral() public {
    // console.log("Hello from the ocean!!");

    // // 1-- mint a vault
    // ISmartVault[] memory _vaults = new ISmartVault[](1);
    // _vaults = createVaultOwners(1);
    // vault = _vaults[0];
    // get the current status of the vault after sending collateral to the vault;
    // VaultifyStructs.Status memory oldStatus = vault.status();
    // uint256 oldMinted = oldStatus.minted;
    // uint256 oldMaxMintableEuro = oldStatus.maxMintable;
    // uint256 oldEuroCollateral = oldStatus.totalCollateralValue;
    // bool oldliquidated = oldStatus.liquidated;
    // console.log(
    //     "--------------------Vault Status Before Borrow------------------"
    // );
    // console.log("oldMinted: ", oldMinted);
    // console.log("oldMaxMintableEuro: ", oldMaxMintableEuro);
    // console.log("oldEuroCollateral: ", oldEuroCollateral);
    // console.log("oldliquidated: ", oldliquidated);
    // console.log("-----------------------------------------------------");
    // }
}
