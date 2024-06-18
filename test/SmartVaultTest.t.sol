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

    function test_helperFunction() public {
        createVaultOwners(1);
    }

    // /**** Test for Maximum Mintable Amount ****/
    // function test_MaximumMintableAmount() public {
    //     console.log("Testing maximum mintable amount");

    //     // Step 1: Mint a vault and transfer collateral
    //     ISmartVault[] memory _vaults = new ISmartVault[](1);
    //     (_vaults, alice) = createVaultOwners(1);
    //     vault = _vaults[0];

    //     // Step 2: Get initial status of the vault
    //     VaultifyStructs.Status memory initialStatus = vault.status();
    //     uint256 initialMaxMintableEuro = initialStatus.maxMintable;
    //     uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

    //     vm.startPrank(alice);

    //     // Step 3: Mint the maximum allowable euros
    //     vault.borrowMint(alice, initialMaxMintableEuro);

    //     // Step 4: Get new status of the vault
    //     VaultifyStructs.Status memory newStatus = vault.status();
    //     assertEq(newStatus.minted, initialMaxMintableEuro);
    //     assertEq(newStatus.maxMintable, initialMaxMintableEuro);
    //     assertEq(newStatus.totalCollateralValue, initialEuroCollateral);

    //     vm.stopPrank();
    // }

    // /**** Test for Successful Minting with Sufficient Collateral ****/
    // function test_SuccessfulMintingWithSufficientCollateral() public {
    //     console.log("Testing successful minting with sufficient collateral");

    //     // Step 1: Mint a vault and transfer collateral
    //     ISmartVault[] memory _vaults = new ISmartVault[](1);
    //     (_vaults, alice) = createVaultOwners(1);
    //     vault = _vaults[0];

    //     // Step 2: Get initial status of the vault
    //     VaultifyStructs.Status memory initialStatus = vault.status();
    //     uint256 initialMaxMintableEuro = initialStatus.maxMintable;
    //     uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

    //     vm.startPrank(alice);

    //     // Step 3: Mint a specific amount
    //     uint256 mintAmount = 55000 * 1e18; // Example mint amount
    //     vault.borrowMint(alice, mintAmount);

    //     // Step 4: Get new status of the vault
    //     VaultifyStructs.Status memory newStatus = vault.status();
    //     assertEq(newStatus.minted, mintAmount);
    //     assertEq(newStatus.maxMintable, initialMaxMintableEuro);
    //     assertEq(newStatus.totalCollateralValue, initialEuroCollateral);

    //     vm.stopPrank();
    // }

    /**** Test for Minting with Fee Deduction ****/
    // function test_MintingWithFeeDeduction() public {
    //     console.log("Testing minting with fee deduction");

    //     // Step 1: Mint a vault and transfer collateral
    //     ISmartVault[] memory _vaults = new ISmartVault[](1);
    //     (_vaults, alice) = createVaultOwners(1);
    //     vault = _vaults[0];

    //     // Step 2: Get initial status of the vault
    //     VaultifyStructs.Status memory initialStatus = vault.status();
    //     uint256 initialMaxMintableEuro = initialStatus.maxMintable;
    //     uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

    //     vm.startPrank(_vaultOwner);

    //     // Step 3: Mint a specific amount and check fee deduction
    //     uint256 mintAmount = 50000 * 1e18;
    //     uint256 fee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
    //         proxySmartVaultManager.HUNDRED_PRC();

    //     console.log("Fee on the 50_000 EUROS", fee);
    //     vault.borrowMint(address(_vaultOwner), mintAmount);

    //     // Step 4: Get new status of the vault
    //     VaultifyStructs.Status memory newStatus = vault.status();
    //     assertEq(newStatus.minted, mintAmount);

    //     console.log(
    //         "Alice Balance after mint",
    //         EUROs.balanceOf(address(_vaultOwner))
    //     );

    //     // assertEq(
    //     //     EUROs.balanceOf(alice),
    //     //     mintAmount - fee,
    //     //     "Fee aren't deducted"
    //     // );
    //     // assertEq(EUROs.balanceOf(proxySmartVaultManager.liquidator()), fee);
    //     // assertEq(newStatus.maxMintable, initialMaxMintableEuro);
    //     // assertEq(newStatus.totalCollateralValue, initialEuroCollateral);

    //     vm.stopPrank();
    // }
}
