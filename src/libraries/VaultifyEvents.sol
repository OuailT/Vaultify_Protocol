// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

library VaultifyEvents {
    // SmartVaultManager.sol Events
    event VaultDeployed(
        address indexed vaultAddress,
        address indexed owner,
        address indexed vaultTokenType,
        uint256 tokenId
    );

    event VaultLiquidated(address indexed vaultAddress);

    event VaultTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to
    );

    // SmartVault.sol Events
    event CollateralRemoved(
        bytes32 indexed symbol,
        uint256 amount,
        address indexed to
    );

    event AssetRemoved(
        address indexed token,
        uint256 amount,
        address indexed to
    );

    event EUROsMinted(address indexed to, uint256 amount, uint256 fee);

    event EUROsBurned(address indexed from, uint256 amount, uint256 fee);

    event ERC20SwapExecuted(
        uint256 amountIn,
        uint256 swapFee,
        uint256 amountOut
    );

    event NativeSwapExecuted(
        uint256 amountIn,
        uint256 swapFee,
        uint256 amountOut
    );

    event FullRepayment(address indexed from, uint256 fee);

    event NativeCollateralRemoved(
        bytes32 indexed symbol,
        uint256 amount,
        address indexed to
    );

    event ERC20CollateralRemoved(
        bytes32 indexed symbol,
        uint256 amount,
        address indexed to
    );

    event PositionIncreased(
        address indexed staker,
        uint256 createdAt,
        uint256 tstValue,
        uint256 eurosValue
    );

    event PositionDecreased(
        address indexed staker,
        uint256 tstValue,
        uint256 eurosValue
    );

    event EmergencyStateChanged(bool indexed emergencyState);

    event EmergencyWithdrawal(
        address indexed staker,
        uint256 totalEuros,
        uint256 totalTst
    );
}
