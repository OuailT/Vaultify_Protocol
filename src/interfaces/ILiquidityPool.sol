// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";

interface ILiquidityPool {
    function consolidatePendingStakes() external;
    function poolManager() external view returns (address payable);
    function increasePosition(uint256 _tstVal, uint256 _eurosVal) external;

    function decreasePosition(uint256 _tstVal, uint256 _eurosVal) external;

    function rewards(bytes memory key) external view returns (uint256);

    function distributeLiquatedAssets(
        VaultifyStructs.Asset[] memory _assets,
        uint256 _collateralRate,
        uint256 _hundredPRC
    ) external payable;

    function claimRewards() external;

    function getTotalTst() external view returns (uint256 _tstTokens);

    function distributeRewardFees(uint256 _amount) external;

    function getStakerPendingStakes(
        address _holder
    ) external view returns (uint256 _pendingTST, uint256 _pendingEUROS);

    function getPosition(
        address _holder
    )
        external
        view
        returns (
            VaultifyStructs.Position memory _position,
            VaultifyStructs.Reward[] memory _rewards
        );

    function getStakerRewards(
        address _staker
    ) external view returns (VaultifyStructs.Reward[] memory);

    function emergencyWithdraw() external;

    function toggleEmergencyState(bool _isEmergencyActive) external;
}
