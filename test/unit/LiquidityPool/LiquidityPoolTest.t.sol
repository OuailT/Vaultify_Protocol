// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {HelperTest} from "../../Helpers/HelperTest.sol";
import {ExpectRevert} from "../../Helpers/ExpectRevert.sol";
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";
import {VaultifyEvents} from "src/libraries/VaultifyEvents.sol";
import {VaultifyErrors} from "src/libraries/VaultifyErrors.sol";
import "forge-std/console.sol";

// NOTE: alicePosition.stakedEurosAmount = 50 EUROS staked + FeesDistribution - CosttoBuyLiquidatedAssets;
// TODO: test every internal function seperatly for more robust test.
// TODO: add the rest of the test here for this comprehensive test

contract LiquidityPoolTest is HelperTest, ExpectRevert {
    function setUp() public override {
        super.setUp();
        super.setUpHelper();
        address _user_1 = fundUserWallet(1, 10000);
        bob = _user_1;

        address _user_2 = fundUserWallet(2, 10000);
        alice = _user_2;

        address _user_3 = fundUserWallet(3, 10000);
        jack = _user_3;
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
        vm.deal(address(proxyLiquidityPoolManager), 2 ether); // 2ETH
        WBTC.mint(address(proxyLiquidityPoolManager), 2e8); // 1 WBTC
        PAXG.mint(address(proxyLiquidityPoolManager), 2e18); // 1 PAXG

        // Alice increases position
        console.log("Alice increasing position");
        vm.startPrank(alice);
        TST.approve(address(pool), 9800 ether);
        EUROs.approve(address(pool), 9800 ether);
        liquidityPoolContract.increasePosition(9800 ether, 9800 ether);
        vm.stopPrank();

        // Check Alice's pending stake
        console.log("Checking Alice's pending stake");
        (
            uint256 alicePendingTst,
            uint256 alicePendingEuros
        ) = liquidityPoolContract.getStakerPendingStakes(alice);
        assertEq(
            alicePendingTst,
            9800 ether,
            "Alice's pending TST should be 9800 ether"
        );

        assertEq(
            alicePendingEuros,
            9800 ether,
            "Alice's pending EUROS should be 9800 ether"
        );

        // Check pool balances
        console.log("Checking pool balances after Alice's deposit");
        assertEq(
            TST.balanceOf(address(pool)),
            9800 ether,
            "Pool TST balance should be 9800 ether"
        );
        assertEq(
            EUROs.balanceOf(address(pool)),
            9800 ether,
            "Pool EUROS balance should be 9800 ether"
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
            9800 ether,
            "Alice's staked TST should be 9800 ether (consolidated)"
        );

        console.log(
            "alicePosition stakedEurosAmount",
            alicePosition.stakedEurosAmount
        );

        assertTrue(
            alicePosition.stakedEurosAmount < 9800 ether,
            "Alice's staked Euros amount should be less than 9800 ether due to liquidated asset purchase"
        );

        // Check protocol treasury balance
        uint256 treasuryBalance = EUROs.balanceOf(protocolTreasury);
        assertTrue(
            treasuryBalance > 0,
            "Treasury should have received some fees"
        );

        //*** Scenario: Test when the staker deposits 9800 EUROs ***//
        // Minimum expected rewards for each asset for a 9800 EUROs deposit
        // NOTE: The below minimum rewards are calculated using "distributeLiquidatedAssets"
        uint256 minEthReward = 2 ether; // 2 ETH
        uint256 minWbtcReward = 19000000; // 19000000 / 10^8 = 0.19 WBTC
        uint256 minPaxgReward = 0; // 0 PAXG

        uint256 aliceBalinETHbefore = alice.balance;
        uint256 aliceBalInWBTCbefore = WBTC.balanceOf(address(alice));
        uint256 aliceBalInPAXGbefore = PAXG.balanceOf(address(alice));

        /**Check rewards for Alice and Bob */
        console.log("Checking rewards for Alice");
        VaultifyStructs.Reward[] memory aliceRewards = liquidityPoolContract
            .getStakerRewards(alice);

        for (uint256 i = 0; i < aliceRewards.length; i++) {
            bytes32 assetSymbol = aliceRewards[i].tokenSymbol;
            uint256 rewardAmount = aliceRewards[i].rewardAmount;

            if (assetSymbol == bytes32("ETH")) {
                assertTrue(
                    rewardAmount >= minEthReward,
                    "Alice's ETH reward should be at least 2 ETH"
                );
            } else if (assetSymbol == bytes32("WBTC")) {
                assertTrue(
                    rewardAmount >= minWbtcReward,
                    "Alice's WBTC reward should be at least 2 WBTC"
                );
            } else if (assetSymbol == bytes32("PAXG")) {
                assertTrue(
                    rewardAmount >= minPaxgReward,
                    "Alice's PAXG reward should be 0"
                );
            } else {
                revert("Unkown asset symbol");
            }

            console.log(
                string.concat(
                    "Alice's ",
                    string(abi.encodePacked(aliceRewards[i].tokenSymbol))
                ),
                "Rewards: ",
                vm.toString(aliceRewards[i].rewardAmount)
            );

            // Alice claims rewards
            vm.startPrank(alice);
            liquidityPoolContract.claimRewards();
            vm.stopPrank();

            uint256 aliceEthBalanceAfter = alice.balance;
            uint256 aliceWbtcBalanceAfter = WBTC.balanceOf(address(alice));
            uint256 alicePaxgBalanceAfter = PAXG.balanceOf(address(alice));

            // For ETH balance
            assertGe(
                aliceEthBalanceAfter,
                aliceBalinETHbefore + minEthReward,
                "Alice's ETH balance should increase by the rewarded amount"
            );

            // For WBTC balance
            assertGe(
                aliceWbtcBalanceAfter,
                aliceBalInWBTCbefore + minWbtcReward,
                "Alice's WBTC balance should increase by the rewarded amount"
            );

            // For PAXG balance (assuming no PAXG rewards expected)
            assertEq(
                alicePaxgBalanceAfter,
                aliceBalInPAXGbefore,
                "Alice's PAXG balance should remain unchanged"
            );
        }

        // Simulate some time passing and fees accumulating
        console.log("Simulating time passage and fee accumulation");
        vm.warp(block.timestamp + 25 hours);
        EUROs.mint(address(proxyLiquidityPoolManager), 2000 ether); // Simulate fees

        /**Jack increases position, triggering consolidation, fee distribution, 
        and asset relay for Alice and Bob */
        {
            vm.startPrank(jack);
            TST.approve(address(pool), 5000 ether);
            EUROs.approve(address(pool), 5000 ether);
            liquidityPoolContract.increasePosition(5000 ether, 5000 ether);
            vm.stopPrank();

            // Check Bob's position (should be consolidated now)
            console.log("Checking Jack's consolidated position");
            (
                VaultifyStructs.Position memory bobPosition,

            ) = liquidityPoolContract.getPosition(bob);

            assertEq(
                bobPosition.stakedTstAmount,
                75 ether,
                "Bob's staked TST should be 75 ether (consolidated)"
            );

            assertTrue(
                bobPosition.stakedEurosAmount < 75 ether,
                "Bob's staked Euros amount should be less than 9800 ether due to liquidated asset purchase"
            );
        }

        /** Check rewards for Bob*/
        uint256 bobBalInWBTCbefore = WBTC.balanceOf(address(bob));

        console.log("Checking rewards for Bob");
        VaultifyStructs.Reward[] memory bobRewards = liquidityPoolContract
            .getStakerRewards(bob);

        for (uint256 i = 0; i < bobRewards.length; i++) {
            console.log(
                string.concat(
                    "Bob's ",
                    string(abi.encodePacked(bobRewards[i].tokenSymbol))
                ),
                "Rewards: ",
                vm.toString(bobRewards[i].rewardAmount)
            );

            // NOTE: The bellow min rewards are calculated using "distributeLiquatedAssets"
            // Bob only could only purchased liquidated WBTC
            uint256 minWbtcReward = 244241; // 244241 / 1e8 = 0.00244241 WBTC

            // Bob claims rewards
            vm.startPrank(bob);
            liquidityPoolContract.claimRewards();
            vm.stopPrank();

            uint256 bobWbtcBalanceAfter = WBTC.balanceOf(address(bob));

            // For WBTC balance
            assertGe(
                bobWbtcBalanceAfter,
                bobBalInWBTCbefore + minWbtcReward,
                "Bob's WBTC balance should increase by the rewarded amount"
            );
        }

        // Check protocol treasury balance
        uint256 treasuryBalance = EUROs.balanceOf(protocolTreasury);
        assertTrue(
            treasuryBalance > 0,
            "Treasury should have received some fees"
        );

        console.log(
            "Comprehensive increasePosition test completed successfully"
        );
    }
}
