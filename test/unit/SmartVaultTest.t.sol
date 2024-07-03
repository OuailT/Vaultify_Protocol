// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {HelperTest} from "../Helpers/HelperTest.sol";
import {ExpectRevert} from "../Helpers/ExpectRevert.sol";
import {ISmartVault} from "src/interfaces/ISmartVault.sol";
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";
import {VaultifyEvents} from "src/libraries/VaultifyEvents.sol";
import {VaultifyErrors} from "src/libraries/VaultifyErrors.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";
import "forge-std/console.sol";

contract SmartVaultTest is HelperTest, ExpectRevert {
    function setUp() public override {
        super.setUp();
        super.setUpHelper();
    }

    uint256 private constant DUST_THRESHOLD = 1e16;

    /////////////////////////////////////////////
    //         Borrow Function unit tests     //
    /////////////////////////////////////////////

    function test_MaximumBorrowableAmount() public {
        console.log("Testing maximum borrowable amount");

        // Step 1: Mint a vault and transfer collateral
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();

        uint256 initialMaxBorrowableEuro = initialStatus.maxBorrowableEuros;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        uint256 fee = (initialMaxBorrowableEuro *
            proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(_owner);

        // Step 3: Borrow the maximum allowable euros
        vault.borrow(_owner, initialMaxBorrowableEuro);

        // Step 4: Get new status of the vault
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        assertEq(
            newStatus.borrowedAmount,
            initialMaxBorrowableEuro - fee,
            "Borrowed amount should equal the initial max borrowable euros minus fee"
        );
        assertEq(
            newStatus.maxBorrowableEuros,
            initialMaxBorrowableEuro,
            "Max borrowable euros should remain the same"
        );
        assertEq(
            newStatus.totalCollateralValue,
            initialEuroCollateral,
            "Total collateral value should remain the same"
        );

        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            fee,
            "Liquidator's balance should be equal to the fee"
        );

        vm.stopPrank();
    }

    function test_SuccessfulBorrowingWithSufficientCollateral() public {
        console.log("Testing successful minting with sufficient collateral");

        // Step 1: Mint a vault and transfer collateral
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 initialMaxBorrowableEuros = initialStatus.maxBorrowableEuros;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(_owner);

        // Step 3: borrow a specific amount
        uint256 borrowAmount = 55000 * 1e18; // Example borrow amount

        vault.borrow(_owner, borrowAmount);

        uint256 fee = (borrowAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        // Step 4: Get new status of the vault
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();

        assertEq(
            newStatus.borrowedAmount,
            borrowAmount - fee,
            "Borrowed amount should be equal to the specified borrow amount - fee"
        );
        assertEq(
            newStatus.maxBorrowableEuros,
            initialMaxBorrowableEuros,
            "Max borrowable euros should remain the same"
        );
        assertEq(
            newStatus.totalCollateralValue,
            initialEuroCollateral,
            "Total collateral value should remain the same"
        );
        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            fee,
            "Liquidator's balance should be equal to the fee"
        );

        vm.stopPrank();
    }

    function test_BorrowingWithFeeDeduction() public {
        console.log("Testing borrowing with fee deduction");

        // Step 1: Mint a vault and transfer collateral
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 initialMaxMintableEuro = initialStatus.maxBorrowableEuros;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(_owner);

        // Step 3: Borrow a specific amount and check fee deduction
        uint256 borrowAmount = 50000 * 1e18;

        uint256 fee = (borrowAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsMinted(_owner, borrowAmount - fee, fee);

        vault.borrow(address(_owner), borrowAmount);

        // Step 4: Get new status of the vault
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        assertEq(
            newStatus.borrowedAmount,
            borrowAmount - fee,
            "Borrowed amount should be equal to the specified borrow amount"
        );

        assertEq(
            EUROs.balanceOf(_owner),
            borrowAmount - fee,
            "Fee isn't deducted correctly"
        );

        vm.stopPrank();
    }

    function test_BorrowingMultipleTimes() public {
        console.log("Testing borrowing multiple times");

        // Step 1: Mint a vault and transfer collateral
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 initialMaxBorrowableEuros = initialStatus.maxBorrowableEuros;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(_owner);

        // Step 3: Borrow in small increments
        uint256 borrowAmount1 = 10000 * 1e18;
        uint256 borrowAmount2 = 20000 * 1e18;
        uint256 borrowAmount3 = 25000 * 1e18;
        uint256 totalBorrowed = borrowAmount1 + borrowAmount2 + borrowAmount3;

        // Total fees for all the borrowed EUROS
        uint256 totalFee = (totalBorrowed *
            proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vault.borrow(_owner, borrowAmount1);
        vault.borrow(_owner, borrowAmount2);
        vault.borrow(_owner, borrowAmount3);

        // Step 4: Get new status of the vault
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        assertEq(
            newStatus.borrowedAmount,
            totalBorrowed - totalFee,
            "Borrowed amount should be equal to the total borrowed amount - totalFee"
        );
        assertEq(
            EUROs.balanceOf(_owner),
            totalBorrowed - totalFee,
            "Owner's balance should be total borrowed amount minus total fee"
        );
        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            totalFee,
            "Liquidator's balance should be equal to the total fee"
        );
        assertEq(
            newStatus.maxBorrowableEuros,
            initialMaxBorrowableEuros,
            "Max borrowable euros should be equal to the initial max borrowable euros"
        );
        assertEq(
            newStatus.totalCollateralValue,
            initialEuroCollateral,
            "Total collateral value should be equal to the initial collateral value"
        );

        vm.stopPrank();
    }

    function test_revert_borrow_zeroAmount() public {
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        vm.startPrank(_owner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(vault.borrow.selector, _owner, 0),
            expectedErrorSignature: "ZeroAmountNotAllowed()",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.ZeroAmountNotAllowed.selector
            )
        });
        vm.stopPrank();
    }

    // function test_revert_borrow_liquidated_Vault() public {
    //     (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
    //     vault = _vaults[0];

    //     VaultifyStructs.VaultStatus memory statusBeforeLiquidation = vault
    //         .vaultStatus();

    //     uint256 maxBorrowableEuros = statusBeforeLiquidation.maxBorrowableEuros;

    //     // Borrow 95% of EUROS with the current prices
    //     uint256 amountToBorrow = (maxBorrowableEuros * 99) / 100;

    //     console.log(
    //         "max Borrowable Euros before price drops",
    //         maxBorrowableEuros
    //     );

    //     vm.startPrank(_owner);
    //     vault.borrow(_owner, amountToBorrow);
    //     vm.stopPrank();

    //     // Drop ETH and WBTC prices to put the vault in undercollateralization status
    //     priceFeedNativeUsd.setPrice(1900 * 1e8); // Price drops from $2200 to $1900
    //     priceFeedwBtcUsd.setPrice(40000 * 1e8); // Price drops from $42000 to $40000

    //     VaultifyStructs.VaultStatus memory statusAfterLiquidation = vault
    //         .vaultStatus();

    //     uint256 maxBorrowableEurosAfter = statusAfterLiquidation
    //         .maxBorrowableEuros;

    //     console.log(
    //         "max Borrowable Euros after price drops",
    //         maxBorrowableEurosAfter
    //     );

    //     vm.startPrank(address(vault.manager()));
    //     vault.liquidate();
    //     vm.stopPrank();

    //     vm.startPrank(_owner);

    //     _expectRevertWithCustomError({
    //         target: address(vault),
    //         callData: abi.encodeWithSelector(
    //             vault.borrow.selector,
    //             _owner,
    //             50 * 1e18
    //         ),
    //         expectedErrorSignature: "LiquidatedVault(address)",
    //         errorData: abi.encodeWithSelector(
    //             VaultifyErrors.LiquidatedVault.selector,
    //             vault
    //         )
    //     });

    //     vm.stopPrank();
    // }

    function test_revert_borrow_nonVault_Owner() public {
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        address _nonOwner = address(0x125444);

        vm.startPrank(_nonOwner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.borrow.selector,
                _nonOwner,
                0
            ),
            expectedErrorSignature: "UnauthorizedCaller(address)",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.UnauthorizedCaller.selector,
                _nonOwner
            )
        });
        vm.stopPrank();
    }

    function test_revert_borrow_with_underCollateralized_vault() public {
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        VaultifyStructs.VaultStatus memory statusBeforeLiquidation = vault
            .vaultStatus();
        uint256 maxBorrowableEuros = statusBeforeLiquidation.maxBorrowableEuros;

        // Borrow 95% of EUROS with the current prices
        uint256 amountToBorrow = (maxBorrowableEuros * 95) / 100;

        vm.startPrank(_owner);
        vault.borrow(_owner, amountToBorrow);
        vm.stopPrank();

        vm.startPrank(_owner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.borrow.selector,
                _owner,
                amountToBorrow
            ),
            expectedErrorSignature: "UnderCollateralizedVault(address)",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.UnderCollateralizedVault.selector,
                vault
            )
        });
        vm.stopPrank();
    }

    function test_SuccessfulRepay() public {
        console.log("Testing successful repay of EUROs");

        // Step 1: Create a vault and transfer collateral
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Borrow some EUROs to have an initial balance
        uint256 borrowAmount = 50000 * 1e18;
        uint256 borrowFee = (borrowAmount *
            proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(_owner);
        vault.borrow(_owner, borrowAmount);
        vm.stopPrank();

        uint256 _ownerBorrowedBalance = borrowAmount - borrowFee;

        // Step 3: Repay some EUROs
        uint256 repayAmount = 10000 * 1e18;
        uint256 repayFee = (repayAmount *
            proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        // Approve the vault to spend EUROs token on _owner behalf
        vm.startPrank(_owner);
        EUROs.approve(address(vault), repayAmount);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(repayAmount - repayFee, repayFee);

        vault.repay(repayAmount);

        // Step 4: Verify the balances
        assertEq(
            EUROs.balanceOf(_owner),
            _ownerBorrowedBalance - repayAmount,
            "_owner balance after repaying is not correct"
        );

        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            repayFee + borrowFee,
            "Liquidator balance after repaying is not correct"
        );

        // Step 5: Check if the borrowed state variable was deducted
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        assertEq(
            newStatus.borrowedAmount,
            borrowAmount - borrowFee - (repayAmount - repayFee),
            "Borrowed state variable is not correct"
        );

        vm.stopPrank();
    }

    function test_FullRepayment() public {
        console.log("Testing full repayment of EUROs");

        // Step 1: Create a vault and transfer collateral
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Borrow some EUROs
        uint256 borrowAmount = 50000 * 1e18;
        uint256 borrowFee = (borrowAmount *
            proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(_owner);
        vault.borrow(_owner, borrowAmount);

        uint256 actualBorrowedAmount = borrowAmount - borrowFee;

        // Step 3: Full Repayment
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 fullRepayAmount = actualBorrowedAmount;
        uint256 fullRepayFee = (fullRepayAmount *
            proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        EUROs.approve(address(vault), fullRepayAmount);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(
            fullRepayAmount - fullRepayFee,
            fullRepayFee
        );

        vault.repay(fullRepayAmount);

        // Step 4: Verify the balances after full repayment
        assertEq(
            EUROs.balanceOf(_owner),
            actualBorrowedAmount - fullRepayAmount,
            "_owner balance after full repayment is not correct"
        );

        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            borrowFee + fullRepayFee,
            "Liquidator balance after full repayment is not correct"
        );

        // Step 5: Check if borrowedAmount is zero after full repayment
        VaultifyStructs.VaultStatus memory finalStatus = vault.vaultStatus();
        assertEq(
            finalStatus.borrowedAmount,
            0,
            "Borrowed amount should be zero after full repayment"
        );

        vm.stopPrank();
    }

    function test_RepayAndBorrowAgain() public {
        console.log("Testing repay followed by another borrow");

        // Step 1: Mint a vault and transfer collateral
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Borrow some EUROs to have an initial balance
        uint256 borrowAmount = 20000 * 1e18;
        uint256 mintFee = (borrowAmount *
            proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(_owner);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsMinted(
            _owner,
            borrowAmount - mintFee,
            mintFee
        );

        vault.borrow(_owner, borrowAmount);

        vm.stopPrank();

        uint256 _ownerBorrowedBalance = borrowAmount - mintFee;

        // Step 3: Repay some EUROs
        uint256 repayAmount = 5000 * 1e18;
        uint256 burnFee = (repayAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        // Approve the vault to spend Euros token on _owner's behalf
        vm.startPrank(_owner);
        EUROs.approve(address(vault), repayAmount);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(repayAmount - burnFee, burnFee);

        vault.repay(repayAmount);

        // Step 4: Borrow more EUROs
        uint256 additionalBorrowAmount = 3000 * 1e18;
        uint256 additionalMintFee = (additionalBorrowAmount *
            proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vault.borrow(_owner, additionalBorrowAmount);

        // Step 5: Verify the balances
        uint256 expected_ownerBalance = _ownerBorrowedBalance -
            (repayAmount) +
            (additionalBorrowAmount - additionalMintFee);

        console.log("_owner Balance", EUROs.balanceOf(_owner));
        console.log("Expected _owner balance", expected_ownerBalance);

        assertEq(
            EUROs.balanceOf(_owner),
            expected_ownerBalance,
            "_owner balance after borrowing again is not correct"
        );

        uint256 expectedLiquidatorBalance = mintFee +
            burnFee +
            additionalMintFee;

        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            expectedLiquidatorBalance,
            "Liquidator balance after borrowing again is not correct"
        );

        // Step 6: Check if the borrowed state variable was updated correctly
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        uint256 expectedBorrowed = _ownerBorrowedBalance -
            (repayAmount - burnFee) +
            (additionalBorrowAmount - additionalMintFee);
        assertEq(
            newStatus.borrowedAmount,
            expectedBorrowed,
            "Borrowed state variable is not correct"
        );

        vm.stopPrank();
    }

    ////////////////////////////////////////////
    //        Revert test for Borrow Function //
    /////////////////////////////////////////////

    function test_revert_repay_zeroAmount() public {
        console.log("Testing repay with zero amount");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        vm.startPrank(_owner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(vault.repay.selector, 0),
            expectedErrorSignature: "ZeroAmountNotAllowed()",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.ZeroAmountNotAllowed.selector
            )
        });
        vm.stopPrank();
    }

    function test_revert_repay_notEnoughAllowance() public {
        console.log("Testing repay with not enough allowance");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 borrowAmount = 10 * 1e18;
        uint256 repayAmount = 5 * 1e18;

        vm.startPrank(_owner);
        vault.borrow(_owner, borrowAmount);

        // Not approving EUROs for repayment
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(vault.repay.selector, repayAmount),
            expectedErrorSignature: "NotEnoughAllowance(uint256)",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.NotEnoughAllowance.selector,
                repayAmount
            )
        });
        vm.stopPrank();
    }

    function test_revert_repay_notVaultOwner() public {
        console.log("Testing repay by non-vault owner");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        address nonOwner = address(0x123);
        uint256 repayAmount = 5 * 1e18;

        vm.prank(_owner);
        vault.borrow(_owner, 10 * 1e18);

        vm.prank(nonOwner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(vault.repay.selector, repayAmount),
            expectedErrorSignature: "UnauthorizedCaller(address)",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.UnauthorizedCaller.selector,
                nonOwner
            )
        });
    }

    function test_revert_repay_excessiveAmount() public {
        console.log("Testing repay with excessive amount");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 borrowAmount = 10 * 1e18;
        uint256 excessiveRepayAmount = 12 * 1e18;

        // Calculate the fee and total repayment
        uint256 fee = (borrowAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(_owner);
        vault.borrow(_owner, borrowAmount);

        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.repay.selector,
                excessiveRepayAmount
            ),
            expectedErrorSignature: "ExcessiveRepayAmount(uint256,uint256)",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.ExcessiveRepayAmount.selector,
                borrowAmount - fee,
                excessiveRepayAmount
            )
        });
        vm.stopPrank();
    }

    function test_revert_repay_insufficientBalance() public {
        console.log("Testing repay with insufficient balance");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 borrowAmount = 10 * 1e18;
        uint256 repayAmount = 5 * 1e18;

        vm.startPrank(_owner);
        vault.borrow(_owner, borrowAmount);
        EUROs.approve(address(vault), repayAmount);

        // Transfer to alice to create insufficient balance
        EUROs.transfer(alice, 9 * 1e18);

        // Calculate the fee and total repayment
        uint256 fee = (repayAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();
        uint256 totalRepayment = repayAmount + fee;

        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(vault.repay.selector, repayAmount),
            expectedErrorSignature: "InsufficientBalance(address,uint256,uint256)",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.InsufficientBalance.selector,
                _owner,
                EUROs.balanceOf(_owner),
                repayAmount
            )
        });
        vm.stopPrank();
    }

    function test_repay_event_emission() public {
        console.log("Testing repay event emission");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 borrowAmount = 10 * 1e18;
        uint256 repayAmount = 5 * 1e18;

        vm.startPrank(_owner);
        vault.borrow(_owner, borrowAmount);
        EUROs.approve(address(vault), repayAmount);

        uint256 fee = (repayAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(repayAmount - fee, fee);

        vault.repay(repayAmount);
        vm.stopPrank();
    }

    /*********************************************************
     **************************SWAP FUNCTION******************
     *********************************************************/

    function test_SwapPAXGtoWBTCWithoutMinting() public {
        console.log(
            "Testing swap from PAXG to WBTC without minting/borrwing EUROs"
        );

        // Step 1: Mint a vault and transfer collateral
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Swap PAXG to WBTC
        uint256 swapAmount = 10 * 1e18;
        uint256 swapFee = (swapAmount * proxySmartVaultManager.swapFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();
        uint256 minAmountOut = 9 * 1e8;
        uint24 poolFee = 3000; // 0.3% pool fee

        // Approve vault to spend PAXG tokens on _owner's behalf
        vm.startPrank(_owner);
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
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Mint/Borrow some EUROs to have an initial balance
        uint256 mintAmount = 50000 * 1e18;
        vm.startPrank(_owner);
        vault.borrow(_owner, mintAmount);
        vm.stopPrank();

        // Step 3: Burn some EUROs
        uint256 burnAmount = 10000 * 1e18;
        uint256 burnFee = (burnAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(_owner);
        EUROs.approve(address(vault), burnAmount);
        vault.repay(burnAmount);
        vm.stopPrank();

        // Step 5: Execute a swap
        uint256 amountIn = 10 * 1e18; // 10 PAXG
        uint256 swapFee = (amountIn * proxySmartVaultManager.swapFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();
        uint256 minAmountOut = 8 * 1e8; // Mock value for minimum amount out
        uint24 poolFee = 3000; // 0.3% pool fee

        vm.startPrank(_owner);
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
    //     (_vaults, _owner) = createVaultOwners(1);
    //     vault = _vaults[0];

    //     // Step 2: Get vault status and calculate maxMintable
    //     VaultifyStructs.VaultStatus memory vaultStatus = vault.vaultStatus();
    //     uint256 totalCollateralValue = vaultStatus.totalCollateralValue;
    //     uint256 maxMintable = vaultStatus.maxBorrowableEuros;

    //     console.log("Euro Collateral:", totalCollateralValue);
    //     console.log("Max Mintable Euros:", maxMintable);

    //     // Step 3: Mint/borrow 80% of maxMintable
    //     uint256 mintAmount = (maxMintable * 80) / 100;
    //     vm.prank(_owner);
    //     vault.borrow(_owner, mintAmount);

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

    //     vm.prank(_owner);
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

    function test_RemoveNativeCollateral_Successful() public {
        console.log("Testing successful removal of native collateral");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 initialBalance = address(vault).balance;
        uint256 amountToRemove = 1 ether;
        uint256 initialOwnerBalance = _owner.balance;

        vm.startPrank(_owner);
        vault.removeNativeCollateral(amountToRemove, payable(_owner));
        vm.stopPrank();

        assertEq(
            address(vault).balance,
            initialBalance - amountToRemove,
            "Incorrect vault balance after removal"
        );
        assertEq(
            _owner.balance,
            initialOwnerBalance + amountToRemove,
            "Incorrect owner balance after removal"
        );
    }

    function test_RemoveNativeCollateral_ExceedingAvailable() public {
        console.log(
            "Testing removal of native collateral exceeding available amount"
        );

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 excessAmount = address(vault).balance + 1 ether;

        vm.startPrank(_owner);
        vm.expectRevert(VaultifyErrors.NotEnoughEthBalance.selector);
        vault.removeNativeCollateral(excessAmount, payable(_owner));
        vm.stopPrank();
    }

    function test_RemoveNativeCollateral_AfterBorrowing() public {
        console.log("Testing removal of native collateral after borrowing");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 borrowAmount = 50 * 1e18;
        uint256 removeAmount = 1 ether;

        uint256 initialBalance = address(vault).balance;
        uint256 initialOwnerBalance = _owner.balance;

        vm.startPrank(_owner);
        vault.borrow(_owner, borrowAmount);

        VaultifyStructs.VaultStatus memory statusBeforeRemoval = vault
            .vaultStatus();

        vault.removeNativeCollateral(removeAmount, payable(_owner));

        VaultifyStructs.VaultStatus memory statusAfterRemoval = vault
            .vaultStatus();

        assertLt(
            statusAfterRemoval.totalCollateralValue,
            statusBeforeRemoval.totalCollateralValue,
            "Collateral value should decrease"
        );

        assertEq(
            address(vault).balance,
            initialBalance - removeAmount,
            "Incorrect vault balance after removal"
        );
        assertEq(
            _owner.balance,
            initialOwnerBalance + removeAmount,
            "Incorrect owner balance after removal"
        );

        vm.stopPrank();
    }

    function test_RemoveERC20Collateral_Successful() public {
        console.log("Testing successful removal of ERC20 collateral");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 initialBalance = WBTC.balanceOf(address(vault));
        uint256 initalOwnerBalance = WBTC.balanceOf(address(_owner));
        uint256 amountToRemove = 0.5 * 1e8; // 0.5 WBTC

        vm.startPrank(_owner);
        vault.removeERC20Collateral(bytes32("WBTC"), amountToRemove, _owner);
        vm.stopPrank();

        assertEq(
            WBTC.balanceOf(address(vault)),
            initialBalance - amountToRemove,
            "Incorrect vault WBTC balance after removal"
        );
        assertEq(
            WBTC.balanceOf(_owner),
            amountToRemove + initalOwnerBalance,
            "Incorrect owner WBTC balance after removal"
        );
    }

    function test_RemoveERC20Collateral_ExceedingAvailable() public {
        console.log(
            "Testing removal of ERC20 collateral exceeding available amount"
        );

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 excessAmount = WBTC.balanceOf(address(vault)) + 1;

        vm.startPrank(_owner);
        vm.expectRevert(VaultifyErrors.NotEnoughTokenBalance.selector);
        vault.removeERC20Collateral(bytes32("WBTC"), excessAmount, _owner);
        vm.stopPrank();
    }

    function test_RemoveERC20Collateral_AfterBorrowing() public {
        console.log("Testing removal of ERC20 collateral after borrowing");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 borrowAmount = 50 * 1e18;
        uint256 removeAmount = 0.5 * 1e8; // 0.5 WBTC

        vm.startPrank(_owner);
        vault.borrow(_owner, borrowAmount);

        VaultifyStructs.VaultStatus memory statusBeforeRemoval = vault
            .vaultStatus();

        vault.removeERC20Collateral(bytes32("WBTC"), removeAmount, _owner);

        VaultifyStructs.VaultStatus memory statusAfterRemoval = vault
            .vaultStatus();

        assertLt(
            statusAfterRemoval.totalCollateralValue,
            statusBeforeRemoval.totalCollateralValue,
            "Collateral value should decrease"
        );

        vm.stopPrank();
    }

    function test_RemoveCollateral_NonOwner() public {
        console.log("Testing removal of collateral by non-owner");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        address _nonOwner = address(0x123444);

        vm.startPrank(_nonOwner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.removeNativeCollateral.selector,
                1 ether,
                payable(_nonOwner)
            ),
            expectedErrorSignature: "UnauthorizedCaller(address)",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.UnauthorizedCaller.selector,
                _nonOwner
            )
        });
        vm.stopPrank();

        vm.startPrank(_nonOwner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.removeERC20Collateral.selector,
                bytes32("WBTC"),
                0.1 * 1e8,
                _nonOwner
            ),
            expectedErrorSignature: "UnauthorizedCaller(address)",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.UnauthorizedCaller.selector,
                _nonOwner
            )
        });
        vm.stopPrank();
    }

    /////////////////////////////////////////////
    //   Revert test for Remove Native  //
    /////////////////////////////////////////////
    function test_revert_removeNativeCollateral_NativeRemovalNotAllowed()
        public
    {
        console.log(
            "Testing revert of removeNativeCollateral when removal is not allowed"
        );

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 maxBorrowableEuros = initialStatus.maxBorrowableEuros;

        // Borrow 95% of max borrowable
        uint256 amountToBorrow = (maxBorrowableEuros * 95) / 100;

        // total collateral hold in the vault is 76,107EUROS were ETH represent aprox 26%.
        // let remove the total amount of ETH after borrowing 95 percent of the total collateral
        uint256 removeAmount = address(vault).balance;

        vm.startPrank(_owner);
        vault.borrow(_owner, amountToBorrow);

        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.removeNativeCollateral.selector,
                removeAmount,
                payable(_owner)
            ),
            expectedErrorSignature: "NativeRemovalNotAllowed()",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.NativeRemovalNotAllowed.selector
            )
        });
        vm.stopPrank();
    }

    function test_revert_removeNativeCollateral_NotEnoughEthBalance() public {
        console.log(
            "Testing revert of removeNativeCollateral when not enough ETH balance"
        );

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 excessiveAmount = address(this).balance + 1 ether;

        vm.prank(_owner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.removeNativeCollateral.selector,
                excessiveAmount,
                payable(_owner)
            ),
            expectedErrorSignature: "NotEnoughEthBalance()",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.NotEnoughEthBalance.selector
            )
        });
        vm.stopPrank();
    }

    function test_revert_removeNativeCollateral_ZeroValue() public {
        console.log("Testing revert of removeNativeCollateral with zero value");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        vm.prank(_owner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.removeNativeCollateral.selector,
                0,
                payable(_owner)
            ),
            expectedErrorSignature: "ZeroValue()",
            errorData: abi.encodeWithSelector(VaultifyErrors.ZeroValue.selector)
        });
        vm.stopPrank();
    }

    /////////////////////////////////////////////
    //   Revert test for RemoveNtiveERC20 //
    /////////////////////////////////////////////
    function test_revert_removeERC20Collateral_TokenRemovalNotAllowed() public {
        console.log(
            "Testing revert of removeERC20Collateral when removal is not allowed"
        );

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 maxBorrowableEuros = initialStatus.maxBorrowableEuros;

        // Borrow 95% of max borrowable
        uint256 amountToBorrow = (maxBorrowableEuros * 95) / 100;

        vm.startPrank(_owner);
        vault.borrow(_owner, amountToBorrow);

        /// Try to remove 100% of WBTC after borrowing 95% of the collateral.
        uint256 removeAmount = WBTC.balanceOf(address(vault)); //

        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.removeERC20Collateral.selector,
                bytes32("WBTC"),
                removeAmount,
                _owner
            ),
            expectedErrorSignature: "TokenRemovalNotAllowed()",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.TokenRemovalNotAllowed.selector
            )
        });
        vm.stopPrank();
    }

    function test_revert_removeERC20Collateral_ZeroValue() public {
        console.log("Testing revert of removeERC20Collateral with zero value");

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        vm.prank(_owner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.removeERC20Collateral.selector,
                bytes32("WBTC"),
                0,
                _owner
            ),
            expectedErrorSignature: "ZeroValue()",
            errorData: abi.encodeWithSelector(VaultifyErrors.ZeroValue.selector)
        });
    }

    function test_revert_removeERC20Collateral_ZeroAddress() public {
        console.log(
            "Testing revert of removeERC20Collateral with zero address"
        );

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        vm.prank(_owner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.removeERC20Collateral.selector,
                bytes32("WBTC"),
                0.1 * 1e8,
                address(0)
            ),
            expectedErrorSignature: "ZeroAddress()",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.ZeroAddress.selector
            )
        });
    }

    function test_revert_removeERC20Collateral_NotEnoughTokenBalance() public {
        console.log(
            "Testing revert of removeERC20Collateral when not enough token balance"
        );

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        uint256 excessiveAmount = WBTC.balanceOf(address(vault)) + 1;

        vm.prank(_owner);
        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.removeERC20Collateral.selector,
                bytes32("WBTC"),
                excessiveAmount,
                _owner
            ),
            expectedErrorSignature: "NotEnoughTokenBalance()",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.NotEnoughTokenBalance.selector
            )
        });
    }

    /////////////////////////////////////////////
    //         liquidate Function unit tests    //
    /////////////////////////////////////////////

    function test_SuccessfulLiquidationOfUndercollateralizedVault() public {
        console.log(
            "Testing successful liquidation of an undercollateralized vault"
        );

        address vaultLiquidator = proxySmartVaultManager.liquidator();

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        VaultifyStructs.VaultStatus memory statusBeforeLiquidation = vault
            .vaultStatus();
        uint256 maxBorrowableEuros = statusBeforeLiquidation.maxBorrowableEuros;

        console.log(
            "Collateral value in EUROS before price drops:",
            statusBeforeLiquidation.totalCollateralValue
        );

        // Borrow 95% of EUROS with the current prices
        uint256 amountToBorrow = (maxBorrowableEuros * 98) / 100;

        vm.startPrank(_owner);
        vault.borrow(_owner, amountToBorrow);
        vm.stopPrank();

        // Drop ETH and WBTC prices to put the vault in undercollateralization status
        priceFeedNativeUsd.setPrice(1900 * 1e8); // Price drops from $2200 to $1900
        priceFeedwBtcUsd.setPrice(40000 * 1e8); // Price drops from $42000 to $40000

        // Store initial balances of the liquidator
        uint256 initialLiquidatorEthBalance = address(vaultLiquidator).balance;
        uint256 initialLiquidatorWbtcBalance = WBTC.balanceOf(
            address(vaultLiquidator)
        );
        uint256 initialLiquidatorPaxgBalance = PAXG.balanceOf(
            address(vaultLiquidator)
        );

        // liquidate the vault
        vm.startPrank(vault.manager());
        vault.liquidate();
        vm.stopPrank();

        VaultifyStructs.VaultStatus memory statusAfterLiquidation = vault
            .vaultStatus();

        // Assertions

        assertTrue(
            statusAfterLiquidation.isLiquidated,
            "Vault should be marked as liquidated"
        );
        assertEq(
            statusAfterLiquidation.borrowedAmount,
            0,
            "Borrowed amount should be zero after liquidation"
        );

        assertEq(
            statusAfterLiquidation.totalCollateralValue,
            0,
            "Total collateral value should be zero after liquidation"
        );

        // Check if liquidator received the funds
        assertGt(
            address(vaultLiquidator).balance,
            initialLiquidatorEthBalance,
            "Liquidator should have received ETH"
        );
        assertGt(
            WBTC.balanceOf(address(vaultLiquidator)),
            initialLiquidatorWbtcBalance,
            "Liquidator should have received WBTC"
        );
        assertGt(
            PAXG.balanceOf(address(vaultLiquidator)),
            initialLiquidatorPaxgBalance,
            "Liquidator should have received PAXG"
        );

        // // Check if the vault is empty
        assertEq(address(vault).balance, 0, "Vault should have no ETH balance");
        assertEq(
            WBTC.balanceOf(address(vault)),
            0,
            "Vault should have no WBTC balance"
        );
        assertEq(
            PAXG.balanceOf(address(vault)),
            0,
            "Vault should have no PAXG balance"
        );

        console.log("Vault successfully liquidated and emptied");
    }

    function test_revert_nonVaultManager() public {
        console.log(
            "Testing liquidation of an undercollateralized vault with unauthorized caller"
        );

        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        VaultifyStructs.VaultStatus memory statusBeforeLiquidation = vault
            .vaultStatus();
        uint256 maxBorrowableEuros = statusBeforeLiquidation.maxBorrowableEuros;

        // Borrow 95% of EUROS with the current prices
        uint256 amountToBorrow = (maxBorrowableEuros * 95) / 100;

        vm.startPrank(_owner);
        vault.borrow(_owner, amountToBorrow);
        vm.stopPrank();

        // Drop ETH and WBTC prices to put the vault in undercollateralization status
        priceFeedNativeUsd.setPrice(1900 * 1e8); // Price drops from $2200 to $1900
        priceFeedwBtcUsd.setPrice(40000 * 1e8); // Price drops from $42000 to $40000

        address nonManager = address(0x666);

        vm.startPrank(nonManager);

        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(vault.liquidate.selector),
            expectedErrorSignature: "UnauthorizedCaller(address)",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.UnauthorizedCaller.selector,
                nonManager
            )
        });
        vm.stopPrank();
    }
}
