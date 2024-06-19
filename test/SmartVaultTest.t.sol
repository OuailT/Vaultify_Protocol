// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {HelperTest} from "./HelperTest.t.sol";
import {ISmartVault} from "src/interfaces/ISmartVault.sol";
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";
import {VaultifyEvents} from "src/libraries/VaultifyEvents.sol";
import "forge-std/console.sol";

// TODOs  SLOW DOWN//
// [] Remove add address from createNewVault

contract SmartVaultTest is HelperTest {
    function setUp() public override {
        super.setUp();
        super.setUpHelper();
    }

    // /**** Test for Maximum Mintable Amount ****/
    function test_MaximumMintableAmount() public {
        console.log("Testing maximum mintable amount");

        // Step 1: Mint a vault and transfer collateral
        ISmartVault[] memory _vaults = new ISmartVault[](1);
        (_vaults, alice) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.Status memory initialStatus = vault.status();

        uint256 initialMaxMintableEuro = initialStatus.maxMintable;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(alice);

        // Step 3: Mint the maximum allowable euros
        vault.borrowMint(alice, initialMaxMintableEuro);

        // Step 4: Get new status of the vault
        VaultifyStructs.Status memory newStatus = vault.status();
        assertEq(newStatus.minted, initialMaxMintableEuro);
        assertEq(newStatus.maxMintable, initialMaxMintableEuro);
        assertEq(newStatus.totalCollateralValue, initialEuroCollateral);

        vm.stopPrank();
    }

    // /**** Test for Successful Minting with Sufficient Collateral ****/
    function test_SuccessfulMintingWithSufficientCollateral() public {
        console.log("Testing successful minting with sufficient collateral");

        // Step 1: Mint a vault and transfer collateral
        ISmartVault[] memory _vaults = new ISmartVault[](1);
        (_vaults, alice) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.Status memory initialStatus = vault.status();
        uint256 initialMaxMintableEuro = initialStatus.maxMintable;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(alice);

        // Step 3: Mint a specific amount
        uint256 mintAmount = 55000 * 1e18; // Example mint amount

        vault.borrowMint(alice, mintAmount);

        // Step 4: Get new status of the vault
        VaultifyStructs.Status memory newStatus = vault.status();
        assertEq(newStatus.minted, mintAmount);
        assertEq(newStatus.maxMintable, initialMaxMintableEuro);
        assertEq(newStatus.totalCollateralValue, initialEuroCollateral);

        vm.stopPrank();
    }

    /**** Test for Minting with Fee Deduction ****/
    function test_MintingWithFeeDeduction() public {
        console.log("Testing minting with fee deduction");

        // Step 1: Mint a vault and transfer collateral
        ISmartVault[] memory _vaults = new ISmartVault[](1);
        (_vaults, alice) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.Status memory initialStatus = vault.status();
        uint256 initialMaxMintableEuro = initialStatus.maxMintable;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(alice);

        // Step 3: Mint a specific amount and check fee deduction
        uint256 mintAmount = 50000 * 1e18;
        uint256 fee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsMinted(alice, mintAmount - fee, fee);

        console.log("Fee on the 50_000 EUROS", fee);
        vault.borrowMint(address(alice), mintAmount);

        // Step 4: Get new status of the vault
        VaultifyStructs.Status memory newStatus = vault.status();
        assertEq(newStatus.minted, mintAmount);

        console.log(
            "Alice Balance after mint",
            EUROs.balanceOf(address(alice))
        );

        assertEq(
            EUROs.balanceOf(alice),
            mintAmount - fee,
            "Fee aren't deducted"
        );
        assertEq(EUROs.balanceOf(proxySmartVaultManager.liquidator()), fee);
        assertEq(newStatus.maxMintable, initialMaxMintableEuro);
        assertEq(newStatus.totalCollateralValue, initialEuroCollateral);

        vm.stopPrank();
    }

    function test_MintingMultipleTimes() public {
        console.log("Testing minting multiple times");

        // Step 1: Mint a vault and transfer collateral
        ISmartVault[] memory _vaults = new ISmartVault[](1);
        (_vaults, alice) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.Status memory initialStatus = vault.status();
        uint256 initialMaxMintableEuro = initialStatus.maxMintable;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(alice);

        // Step 3: Mint in small increments
        uint256 mintAmount1 = 10000 * 1e18;
        uint256 mintAmount2 = 20000 * 1e18;
        uint256 mintAmount3 = 25000 * 1e18;
        uint256 totalMinted = mintAmount1 + mintAmount2 + mintAmount3;

        // total fees for all the borrowed EUROS
        uint totalFee = (totalMinted * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vault.borrowMint(alice, mintAmount1);
        vault.borrowMint(alice, mintAmount2);
        vault.borrowMint(alice, mintAmount3);

        // Step 4: Get new status of the vault
        VaultifyStructs.Status memory newStatus = vault.status();
        assertEq(newStatus.minted, totalMinted);
        assertEq(EUROs.balanceOf(alice), totalMinted - totalFee);
        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            totalFee
        );
        assertEq(newStatus.maxMintable, initialMaxMintableEuro);
        assertEq(newStatus.totalCollateralValue, initialEuroCollateral);

        vm.stopPrank();
    }

    // TODO: ADD TEST REVERT for BORROW MINT

    function test_SuccessfulBurn() public {
        console.log("Testing successful burn of EUROs");

        // Step 1: Mint a vault and transfer collateral
        ISmartVault[] memory _vaults = new ISmartVault[](1);
        (_vaults, alice) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Mint some EUROs to have an initial balance
        uint256 mintAmount = 50000 * 1e18;
        uint256 mintFee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(alice);
        vault.borrowMint(alice, mintAmount);
        vm.stopPrank();

        uint256 aliceMintedBalance = mintAmount - mintFee;

        // Step 3: Burn some EUROs
        uint256 burnAmount = 10000 * 1e18;
        uint256 burnFee = (burnAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        // Aprrove the vault to spend Euros token on alice behalf
        vm.startPrank(alice);
        EUROs.approve(address(vault), burnAmount);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(burnAmount, burnFee);

        vault.burnEuros(burnAmount);

        // Step 4: Verify the balances
        assertEq(
            EUROs.balanceOf(alice),
            ((aliceMintedBalance) - (burnAmount)),
            " Alice balance after burning is not correct"
        );

        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            burnFee + mintFee,
            "Liquidator balance after burning is not correct"
        );

        // Step 5: Check if the minted state variable was deducted
        VaultifyStructs.Status memory newStatus = vault.status();
        assertEq(
            newStatus.minted,
            mintAmount - burnAmount,
            "Minted/Borrowed state variable is not correct"
        );

        vm.stopPrank();
    }

    function test_BurnExactAmount() public {
        console.log("Testing burning the exact amount of minted EUROs");

        // Step 1: Mint a vault and transfer collateral
        ISmartVault[] memory _vaults = new ISmartVault[](1);
        (_vaults, alice) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Mint some EUROs to have an initial balance
        uint256 mintAmount = 50000 * 1e18;
        vm.startPrank(alice);
        vault.borrowMint(alice, mintAmount);
        vm.stopPrank();

        uint256 mintFee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        uint256 aliceMintedBalance = mintAmount - mintFee;

        // Step 3: Burn the exact amount of minted EUROs
        uint256 burnFee = (aliceMintedBalance *
            proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(alice);
        EUROs.approve(address(vault), aliceMintedBalance);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(aliceMintedBalance, burnFee);

        vault.burnEuros(aliceMintedBalance);

        assertEq(
            EUROs.balanceOf(alice),
            0,
            "Incorrect Alice balance after burning the "
        );
        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            burnFee,
            "Incorrect Liquidator balance after burning the exact amount of minted EUROs"
        );

        VaultifyStructs.Status memory newStatus = vault.status();
        console.log("minted", newStatus.minted);
        assertEq(
            newStatus.minted / 1e18,
            (mintAmount - aliceMintedBalance) / 1e18,
            "Minted/Borrowed state variable is not correct"
        );
        vm.stopPrank();
    }
}
