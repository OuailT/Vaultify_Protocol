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

        // Step 2: Transfer ETH to the vault
        vm.startPrank(alice);
        (bool sent, ) = payable(address(vault)).call{value: 10 * 1e18}("");
        require(sent, "Native ETH trx failed");
        vm.stopPrank();

        // Step 3: Execute a swap
        uint256 amountIn = 10 * 1e18; // 10 ETH
        uint256 swapFee = (amountIn * proxySmartVaultManager.swapFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();
        uint256 minAmountOut = 0.1 * 1e8; // Mock value for minimum amount out

        vm.startPrank(alice);
        vault.swap(
            bytes32(abi.encodePacked("ETH")),
            bytes32(abi.encodePacked("WBTC")),
            amountIn,
            swapFee,
            minAmountOut
        );
        vm.stopPrank();

        // Step 4: Verify the balances and state
        // Use mock data to verify swap execution and state variables
        MockSwapData memory swapData = SwapRouterMock(
            smartVaultManager.swapRouter2()
        ).receivedSwap();
        assertEq(
            swapData.tokenIn,
            smartVaultManager.weth(),
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

        assertEq((smartVaultManager.liquidator()).balance, swapFee);

        console.log("Swap executed successfully from ETH to WBTC");
    }
}
