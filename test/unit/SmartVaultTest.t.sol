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

    /////////////////////////////////////////////
    //         Borrow Function unit tests     //
    /////////////////////////////////////////////

    // /**** Test for Maximum Mintable Amount ****/
    function test_MaximumMintableAmount() public {
        console.log("Testing maximum mintable amount");

        // Step 1: Mint a vault and transfer collateral
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();

        uint256 initialMaxMintableEuro = initialStatus.maxBorrowableEuros;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(_owner);

        // Step 3: Mint the maximum allowable euros
        vault.borrow(_owner, initialMaxMintableEuro);

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
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 initialMaxMintableEuro = initialStatus.maxBorrowableEuros;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(_owner);

        // Step 3: Mint a specific amount
        uint256 mintAmount = 55000 * 1e18; // Example mint amount

        vault.borrow(_owner, mintAmount);

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
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 initialMaxMintableEuro = initialStatus.maxBorrowableEuros;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(_owner);

        // Step 3: Mint a specific amount and check fee deduction
        uint256 mintAmount = 50000 * 1e18;
        uint256 fee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsMinted(_owner, mintAmount - fee, fee);

        console.log("Fee on the 50_000 EUROS", fee);
        vault.borrow(address(_owner), mintAmount);

        // Step 4: Get new status of the vault
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        assertEq(newStatus.borrowedAmount, mintAmount);

        console.log(
            "_owner Balance after mint",
            EUROs.balanceOf(address(_owner))
        );

        assertEq(
            EUROs.balanceOf(_owner),
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
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Get initial status of the vault
        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        uint256 initialMaxMintableEuro = initialStatus.maxBorrowableEuros;
        uint256 initialEuroCollateral = initialStatus.totalCollateralValue;

        vm.startPrank(_owner);

        // Step 3: Mint in small increments
        uint256 mintAmount1 = 10000 * 1e18;
        uint256 mintAmount2 = 20000 * 1e18;
        uint256 mintAmount3 = 25000 * 1e18;
        uint256 totalMinted = mintAmount1 + mintAmount2 + mintAmount3;

        // total fees for all the borrowed EUROS
        uint totalFee = (totalMinted * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vault.borrow(_owner, mintAmount1);
        vault.borrow(_owner, mintAmount2);
        vault.borrow(_owner, mintAmount3);

        // Step 4: Get new status of the vault
        VaultifyStructs.VaultStatus memory newStatus = vault.vaultStatus();
        assertEq(newStatus.borrowedAmount, totalMinted);
        assertEq(EUROs.balanceOf(_owner), totalMinted - totalFee);
        assertEq(
            EUROs.balanceOf(proxySmartVaultManager.liquidator()),
            totalFee
        );
        assertEq(newStatus.maxBorrowableEuros, initialMaxMintableEuro);
        assertEq(newStatus.totalCollateralValue, initialEuroCollateral);

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

    function test_revert_borrow_liquidated_Vault() public {
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

        vm.startPrank(address(vault.manager()));
        vault.liquidate();
        vm.stopPrank();

        vm.startPrank(_owner);

        _expectRevertWithCustomError({
            target: address(vault),
            callData: abi.encodeWithSelector(
                vault.borrow.selector,
                _owner,
                50 * 1e18
            ),
            expectedErrorSignature: "LiquidatedVault(address)",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.LiquidatedVault.selector,
                vault
            )
        });

        // _expectRevertWith({
        //     target: address(vault),
        //     callData: abi.encodeWithSelector(
        //         vault.borrow.selector,
        //         _owner,
        //         50 * 1e18
        //     ),
        //     revertMessage: " "
        // });

        vm.stopPrank();
    }

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

    /************Borrow function revert uses cases *********/

    function test_SuccessfulBurn() public {
        console.log("Testing successful burn of EUROs");

        // Step 1: Mint a vault and transfer collateral
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Mint some EUROs to have an initial balance
        uint256 mintAmount = 50000 * 1e18;
        uint256 mintFee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(_owner);
        vault.borrow(_owner, mintAmount);
        vm.stopPrank();

        uint256 _ownerMintedBalance = mintAmount - mintFee;

        // Step 3: Burn some EUROs
        uint256 burnAmount = 10000 * 1e18;
        uint256 burnFee = (burnAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        // Aprrove the vault to spend Euros token on _owner behalf
        vm.startPrank(_owner);
        EUROs.approve(address(vault), burnAmount);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(burnAmount - burnFee, burnFee);

        vault.repay(burnAmount);

        // Step 4: Verify the balances
        assertEq(
            EUROs.balanceOf(_owner),
            ((_ownerMintedBalance) - (burnAmount)),
            " _owner balance after burning is not correct"
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
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        console.log("_owner balance before mint", EUROs.balanceOf(_owner));

        // Step 2: Mint some EUROs to have an initial balance
        uint256 mintAmount = 50000 * 1e18;
        vm.startPrank(_owner);
        vault.borrow(_owner, mintAmount);
        vm.stopPrank();

        uint256 mintFee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        uint256 burnAmount = mintAmount - mintFee;
        console.log("_owner balance after mint", EUROs.balanceOf(_owner));

        VaultifyStructs.VaultStatus memory initialStatus = vault.vaultStatus();
        console.log("Minted After borrowing", initialStatus.borrowedAmount); // includes fees

        // Step 3: Burn the exact amount of minted EUROs
        uint256 burnFee = (burnAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(_owner);
        EUROs.approve(address(vault), burnAmount);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(burnAmount - burnFee, burnFee);

        vault.repay(burnAmount);

        console.log("_owner balance after burn", EUROs.balanceOf(_owner));
        console.log("_owner Minted balnce to burn", burnAmount);

        assertEq(
            EUROs.balanceOf(_owner),
            0,
            "Incorrect _owner balance after burning the "
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
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];

        // Step 2: Mint some EUROs to have an initial balance
        uint256 mintAmount = 20000 * 1e18;
        uint256 mintFee = (mintAmount * proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vm.startPrank(_owner);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsMinted(_owner, mintAmount - mintFee, mintFee);

        vault.borrow(_owner, mintAmount);

        vm.stopPrank();

        uint256 _ownerMintedBalance = mintAmount - mintFee;

        // Step 3: Burn some EUROs
        uint256 burnAmount = 5000 * 1e18;
        uint256 burnFee = (burnAmount * proxySmartVaultManager.burnFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        // Approve the vault to spend Euros token on _owner's behalf
        vm.startPrank(_owner);
        EUROs.approve(address(vault), burnAmount);

        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EUROsBurned(burnAmount - burnFee, burnFee);

        vault.repay(burnAmount);

        // Step 4: Mint more EUROs
        uint256 additionalMintAmount = 3000 * 1e18;
        uint256 additionalMintFee = (additionalMintAmount *
            proxySmartVaultManager.mintFeeRate()) /
            proxySmartVaultManager.HUNDRED_PRC();

        vault.borrow(_owner, additionalMintAmount);

        // _ownerMintedBalance goes to _owner wallet - burnAmount
        //
        // Step 5: Verify the balances
        uint256 expected_ownerBalance = _ownerMintedBalance -
            burnAmount +
            (additionalMintAmount - additionalMintFee);

        console.log("_owner Balance", EUROs.balanceOf(_owner));
        console.log("Execpted_owner balance", expected_ownerBalance);

        assertEq(
            EUROs.balanceOf(_owner),
            expected_ownerBalance,
            "_owner balance after minting again is not correct"
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
        uint256 excessiveRepayAmount = 11 * 1e18;

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
                borrowAmount,
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
                totalRepayment
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

        address nonOwner = address(0x123444);

        vm.startPrank(nonOwner);
        vm.expectRevert(VaultifyErrors.UnauthorizedCaller.selector);
        vault.removeNativeCollateral(1 ether, payable(nonOwner));

        vm.expectRevert(VaultifyErrors.UnauthorizedCaller.selector);
        vault.removeERC20Collateral(bytes32("WBTC"), 0.1 * 1e8, nonOwner);
        vm.stopPrank();
    }

    // PIN
    /////////////////////////////////////////////
    //   Revert test for RemoveNtiveERC20 //
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
    }

    // Stop Here

    /////////////////////////////////////////////
    //         liquidate Function unit tests    //
    /////////////////////////////////////////////

    function test_liquidate_underCollateralized_vault() public {
        console.log("Testing liquidation of an undercollateralized vault");

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
        uint256 amountToBorrow = (maxBorrowableEuros * 95) / 100;

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
