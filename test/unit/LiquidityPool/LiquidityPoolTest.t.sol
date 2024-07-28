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

        // Check event emitted: PositionIncreased
        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.PositionIncreased(
            bob,
            block.timestamp,
            75 ether,
            75 ether
        );

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

        // HERE
        console.log("Checking rewards for Bob after decrease");
        /** Check alice balance for Bob before decrease*/
        uint256 bobBalanceInWBTCBef = WBTC.balanceOf(bob);

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

            // NOTE: The bellow min rewards are calculated using "distributeLiquatedAssets
            // check Bob rewrads after decreasing half of his stake.
            uint256 bobMinWbtcReward = 2253; // 2253 / 1e8 = 0.00002253 WTBC

            // Bob claims rewards
            vm.startPrank(bob);
            liquidityPoolContract.claimRewards();
            vm.stopPrank();

            console.log("alice ETh after reward claimin", bob.balance);

            uint256 bobBalanceInWBTCafter = WBTC.balanceOf(bob);

            // For WBTC balance
            assertGe(
                bobBalanceInWBTCafter,
                bobBalanceInWBTCBef + bobMinWbtcReward,
                "Bob's WBTC balance should increase by the rewarded amount"
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
        console.log("Simulating time passage and fee accumulation");
        vm.warp(block.timestamp + 25 hours);
        EUROs.mint(address(proxyLiquidityPoolManager), 1000 ether); // Simulate fees

        // // Jack increases position, triggering consolidation and fee distribution
        console.log("Jack increasing position");
        vm.startPrank(jack);
        TST.approve(address(pool), 1000 ether);
        EUROs.approve(address(pool), 1000 ether);
        liquidityPoolContract.increasePosition(1000 ether, 1000 ether);
        vm.stopPrank();

        // // Check Jack's position
        // console.log("Checking Jack's position");
        (VaultifyStructs.Position memory jackPosition, ) = liquidityPoolContract
            .getPosition(jack);
        assertEq(
            jackPosition.stakedTstAmount,
            6000 ether,
            "Jack's staked TST should be 6000 ether"
        );
        assertTrue(
            jackPosition.stakedEurosAmount < 6000 ether,
            "Jack's staked EUROS should be less than 6000 ether due to liquidated asset purchase"
        );

        // Check rewards for Jack
        console.log("Checking rewards for Jack");
        VaultifyStructs.Reward[] memory jackRewards = liquidityPoolContract
            .getStakerRewards(jack);
        for (uint256 i = 0; i < jackRewards.length; i++) {
            console.log(
                string.concat(
                    "Jack's ",
                    string(abi.encodePacked(jackRewards[i].tokenSymbol))
                ),
                "Rewards: ",
                vm.toString(jackRewards[i].rewardAmount)
            );
        }

        // // Jack claims rewards
        uint256 jackMinWbtcReward = 17833331;

        vm.startPrank(jack);
        uint256 jackWbtcBalanceBefore = WBTC.balanceOf(address(jack));

        liquidityPoolContract.claimRewards();

        uint256 jackWbtcBalanceAfter = WBTC.balanceOf(address(jack));

        // Assert Jack's balance changes
        assertGe(
            jackWbtcBalanceAfter,
            jackWbtcBalanceBefore + jackMinWbtcReward,
            "Jack's WBTC balance should increase by the rewarded amount"
        );

        vm.stopPrank();

        // Check protocol treasury balance
        uint256 treasuryBalance = EUROs.balanceOf(protocolTreasury);
        assertTrue(
            treasuryBalance > 0,
            "Treasury should have received some fees"
        );

        console.log(
            "Comprehensive decreasePosition test completed successfully"
        );
    }

    function testComprehensiveEmergencyWithdraw() public {
        console.log("Starting comprehensive emergencyWithdraw test");

        // First, run the increasePosition test to set up the initial state
        testComprehensiveIncreasePosition();

        console.log(
            "Initial state set up completed, proceeding with emergency withdraw tests"
        );

        // Simulate emergency state
        vm.startPrank(address(proxyLiquidityPoolManager));
        liquidityPoolContract.toggleEmergencyState(true);
        vm.stopPrank();

        // Test Alice's emergency withdraw
        _testEmergencyWithdraw(alice);

        // Test Bob's emergency withdraw
        _testEmergencyWithdraw(bob);

        console.log(
            "Comprehensive emergencyWithdraw test completed successfully"
        );
    }

    function _testEmergencyWithdraw(address user) private {
        console.log("Testing emergency withdraw for user", user);

        // Store initial balances
        uint256 initialEurosBalance = EUROs.balanceOf(user);
        uint256 initialTstBalance = TST.balanceOf(user);

        // Store initial position and pending stakes
        (
            VaultifyStructs.Position memory initialPosition,

        ) = liquidityPoolContract.getPosition(user);

        (
            uint256 initialPendingTst,
            uint256 initialPendingEuros
        ) = liquidityPoolContract.getStakerPendingStakes(user);

        // Perform emergency withdraw
        vm.prank(user);
        liquidityPoolContract.emergencyWithdraw();

        // get user's position after successful withdraw
        (
            VaultifyStructs.Position memory finalPosition,

        ) = liquidityPoolContract.getPosition(user);

        // Check final balances
        uint256 finalEurosBalance = EUROs.balanceOf(user);
        uint256 finalTstBalance = TST.balanceOf(user);

        assertGe(
            initialEurosBalance +
                initialPosition.stakedEurosAmount +
                initialPendingEuros,
            finalEurosBalance,
            "EUROS balance should include staked and pending amounts"
        );

        assertGe(
            initialTstBalance +
                initialPosition.stakedTstAmount +
                initialPendingTst,
            finalTstBalance,
            "TST balance should include staked and pending amounts"
        );

        assertEq(
            finalPosition.stakerAddress,
            address(0),
            "User's position should be removed after successful emergency withdrawal."
        );

        (
            uint256 finalPendingTst,
            uint256 finalPendingEuros
        ) = liquidityPoolContract.getStakerPendingStakes(user);
        assertEq(
            finalPendingTst,
            0,
            "Pending TST should be 0 after emergency withdraw"
        );
        assertEq(
            finalPendingEuros,
            0,
            "Pending EUROS should be 0 after emergency withdraw"
        );
    }

    function testReturnExcessETH() public {
        // Assume returnExcessETH is public for testing
        // Setup initial state
        uint256 initialPoolManagerBalance = 1 ether;
        vm.deal(address(proxyLiquidityPoolManager), initialPoolManagerBalance);

        uint256 totalETHToDistribute = 2 ether;
        uint256 nativePurchased = 1.5 ether;
        uint256 expectedExcess = totalETHToDistribute - nativePurchased;

        // Setup test assets
        VaultifyStructs.Asset[] memory assets = new VaultifyStructs.Asset[](1);
        assets[0] = VaultifyStructs.Asset({
            token: VaultifyStructs.Token({
                symbol: bytes32("ETH"),
                addr: address(0),
                dec: 18,
                clAddr: address(0),
                clDec: 8
            }),
            amount: totalETHToDistribute
        });

        // Fund the contract with ETH for distribution
        vm.deal(address(liquidityPoolContract), totalETHToDistribute);

        // Call returnExcessETH
        vm.prank(address(liquidityPoolContract));

        //NOTE: change visibility of the function to public to test this
        liquidityPoolContract.returnExcessETH(assets, nativePurchased);

        // Check pool manager balance after excess ETH return
        uint256 finalPoolManagerBalance = address(proxyLiquidityPoolManager)
            .balance;

        assertEq(
            finalPoolManagerBalance,
            initialPoolManagerBalance + expectedExcess,
            "Pool manager should receive excess ETH"
        );

        // Check remaining balance in the contract
        uint256 contractBalance = address(liquidityPoolContract).balance;

        assertEq(
            contractBalance,
            nativePurchased,
            "Contract should retain the purchased amount of ETH"
        );

        // Test with no excess ETH
        // Setup test assets
        uint256 totalETHToDistributee = 1.5 ether;
        VaultifyStructs.Asset[] memory ethAsset = new VaultifyStructs.Asset[](
            1
        );
        ethAsset[0] = VaultifyStructs.Asset({
            token: VaultifyStructs.Token({
                symbol: bytes32("ETH"),
                addr: address(0),
                dec: 18,
                clAddr: address(0),
                clDec: 8
            }),
            amount: totalETHToDistributee
        });

        vm.deal(address(liquidityPoolContract), totalETHToDistributee); // 1.5 ETH
        vm.prank(address(liquidityPoolContract));
        liquidityPoolContract.returnExcessETH(ethAsset, nativePurchased);

        // Check that balances remain unchanged when there's no excess
        assertEq(
            address(proxyLiquidityPoolManager).balance,
            finalPoolManagerBalance,
            "Pool manager balance should not change when there's no excess"
        );

        assertEq(
            address(liquidityPoolContract).balance,
            nativePurchased,
            "Contract balance should remain the same when there's no excess"
        );
    }

    function testToggleEmergencyState() public {
        // Initial state check
        assertFalse(
            liquidityPoolContract.isEmergencyActive(),
            "Emergency state should initially be false"
        );

        // Test toggling emergency state to true
        vm.prank(address(proxyLiquidityPoolManager));
        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EmergencyStateChanged(true);
        liquidityPoolContract.toggleEmergencyState(true);

        assertTrue(
            liquidityPoolContract.isEmergencyActive(),
            "Emergency state should be true after toggling"
        );

        // Test toggling emergency state back to false
        vm.prank(address(proxyLiquidityPoolManager));
        vm.expectEmit(true, true, true, true);
        emit VaultifyEvents.EmergencyStateChanged(false);
        liquidityPoolContract.toggleEmergencyState(false);

        assertFalse(
            liquidityPoolContract.isEmergencyActive(),
            "Emergency state should be false after toggling back"
        );

        // Test calling from an unauthorized address
        vm.prank(alice);

        _expectRevertWithCustomError({
            target: address(liquidityPoolContract),
            callData: abi.encodeWithSelector(
                liquidityPoolContract.toggleEmergencyState.selector,
                true
            ),
            expectedErrorSignature: "UnauthorizedCaller(address)",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.UnauthorizedCaller.selector,
                alice
            )
        });

        // Ensure state hasn't changed after unauthorized call
        assertFalse(
            liquidityPoolContract.isEmergencyActive(),
            "Emergency state should remain false after unauthorized call"
        );
    }

    function test_revert_increasePosition() public {
        // Test revert when emergency state is active
        vm.prank(address(proxyLiquidityPoolManager));
        liquidityPoolContract.toggleEmergencyState(true);

        _expectRevertWithCustomError({
            target: address(liquidityPoolContract),
            callData: abi.encodeWithSelector(
                liquidityPoolContract.increasePosition.selector,
                1 ether,
                1 ether
            ),
            expectedErrorSignature: "EmergencyStateIsActive()",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.EmergencyStateIsActive.selector
            )
        });

        // Reset emergency state
        vm.prank(address(proxyLiquidityPoolManager));
        liquidityPoolContract.toggleEmergencyState(false);
        // Stop here
        uint256 MINIMUM_DEPOSIT = 20e18;
        // Test revert when deposit is below minimum requirement
        uint256 belowMinimum = MINIMUM_DEPOSIT - 1;
        _expectRevertWithCustomError({
            target: address(liquidityPoolContract),
            callData: abi.encodeWithSelector(
                liquidityPoolContract.increasePosition.selector,
                belowMinimum,
                belowMinimum
            ),
            expectedErrorSignature: "DepositBelowMinimum()",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.DepositBelowMinimum.selector
            )
        });

        // Test revert when EUROs allowance is not enough
        vm.prank(alice);
        EUROs.approve(address(liquidityPoolContract), 1 ether - 1);
        _expectRevertWithCustomError({
            target: address(liquidityPoolContract),
            callData: abi.encodeWithSelector(
                liquidityPoolContract.increasePosition.selector,
                0,
                1 ether
            ),
            expectedErrorSignature: "NotEnoughEurosAllowance()",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.NotEnoughEurosAllowance.selector
            )
        });

        // Test revert when TST allowance is not enough
        vm.prank(alice);
        TST.approve(address(liquidityPoolContract), 1 ether - 1);
        _expectRevertWithCustomError({
            target: address(liquidityPoolContract),
            callData: abi.encodeWithSelector(
                liquidityPoolContract.increasePosition.selector,
                1 ether,
                0
            ),
            expectedErrorSignature: "NotEnoughTstAllowance()",
            errorData: abi.encodeWithSelector(
                VaultifyErrors.NotEnoughTstAllowance.selector
            )
        });
    }
}
