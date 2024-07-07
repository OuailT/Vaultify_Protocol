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

    function test_SwapETHtoWBTC() public {
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
}
