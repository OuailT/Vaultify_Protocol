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
            uint256 bobMinWbtcReward = 244241; // 244241 / 1e8 = 0.00244241 WBTC

            // Bob claims rewards
            vm.startPrank(bob);
            liquidityPoolContract.claimRewards();
            vm.stopPrank();

            uint256 bobWbtcBalanceAfter = WBTC.balanceOf(address(bob));

            // For WBTC balance
            assertGe(
                bobWbtcBalanceAfter,
                bobBalInWBTCbefore + bobMinWbtcReward,
                "Bob's WBTC balance should increase by the rewarded amount"
            );
        }

        // Check protocol treasury balance
        treasuryBalance = EUROs.balanceOf(protocolTreasury);
        assertTrue(
            treasuryBalance > 0,
            "Treasury should have received some fees"
        );

        console.log(
            "Comprehensive increasePosition test completed successfully"
        );
    }

    function testComprehensiveDecreasePosition() public {
        console.log("Starting comprehensive decreasePosition test");

        // First, run the increasePosition test to set up the initial states
        testComprehensiveIncreasePosition();

        console.log(
            "Initial state set up completed, proceeding with decrease tests"
        );

        // Alice decreases her entire position
        console.log("Alice decreasing position");

        vm.startPrank(alice);

        (
            VaultifyStructs.Position memory alicePositionBefore,

        ) = liquidityPoolContract.getPosition(alice);

        console.log(
            "Alice tst before Full withdraw of TST",
            alicePositionBefore.stakedTstAmount
        );

        // Alic's staked amount before decreasing her position
        uint256 aliceInitialStakedTST = alicePositionBefore.stakedTstAmount;
        uint256 aliceInitialStakedEuros = alicePositionBefore.stakedTstAmount;

        // Alice Balance in TST and EUROS before decreasing her position
        uint256 aliceTstBalanceBefore = TST.balanceOf(alice);
        uint256 aliceEurosBalanceBefore = EUROs.balanceOf(alice);

        console.log("alice TstBalance Before", aliceTstBalanceBefore / 1e18);
        console.log(
            "alice EurosBalance Before",
            aliceEurosBalanceBefore / 1e18
        );

        liquidityPoolContract.decreasePosition(
            alicePositionBefore.stakedTstAmount,
            alicePositionBefore.stakedEurosAmount
        );
        vm.stopPrank();

        // Alice Balance in TST and EUROS after decreasing her position
        uint256 aliceTstBalanceAfter = TST.balanceOf(alice);
        uint256 aliceEurosBalanceAfter = EUROs.balanceOf(alice);

        // Check Alice's TST balance after position decrease
        assertEq(
            aliceInitialStakedTST + aliceTstBalanceBefore,
            aliceTstBalanceAfter,
            "Alice's TST balance incorrect after position decrease"
        );

        // Check Alice's euro balance after position decrease/ assets purchased
        assertEq(
            aliceEurosBalanceBefore,
            aliceEurosBalanceAfter,
            "Alice's euro balance should remain unchanged after position decrease/assets purchase"
        );

        // Check Alice's position after decrease
        console.log("Checking Alice's position after decrease");
        (
            VaultifyStructs.Position memory alicePositionAfter,

        ) = liquidityPoolContract.getPosition(alice);

        console.log(
            "alicePositionAfter stakedTstAmount",
            alicePositionAfter.stakedTstAmount
        );
        assertEq(
            alicePositionAfter.stakedTstAmount,
            0,
            "Alice's staked TST should be 0 after full withdrawal"
        );
        assertEq(
            alicePositionAfter.stakedEurosAmount,
            0,
            "Alice's staked EUROS should be 0 after full withdrawal"
        );

        assertEq(
            alicePositionAfter.stakerAddress,
            address(0),
            "Alice's position should be deleted after a full withdrawl"
        );

        // @audit-info Bob decreases half of his position
        console.log("Bob decreasing half of his position");
        vm.startPrank(bob);
        (
            VaultifyStructs.Position memory bobPositionBefore,

        ) = liquidityPoolContract.getPosition(bob);
        uint256 bobHalfTst = bobPositionBefore.stakedTstAmount / 2;
        uint256 bobHalfEuros = bobPositionBefore.stakedEurosAmount / 2;
        liquidityPoolContract.decreasePosition(bobHalfTst, bobHalfEuros);
        vm.stopPrank();

        console.log("Checking rewards for Bob after decrease");
        VaultifyStructs.Reward[] memory bobRewardsAfter = liquidityPoolContract
            .getStakerRewards(bob);

        for (uint256 i = 0; i < bobRewardsAfter.length; i++) {
            console.log(
                string.concat(
                    "Bob's ",
                    string(abi.encodePacked(bobRewardsAfter[i].tokenSymbol))
                ),
                "Rewards: ",
                vm.toString((bobRewardsAfter[i].rewardAmount / 10) ^ 8)
            );
        }

        // Check Bob's position after decrease
        console.log("Checking Bob's position after decrease");
        (
            VaultifyStructs.Position memory bobPositionAfter,

        ) = liquidityPoolContract.getPosition(bob);

        assertEq(
            bobPositionAfter.stakedTstAmount,
            bobHalfTst,
            "Bob's staked TST should be half of original amount"
        );

        assertLe(
            bobPositionAfter.stakedEurosAmount,
            bobHalfEuros,
            "Bob's staked EUROS should be less than of original amount due to position decrease, assets purched"
        );

        // // Simulate some time passing and fees accumulating
        // console.log("Simulating time passage and fee accumulation");
        // vm.warp(block.timestamp + 25 hours);
        // EUROs.mint(address(proxyLiquidityPoolManager), 1000 ether); // Simulate fees

        // // Jack increases position, triggering consolidation and fee distribution
        // console.log("Jack increasing position");
        // vm.startPrank(jack);
        // TST.approve(address(pool), 1000 ether);
        // EUROs.approve(address(pool), 1000 ether);
        // liquidityPoolContract.increasePosition(1000 ether, 1000 ether);
        // vm.stopPrank();

        // // Check Jack's position
        // console.log("Checking Jack's position");
        // (VaultifyStructs.Position memory jackPosition, ) = liquidityPoolContract
        //     .getPosition(jack);
        // assertEq(
        //     jackPosition.stakedTstAmount,
        //     6000 ether,
        //     "Jack's staked TST should be 6000 ether"
        // );
        // assertTrue(
        //     jackPosition.stakedEurosAmount < 6000 ether,
        //     "Jack's staked EUROS should be less than 6000 ether due to liquidated asset purchase"
        // );

        // // Check rewards for Jack
        // console.log("Checking rewards for Jack");
        // VaultifyStructs.Reward[] memory jackRewards = liquidityPoolContract
        //     .getStakerRewards(jack);
        // for (uint256 i = 0; i < jackRewards.length; i++) {
        //     console.log(
        //         string.concat(
        //             "Jack's ",
        //             string(abi.encodePacked(jackRewards[i].tokenSymbol))
        //         ),
        //         "Rewards: ",
        //         vm.toString(jackRewards[i].rewardAmount)
        //     );

        //     // NOTE: Uncomment and fill in the expected minimum rewards based on your calculations
        //     // uint256 minEthReward = /* Add your calculated value here */;
        //     // uint256 minWbtcReward = /* Add your calculated value here */;
        //     // uint256 minPaxgReward = /* Add your calculated value here */;

        //     // Add assertions for Jack's rewards here
        //     // assertTrue(jackRewards[i].rewardAmount >= minEthReward, "Jack's ETH reward should be at least the minimum");
        //     // assertTrue(jackRewards[i].rewardAmount >= minWbtcReward, "Jack's WBTC reward should be at least the minimum");
        //     // assertTrue(jackRewards[i].rewardAmount >= minPaxgReward, "Jack's PAXG reward should be at least the minimum");
        // }

        // // Jack claims rewards
        // vm.startPrank(jack);
        // uint256 jackEthBalanceBefore = jack.balance;
        // uint256 jackWbtcBalanceBefore = WBTC.balanceOf(address(jack));
        // uint256 jackPaxgBalanceBefore = PAXG.balanceOf(address(jack));

        // liquidityPoolContract.claimRewards();

        // uint256 jackEthBalanceAfter = jack.balance;
        // uint256 jackWbtcBalanceAfter = WBTC.balanceOf(address(jack));
        // uint256 jackPaxgBalanceAfter = PAXG.balanceOf(address(jack));

        // // Assert Jack's balance changes
        // // NOTE: Uncomment and adjust these assertions based on your expected rewards
        // // assertGe(jackEthBalanceAfter, jackEthBalanceBefore + minEthReward, "Jack's ETH balance should increase by the rewarded amount");
        // // assertGe(jackWbtcBalanceAfter, jackWbtcBalanceBefore + minWbtcReward, "Jack's WBTC balance should increase by the rewarded amount");
        // // assertGe(jackPaxgBalanceAfter, jackPaxgBalanceBefore + minPaxgReward, "Jack's PAXG balance should increase by the rewarded amount");

        // vm.stopPrank();

        // // Check protocol treasury balance
        // uint256 treasuryBalance = EUROs.balanceOf(protocolTreasury);
        // assertTrue(
        //     treasuryBalance > 0,
        //     "Treasury should have received some fees"
        // );

        console.log(
            "Comprehensive decreasePosition test completed successfully"
        );
    }
}
