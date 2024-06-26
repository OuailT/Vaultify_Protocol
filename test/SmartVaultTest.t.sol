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
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();

        uint256 initialMaxMintableEuro = initialStatus.maxBorrowableEuros;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(alice);

        // Step 3: Mint the maximum allowable euros
        vault.borrow(alice, initialMaxMintableEuro);

        // Step 4: Get new status of the vault
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        assertEq(newStatus.borrowedAmount, initialMaxMintableEuro);
        assertEq(newStatus.maxBorrowableEuros, initialMaxMintableEuro);
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
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 initialMaxMintableEuro = initialStatus.maxBorrowableEuros;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(alice);

        // Step 3: Mint a specific amount
        uint256 mintAmount = 55000 * 1e18; // Example mint amount

        vault.borrow(alice, mintAmount);

        // Step 4: Get new status of the vault
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        assertEq(newStatus.borrowedAmount, mintAmount);
        assertEq(newStatus.maxBorrowableEuros, initialMaxMintableEuro);
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
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 initialMaxMintableEuro = initialStatus.maxBorrowableEuros;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(alice);

        // Step 3: Mint a specific amount and check fee deduction
        uint256 mintAmount = 50000 * 1e18;
        uint256 fee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsMinted(alice, mintAmount - fee, fee);

        console.log("Fee on the 50_000 EUROS", fee);
        vault.borrow(address(alice), mintAmount);

        // Step 4: Get new status of the vault
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        assertEq(newStatus.borrowedAmount, mintAmount);

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
        assertEq(newStatus.maxBorrowableEuros, initialMaxMintableEuro);
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
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 initialMaxMintableEuro = initialStatus.maxBorrowableEuros;
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

        vault.borrow(alice, mintAmount1);
        vault.borrow(alice, mintAmount2);
        vault.borrow(alice, mintAmount3);

        // Step 4: Get new status of the vault
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        assertEq(newStatus.borrowedAmount, totalMinted);
        assertEq(EUROs.balanceOf(alice), totalMinted - totalFee);
        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            totalFee
        );
        assertEq(newStatus.maxBorrowableEuros, initialMaxMintableEuro);
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
        vault.borrow(alice, mintAmount);
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

        vault.repay(burnAmount);

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
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        assertEq(
            newStatus.borrowedAmount,
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
        vault.borrow(alice, mintAmount);
        vm.stopPrank();

        uint256 mintFee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        uint256 burnAmount = mintAmount - mintFee;
        console.log("Alice balance after mint", EUROs.balanceOf(alice));

        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        console.log("Minted After borrowing", initialStatus.borrowedAmount); // includes fees

        // Step 3: Burn the exact amount of minted EUROs
        uint256 burnFee = (burnAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(alice);
        EUROs.approve(address(vault), burnAmount);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(burnAmount - burnFee, burnFee);

        vault.repay(burnAmount);

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
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();

        console.log("newStatus", newStatus.borrowedAmount / 1e18);

        assertEq(
            newStatus.borrowedAmount,
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

        vault.borrow(alice, mintAmount);

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

        vault.repay(burnAmount);

        // Step 4: Mint more EUROs
        uint256 additionalMintAmount = 3000 * 1e18;
        uint256 additionalMintFee = (additionalMintAmount *
            proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vault.borrow(alice, additionalMintAmount);

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
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        uint256 expectedMinted = mintAmount - burnAmount + additionalMintAmount;
        assertEq(
            newStatus.borrowedAmount,
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
        vault.borrow(alice, mintAmount);
        vm.stopPrank();

        // Step 3: Burn some EUROs
        uint256 burnAmount = 10000 * 1e18;
        uint256 burnFee = (burnAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(alice);
        EUROs.approve(address(vault), burnAmount);
        vault.repay(burnAmount);
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

    function test_BasicEthToWbtcSwap() public {
        console.log("Testing basic ETH to WBTC swap");

        // Setup
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Add collateral
        vm.startPrank(_owner);
        (bool sent, ) = address(vault).call{value: 1 ether}("");
        require(sent, "Failed to send Ether");

        // Prepare swap parameters
        bytes32 inToken = bytes32("ETH");
        bytes32 outToken = bytes32("WBTC");
        uint256 swapAmount = 0.1 ether;
        uint256 minAmountOut = 0.005 * 1e8; // Expect at least 0.005 WBTC
        uint24 poolFee = 3000; // 0.3% pool fee

        // Execute swap
        vault.swap(inToken, outToken, swapAmount, poolFee, minAmountOut);

        // Verify MockSwapData
        ISwapRouter.MockSwapData memory swapData = swapRouterMockContract
            .receivedSwap();
        assertEq(
            swapData.tokenIn,
            address(proxySmartVaultManager.weth()),
            "Incorrect tokenIn"
        );
        assertEq(swapData.tokenOut, address(WBTC), "Incorrect tokenOut");
        assertEq(swapData.fee, poolFee, "Incorrect pool fee");
        assertEq(swapData.recipient, address(vault), "Incorrect recipient");

        uint256 swapFee = (swapAmount * proxySmartVaultManager.swapFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();
        assertEq(swapData.amountIn, swapAmount - swapFee, "Incorrect amountIn");
        assertGe(
            swapData.amountOutMinimum,
            minAmountOut,
            "Incorrect amountOutMinimum"
        );

        vm.stopPrank();
    }

    function test_BasicWbtcToEthSwap() public {
        console.log("Testing basic WBTC to ETH swap");

        // Setup
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Add WBTC collateral
        vm.startPrank(_owner);

        // Prepare swap parameters
        bytes32 inToken = bytes32("WBTC");
        bytes32 outToken = bytes32("ETH");
        uint256 swapAmount = 0.1 * 1e8; // 0.1 WBTC
        uint256 minAmountOut = 1 ether; // Expect at least 1 ETH
        uint24 poolFee = 3000; // 0.3% pool fee

        // Execute swap
        vault.swap(inToken, outToken, swapAmount, poolFee, minAmountOut);

        // Verify MockSwapData
        ISwapRouter.MockSwapData memory swapData = swapRouterMockContract
            .receivedSwap();
        assertEq(swapData.tokenIn, address(WBTC), "Incorrect tokenIn");
        assertEq(
            swapData.tokenOut,
            address(proxySmartVaultManager.weth()),
            "Incorrect tokenOut"
        );
        assertEq(swapData.fee, poolFee, "Incorrect pool fee");
        assertEq(swapData.recipient, address(vault), "Incorrect recipient");

        uint256 swapFee = (swapAmount * proxySmartVaultManager.swapFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();
        assertEq(swapData.amountIn, swapAmount - swapFee, "Incorrect amountIn");
        assertGe(
            swapData.amountOutMinimum,
            minAmountOut,
            "Incorrect amountOutMinimum"
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
    //     VaultifyStructs.VaultStatus memory vaultStatus = vault.vaultStatus();
    //     uint256 totalCollateralValue = vaultStatus.totalCollateralValue;
    //     uint256 maxMintable = vaultStatus.maxBorrowableEuros;

    //     console.log("Euro Collateral:", totalCollateralValue);
    //     console.log("Max Mintable Euros:", maxMintable);

    //     // Step 3: Mint/borrow 80% of maxMintable
    //     uint256 mintAmount = (maxMintable * 80) / 100;
    //     vm.prank(alice);
    //     vault.borrow(alice, mintAmount);

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
    //     vaultStatus = vault.vaultStatus();
    //     uint256 newTotalCollateralValue = vaultStatus.totalCollateralValue;
    //     uint256 mintedEuros = vaultStatus.borrowedAmount;

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
    //     console.log(
    //         "required Collateral Value:",
    //         requiredCollateralValue / 1e18
    //     );
    //     console.log("Minted Euros:", mintedEuros);
    //     console.log("Swap of more than allowed amount handled correctly");
    // }
}
