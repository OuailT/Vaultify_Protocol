// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {OnchainHelperTest} from "../Helpers/OnchainHelperTest.sol";
import {ExpectRevert} from "../Helpers/ExpectRevert.sol";
import {ISmartVault} from "src/interfaces/ISmartVault.sol";
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";
import {VaultifyEvents} from "src/libraries/VaultifyEvents.sol";
import {VaultifyErrors} from "src/libraries/VaultifyErrors.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";
import "forge-std/console.sol";

// Test Smart vault swap functionality using onchain swap on Arbitrum.
contract SmartVaultSwapTest is OnchainHelperTest, ExpectRevert {
    function setUp() public override {
        super.setUp();
        super.setUpHelper();
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
}
