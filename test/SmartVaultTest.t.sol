// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {HelperTest} from "./HelperTest.t.sol";
import {ISmartVault} from "src/interfaces/ISmartVault.sol";
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";
import {VaultifyEvents} from "src/libraries/VaultifyEvents.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";
import "forge-std/console.sol";

// TODOs  SLOW DOWN//

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
        emit VaultifyEvents.EUROsBurned(burnAmount - burnFee, burnFee);

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

        console.log("Alice balance before mint", EUROs.balanceOf(alice));

        // Step 2: Mint some EUROs to have an initial balance
        uint256 mintAmount = 50000 * 1e18;
        vm.startPrank(alice);
        vault.borrowMint(alice, mintAmount);
        vm.stopPrank();

        uint256 mintFee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        uint256 burnAmount = mintAmount - mintFee;
        console.log("Alice balance after mint", EUROs.balanceOf(alice));

        VaultifyStructs.Status memory initialStatus = vault.status();
        console.log("Minted After borrowing", initialStatus.minted); // includes fees

        // Step 3: Burn the exact amount of minted EUROs
        uint256 burnFee = (burnAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(alice);
        EUROs.approve(address(vault), burnAmount);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(burnAmount - burnFee, burnFee);

        vault.burnEuros(burnAmount);

        console.log("Alice balance after burn", EUROs.balanceOf(alice));
        console.log("Alice Minted balnce to burn", burnAmount);

        assertEq(
            EUROs.balanceOf(alice),
            0,
            "Incorrect Alice balance after burning the "
        );
        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            burnFee + mintFee,
            "Incorrect Liquidator balance after burning the exact amount of minted EUROs"
        );

        // Step 5: Check if the minted state variable was deducted
        VaultifyStructs.Status memory newStatus = vault.status();

        console.log("newStatus", newStatus.minted / 1e18);

        assertEq(
            newStatus.minted,
            0,
            "Minted/Borrowed state variable is not correct"
        );

        vm.stopPrank();
    }

    function test_BurnAndMintAgain() public {
        console.log("Testing burn followed by another mint");

        // Step 1: Mint a vault and transfer collateral
        ISmartVault[] memory _vaults = new ISmartVault[](1);
        (_vaults, alice) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Mint some EUROs to have an initial balance
        uint256 mintAmount = 20000 * 1e18;
        uint256 mintFee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsMinted(alice, mintAmount - mintFee, mintFee);

        vault.borrowMint(alice, mintAmount);

        vm.stopPrank();

        uint256 aliceMintedBalance = mintAmount - mintFee;

        // Step 3: Burn some EUROs
        uint256 burnAmount = 5000 * 1e18;
        uint256 burnFee = (burnAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        // Approve the vault to spend Euros token on alice's behalf
        vm.startPrank(alice);
        EUROs.approve(address(vault), burnAmount);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(burnAmount - burnFee, burnFee);

        vault.burnEuros(burnAmount);

        // Step 4: Mint more EUROs
        uint256 additionalMintAmount = 3000 * 1e18;
        uint256 additionalMintFee = (additionalMintAmount *
            proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vault.borrowMint(alice, additionalMintAmount);

        // aliceMintedBalance goes to alice wallet - burnAmount
        //
        // Step 5: Verify the balances
        uint256 expectedAliceBalance = aliceMintedBalance -
            burnAmount +
            (additionalMintAmount - additionalMintFee);

        console.log("Alice Balance", EUROs.balanceOf(alice));
        console.log("ExecptedAlice balance", expectedAliceBalance);

        assertEq(
            EUROs.balanceOf(alice),
            expectedAliceBalance,
            "Alice balance after minting again is not correct"
        );

        uint256 expectedLiquidatorBalance = mintFee +
            burnFee +
            additionalMintFee;

        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            expectedLiquidatorBalance,
            "Liquidator balance after minting again is not correct"
        );

        // Step 6: Check if the minted state variable was updated correctly
        VaultifyStructs.Status memory newStatus = vault.status();
        uint256 expectedMinted = mintAmount - burnAmount + additionalMintAmount;
        assertEq(
            newStatus.minted,
            expectedMinted,
            "Minted/Borrowed state variable is not correct"
        );

        vm.stopPrank();
    }

    // TODO: ADD TEST REVERT for BORROW MINT

    /*********************************************************
     **************************SWAP FUNCTION******************
     *********************************************************/

    function test_SwapPAXGtoWBTCWithoutMinting() public {
        console.log(
            "Testing swap from PAXG to WBTC without minting/borrwing EUROs"
        );

        // Step 1: Mint a vault and transfer collateral
        ISmartVault[] memory _vaults = new ISmartVault[](1);
        (_vaults, alice) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Swap PAXG to WBTC
        uint256 swapAmount = 10 * 1e18;
        uint256 swapFee = (swapAmount * proxySmartVaultManager.swapFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();
        uint256 minAmountOut = 9 * 1e8;
        uint24 poolFee = 3000; // 0.3% pool fee

        // Approve vault to spend PAXG tokens on alice's behalf
        vm.startPrank(alice);
        PAXG.approve(address(vault), swapAmount);

        vault.swap(
            bytes32(abi.encodePacked("PAXG")),
            bytes32(abi.encodePacked("WBTC")),
            swapAmount,
            poolFee,
            minAmountOut
        );

        ISwapRouter.MockSwapData memory swapData = swapRouterMockContract
            .receivedSwap();
        assertEq(swapData.tokenIn, address(PAXG), "tokenIn should be PAXG");
        assertEq(swapData.tokenOut, address(WBTC), "tokenOut should be WBTC");

        assertEq(
            swapData.amountIn,
            swapAmount - swapFee,
            "AmountIn should be correct"
        );
        assertEq(
            swapData.amountOutMinimum,
            minAmountOut,
            "AmountOutMinimum should be correct"
        );

        console.log("Swap executed successfully without minting/borrowing");

        vm.stopPrank();
    }

    function test_SwapAfterMintingAndBurning() public {
        console.log("Testing swap after minting and burning EUROs");

        // Step 1: Mint a vault and transfer collateral
        ISmartVault[] memory _vaults = new ISmartVault[](1);
        (_vaults, alice) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Mint/Borrow some EUROs to have an initial balance
        uint256 mintAmount = 50000 * 1e18;
        vm.startPrank(alice);
        vault.borrowMint(alice, mintAmount);
        vm.stopPrank();

        // Step 3: Burn some EUROs
        uint256 burnAmount = 10000 * 1e18;
        uint256 burnFee = (burnAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(alice);
        EUROs.approve(address(vault), burnAmount);
        vault.burnEuros(burnAmount);
        vm.stopPrank();

        // Step 5: Execute a swap
        uint256 amountIn = 10 * 1e18; // 10 PAXG
        uint256 swapFee = (amountIn * proxySmartVaultManager.swapFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();
        uint256 minAmountOut = 8 * 1e8; // Mock value for minimum amount out
        uint24 poolFee = 3000; // 0.3% pool fee

        vm.startPrank(alice);
        vault.swap(
            bytes32(abi.encodePacked("PAXG")),
            bytes32(abi.encodePacked("WBTC")),
            amountIn,
            poolFee,
            minAmountOut
        );
        vm.stopPrank();

        // Step 6: Verify the balances and state
        // Use mock data to verify swap execution and state variables
        ISwapRouter.MockSwapData memory swapData = swapRouterMockContract
            .receivedSwap();
        assertEq(swapData.tokenIn, address(PAXG), "TokenIn should be PAXG");
        assertEq(swapData.tokenOut, address(WBTC), "TokenOut should be WBTC");
        assertEq(
            swapData.amountIn,
            amountIn - swapFee,
            "AmountIn should be correct"
        );
        assertEq(
            swapData.amountOutMinimum,
            minAmountOut,
            "AmountOutMinimum should be correct"
        );

        console.log(
            "Swap executed successfully after minting and burning EUROs"
        );
    }

    function test_SwapETHToWBTC() public {
        console.log("Testing swap from ETH to WBTC");

        // Step 1: Mint a vault and transfer collateral
        ISmartVault[] memory _vaults = new ISmartVault[](1);
        (_vaults, alice) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 3: Execute a swap
        uint256 amountIn = 10 * 1e18; // 10 ETH
        uint256 swapFee = (amountIn * proxySmartVaultManager.swapFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();
        uint256 minAmountOut = 0.1 * 1e8; // Mock value for minimum amount out
        uint24 poolFee = 500; // 0.5% pool fee in basis point

        vm.startPrank(alice);
        vault.swap(
            bytes32(abi.encodePacked("ETH")),
            bytes32(abi.encodePacked("WBTC")),
            amountIn,
            poolFee,
            minAmountOut
        );
        vm.stopPrank();

        // Step 4: Verify the balances and state
        // Use mock data to verify swap execution and state variables
        ISwapRouter.MockSwapData memory swapData = swapRouterMockContract
            .receivedSwap();
        assertEq(
            swapData.tokenIn,
            proxySmartVaultManager.weth(),
            "TokenIn should be WETH"
        );
        assertEq(swapData.tokenOut, address(WBTC), "TokenOut should be WBTC");
        assertEq(
            swapData.amountIn,
            amountIn - swapFee,
            "AmountIn should be correct"
        );
        assertEq(
            swapData.amountOutMinimum,
            minAmountOut,
            "AmountOutMinimum should be correct"
        );

        assertEq((proxySmartVaultManager.liquidator()).balance, swapFee);

        console.log("Swap executed successfully from ETH to WBTC");
    }

    function test_SwapExactCollateralizationLimit() public {
        console.log("Testing swap at exact collateralization limit");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        VaultifyStructs.Status memory initialStatus = vault.status();
        uint256 maxMintable = initialStatus.maxMintable;

        vm.startPrank(_owner);
        vault.borrowMint(_owner, maxMintable);

        uint256 swapAmount = 1 ether;
        uint256 minAmountOut = 0;
        uint24 poolFee = 500;

        uint256 preSwapCollateral = vault.status().totalCollateralValue;

        vault.swap(
            bytes32("ETH"),
            bytes32("WBTC"),
            swapAmount,
            poolFee,
            minAmountOut
        );

        // Check MockSwapRouter data
        ISwapRouter.MockSwapData memory swapData = SwapRouterMock(
            address(swapRouterMockContract)
        ).receivedSwap();
        assertEq(
            swapData.tokenIn,
            address(proxySmartVaultManager.weth()),
            "Incorrect tokenIn"
        );
        assertEq(swapData.tokenOut, address(WBTC), "Incorrect tokenOut");
        assertEq(swapData.fee, poolFee, "Incorrect pool fee");
        assertEq(swapData.recipient, address(vault), "Incorrect recipient");
        assertEq(
            swapData.amountIn,
            swapAmount -
                (swapAmount * proxySmartVaultManager.swapFeeRate()) /
                proxySmartVaultManager.HUNDRED_PRC(),
            "Incorrect amountIn"
        );
        assertEq(
            swapData.amountOutMinimum,
            minAmountOut,
            "Incorrect amountOutMinimum"
        );

        VaultifyStructs.Status memory postSwapStatus = vault.status();

        assertGe(
            postSwapStatus.totalCollateralValue,
            (postSwapStatus.minted * proxySmartVaultManager.collateralRate()) /
                proxySmartVaultManager.HUNDRED_PRC(),
            "Vault should remain at or above collateralization limit"
        );
        assertLt(
            postSwapStatus.totalCollateralValue,
            preSwapCollateral,
            "Collateral should decrease due to swap fee"
        );

        vm.stopPrank();
    }

    // function test_SwapMoreThanAllowed() public {
    //     console.log("Testing swap of more than allowed amount");

    //     // Step 1: Mint a vault and transfer collateral
    //     ISmartVault[] memory _vaults = new ISmartVault[](1);
    //     (_vaults, alice) = createVaultOwners(1);
    //     vault = _vaults[0];

    //     // Step 2: Get vault status and calculate maxMintable
    //     VaultifyStructs.Status memory vaultStatus = vault.status();
    //     uint256 totalCollateralValue = vaultStatus.totalCollateralValue;
    //     uint256 maxMintable = vaultStatus.maxMintable;

    //     console.log("Euro Collateral:", totalCollateralValue);
    //     console.log("Max Mintable Euros:", maxMintable);

    //     // Step 3: Mint/borrow 80% of maxMintable
    //     uint256 mintAmount = (maxMintable * 80) / 100;
    //     vm.prank(alice);
    //     vault.borrowMint(alice, mintAmount);

    //     // Step 4: Attempt to swap more than 12% of collateral (let's try 15%)
    //     uint256 swapAmount = (totalCollateralValue * 15) / 100;
    //     uint256 swapAmountInETH = (swapAmount * 1e18) / 2200; // Convert EUR to ETH

    //     // Get the actual ETH balance of the vault
    //     uint256 vaultETHBalance = address(vault).balance;

    //     // Use the minimum of swapAmountInETH and vaultETHBalance
    //     uint256 actualSwapAmount = swapAmountInETH < vaultETHBalance
    //         ? swapAmountInETH
    //         : vaultETHBalance;

    //     uint256 minAmountOut = 0; // Set to 0 for this test
    //     uint24 poolFee = 500; // 0.5% pool fee in basis points
    //     uint256 swapFee = (actualSwapAmount *
    //         proxySmartVaultManager.swapFeeRate()) /
    //         proxySmartVaultManager.HUNDRED_PRC();

    //     console.log("Attempting to swap ETH amount:", actualSwapAmount);

    //     vm.prank(alice);
    //     vault.swap(
    //         bytes32("ETH"),
    //         bytes32("WBTC"),
    //         actualSwapAmount,
    //         poolFee,
    //         minAmountOut
    //     );

    //     // Step 5: Verify the swap results
    //     ISwapRouter.MockSwapData memory swapData = swapRouterMockContract
    //         .receivedSwap();

    //     // Checks if a is less than b
    //     // The actual swapped amount should be less than the requested amount
    //     assertLt(
    //         swapData.amountOutMinimum,
    //         actualSwapAmount - fee,
    //         "amountOutMinimum amount should be less than requested amount to swap"
    //     );

    //     // Step 6: Get updated vault status
    //     vaultStatus = vault.status();
    //     uint256 newTotalCollateralValue = vaultStatus.totalCollateralValue;
    //     uint256 mintedEuros = vaultStatus.minted;

    //     // Verify that the vault remains collateralized
    //     uint256 requiredCollateralValue = (mintedEuros *
    //         proxySmartVaultManager.collateralRate()) /
    //         proxySmartVaultManager.HUNDRED_PRC();

    //     // // greater than or equal to
    //     // assertGe(
    //     //     newTotalCollateralValue,
    //     //     requiredCollateralValue,
    //     //     "Vault should remain collateralized"
    //     // );

    //     console.log("New Euro Collateral:", newTotalCollateralValue / 1e18);
    //     console.log("required Collateral Value:", requiredCollateralValue / 1e18);
    //     console.log("Minted Euros:", mintedEuros);
    //     console.log("Swap of more than allowed amount handled correctly");
    // }
}
