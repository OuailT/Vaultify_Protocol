// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {OnchainHelperTest} from "../..//Helpers/OnchainHelperTest.sol";
import {ExpectRevert} from "../..//Helpers/ExpectRevert.sol";
import {ISmartVault} from "src/interfaces/ISmartVault.sol";
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";
import {VaultifyEvents} from "src/libraries/VaultifyEvents.sol";
import {VaultifyErrors} from "src/libraries/VaultifyErrors.sol";
import {ISwapRouter} from "src/interfaces/ISwapRouter.sol";
import "forge-std/console.sol";

// Test Smart vault swap functionality using onchain swap on Arbitrum.
contract SmartVaultOnSwapTest is OnchainHelperTest, ExpectRevert {
    function setUp() public override {
        super.setUp();
        super.setUpHelper();

        // Create vault and owner
        (ISmartVault[] memory _vaults, address _owner) = createVaultOwners(1);
        vault = _vaults[0];
        alice = _owner;
    }

    /*********************************************************
     **************************SWAP FUNCTION******************
     *********************************************************/

    function test_onchain_SwapETHtoWBTC() public {
        console.log("Testing swap from ETH to WBTC");

        vm.startPrank(alice);

        uint256 initialETHBalance = address(vault).balance;
        uint256 initialWBTCBalance = WBTC.balanceOf(address(vault));

        console.log("initial ETH Balance pre swap", initialETHBalance);
        console.log("initial WBTC Balance pre swap", initialWBTCBalance);

        // Swap 2 ETH to WBTC
        vault.swap(
            bytes32("ETH"),
            bytes32("WBTC"),
            2 * 1e18,
            3000, // 0.3% fee
            0 // Min amount
        );

        console.log("initial ETH Balance after swap", address(vault).balance);
        console.log(
            "initial WBTC Balance after swap",
            WBTC.balanceOf(address(vault))
        );

        assertLt(
            address(vault).balance,
            initialETHBalance,
            "ETH balance should decrease"
        );
        assertGt(
            WBTC.balanceOf(address(vault)),
            initialWBTCBalance,
            "WBTC balance should increase"
        );

        vm.stopPrank();
        console.log("Swap from ETH to WBTC completed successfully");
    }

    function test_onchain_SwapWBTCtoETH() public {
        console.log("Testing swap from WBTC to ETH");

        vm.startPrank(alice);

        uint256 initialWBTCBalance = WBTC.balanceOf(address(vault));
        uint256 initialETHBalance = address(vault).balance;

        console.log("initial ETH Balance pre swap", initialETHBalance);
        console.log("initial WBTC Balance pre swap", initialWBTCBalance);

        // Swap 0.1 WBTC to ETH
        vault.swap(
            bytes32("WBTC"),
            bytes32("ETH"),
            0.1 * 1e8,
            3000, // 0.3% fee
            0 // Min amount out (use actual value in production)
        );

        uint256 afterSwapWBTCBalance = WBTC.balanceOf(address(vault));
        uint256 afterSwapETHBalance = address(vault).balance;

        console.log("afterSwap ETH Balance pre swap", afterSwapETHBalance);
        console.log("afterSwap WBTC Balance pre swap", afterSwapWBTCBalance);

        assertLt(
            WBTC.balanceOf(address(vault)),
            initialWBTCBalance,
            "WBTC balance should decrease"
        );
        assertGt(
            address(vault).balance,
            initialETHBalance,
            "ETH balance should increase"
        );

        vm.stopPrank();
        console.log("Swap from WBTC to ETH completed successfully");
    }

    function test_SwapAfterBorrowingAndRepaying() public {
        console.log("Testing swap after borrowing and repaying EUROs");

        vm.startPrank(alice);

        // Borrow EUROs
        uint256 borrowAmount = 5000 * 1e18;
        vault.borrow(alice, borrowAmount);

        // Repay some EUROs
        uint256 repayAmount = 1000 * 1e18;
        EUROs.approve(address(vault), repayAmount);
        vault.repay(repayAmount);

        uint256 initialETHBalance = address(vault).balance;
        uint256 initialWBTCBalance = WBTC.balanceOf(address(vault));

        // Swap ETH to WBTC
        vault.swap(bytes32("ETH"), bytes32("WBTC"), 1 * 1e18, 3000, 0);

        assertLt(
            address(vault).balance,
            initialETHBalance,
            "ETH balance should decrease"
        );
        assertGt(
            WBTC.balanceOf(address(vault)),
            initialWBTCBalance,
            "WBTC balance should increase"
        );

        vm.stopPrank();
        console.log("Swap after borrowing and repaying completed successfully");
    }
}
