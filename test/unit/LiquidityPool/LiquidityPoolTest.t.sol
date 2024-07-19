// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {HelperTest} from "../../Helpers/HelperTest.sol";
import {ExpectRevert} from "../../Helpers/ExpectRevert.sol";
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";
import {VaultifyEvents} from "src/libraries/VaultifyEvents.sol";
import {VaultifyErrors} from "src/libraries/VaultifyErrors.sol";
import "forge-std/console.sol";

contract LiquidityPoolTest is HelperTest, ExpectRevert {
    function setUp() public override {
        super.setUp();
        super.setUpHelper();
        address _user_1 = fundUserWallet(1, 100);
        bob = _user_1;

        address _user_2 = fundUserWallet(2, 100);
        alice = _user_2;
    }

    function testIncreasePosition_Success() public {
        console.log("Testing successful increase of position");

        console.log("pool", pool);
        console.log(
            "pool manager address",
            liquidityPoolContract.poolManager()
        );

        uint256 initialTstBalance = TST.balanceOf(bob);
        uint256 initialEurosBalance = EUROs.balanceOf(bob);

        // // Initial Pool Balance in TST and EUROs;
        // uint256 initialPoolTstBalance = TST.balanceOf(pool);
        // uint256 initialPoolEurosBalance = EUROs.balanceOf(pool);

        console.log(initialTstBalance);
        console.log(initialEurosBalance);
        console.log(bob);

        vm.startPrank(bob);

        // Approve tokens
        TST.approve(address(pool), 50 ether);
        EUROs.approve(address(pool), 50 ether);

        // Increase position
        liquidityPoolContract.increasePosition(50 ether, 50 ether);

        vm.stopPrank();

        // Check balances Staker balance
        assertEq(
            TST.balanceOf(bob),
            initialTstBalance - 50 ether,
            "TST balance should decrease by 50 ether"
        );
        assertEq(
            EUROs.balanceOf(bob),
            initialEurosBalance - 50 ether,
            "EUROs balance should decrease by 50 ether"
        );

        // Check the pool balance;
        assertEq(TST.balanceOf(pool), 50 ether);
        assertEq(EUROs.balanceOf(pool), 50 ether);

        // Check position
        (VaultifyStructs.Position memory position, ) = liquidityPoolContract
            .getPosition(bob);
        assertEq(
            position.stakedTstAmount,
            50 ether,
            "Staked TST amount should be 50 ether"
        );
        assertEq(
            position.stakedEurosAmount,
            50 ether,
            "Staked EUROs amount should be 50 ether"
        );

        console.log("Increase position successful");
    }

    function testComprehensiveIncreasePosition() public {
        console.log("Starting comprehensive increasePosition test");

        // Initial state checks
        console.log("Checking initial states");
        assertEq(
            TST.balanceOf(address(pool)),
            0,
            "Initial TST balance of pool should be 0"
        );
        assertEq(
            EUROs.balanceOf(address(pool)),
            0,
            "Initial EUROS balance of pool should be 0"
        );

        // Simulate some liquidated assets in the pool manager
        vm.deal(address(proxyLiquidityPoolManager), 1 ether); // 1ETH
        WBTC.mint(address(proxyLiquidityPoolManager), 1e8); // 1 WBTC
        PAXG.mint(address(proxyLiquidityPoolManager), 1e18); // 1 PAXG

        // Alice increases position
        console.log("Alice increasing position");
        vm.startPrank(alice);
        TST.approve(address(pool), 50 ether);
        EUROs.approve(address(pool), 50 ether);
        liquidityPoolContract.increasePosition(50 ether, 50 ether);
        vm.stopPrank();

        // Check Alice's pending stake
        console.log("Checking Alice's pending stake");
        (
            uint256 alicePendingTst,
            uint256 alicePendingEuros
        ) = liquidityPoolContract.getStakerPendingStakes(alice);
        assertEq(
            alicePendingTst,
            50 ether,
            "Alice's pending TST should be 50 ether"
        );

        console.log("Alice Euros when pending", alicePendingTst);

        assertEq(
            alicePendingEuros,
            50 ether,
            "Alice's pending EUROS should be 50 ether"
        );

        // Check pool balances
        console.log("Checking pool balances after Alice's deposit");
        assertEq(
            TST.balanceOf(address(pool)),
            50 ether,
            "Pool TST balance should be 50 ether"
        );
        assertEq(
            EUROs.balanceOf(address(pool)),
            50 ether,
            "Pool EUROS balance should be 50 ether"
        );

        // Simulate some time passing and fees accumulating
        console.log("Simulating time passage and fee accumulation");
        vm.warp(block.timestamp + 25 hours);
        EUROs.mint(address(proxyLiquidityPoolManager), 1000 ether); // Simulate fees

        // Bob increases position, triggering consolidation, fee distribution, and asset relay
        console.log("Bob increasing position");
        vm.startPrank(bob);
        TST.approve(address(pool), 75 ether);
        EUROs.approve(address(pool), 75 ether);
        liquidityPoolContract.increasePosition(75 ether, 75 ether);
        vm.stopPrank();

        // Check Bob's pending stake
        console.log("Checking Bob's pending stake");
        (uint256 bobPendingTst, uint256 bobPendingEuros) = liquidityPoolContract
            .getStakerPendingStakes(bob);
        assertEq(
            bobPendingTst,
            75 ether,
            "Bob's pending TST should be 75 ether"
        );
        assertEq(
            bobPendingEuros,
            75 ether,
            "Bob's pending EUROS should be 75 ether"
        );

        // Check Alice's position (should be consolidated now)
        console.log("Checking Alice's consolidated position");
        (
            VaultifyStructs.Position memory alicePosition,

        ) = liquidityPoolContract.getPosition(alice);

        assertEq(
            alicePosition.stakedTstAmount,
            50 ether,
            "Alice's staked TST should be 50 ether (consolidated)"
        );

        console.log(
            "after staking and receiving Fees",
            alicePosition.stakedTstAmount
        );

        console.log(
            "alicePosition stakedEurosAmount",
            alicePosition.stakedEurosAmount
        );

        assertTrue(
            alicePosition.stakedEurosAmount > 50 ether,
            "Alice's staked EUROS should be more than 50 ether (consolidated + fees)"
        );

        console.log(
            "Comprehensive increasePosition test completed successfully"
        );
    }
}
