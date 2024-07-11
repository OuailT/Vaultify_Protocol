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
        address _user = fundUserWallet(1, 100);
        bob = _user;
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

        // Check balances
        assertEq(
            TST.balanceOf(bob),
            initialTstBalance - 50 ether,
            "TST balance should decrease by 50"
        );
        assertEq(
            EUROs.balanceOf(bob),
            initialEurosBalance - 50 ether,
            "EUROs balance should decrease by 50"
        );

        // Check position
        (VaultifyStructs.Position memory position, ) = liquidityPoolContract
            .getPosition(bob);
        assertEq(
            position.stakedTstAmount,
            50 ether,
            "Staked TST amount should be 50"
        );
        assertEq(
            position.stakedEurosAmount,
            50 ether,
            "Staked EUROs amount should be 50"
        );

        console.log("Increase position successful");
    }
}
