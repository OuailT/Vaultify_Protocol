// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

library VaultifyEvents {
    //** smartVaultManager.sol Event **//
    event VaultDeployed(
        address indexed vaultAddress,
        address indexed owner,
        address vaultTokenType,
        uint256 tokenId
    );
    event VaultLiquidated(address indexed vaultAddress);
    event VaultTransferred(uint256 indexed tokenId, address from, address to);

    //** smartVault.sol Event **//
    /// @notice Emitted when collateral is removed from the vault.
    event CollateralRemoved(bytes32 symbol, uint256 amount, address to);

    /// @notice Emitted when an asset is removed from the vault.
    event AssetRemoved(address token, uint256 amount, address to);

    /// @notice Emitted when EUROs are minted.
    event EUROsMinted(address to, uint256 amount, uint256 fee);

    /// @notice Emitted when EUROs are burned.
    event EUROsBurned(uint256 amount, uint256 fee);

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

    event NativeCollateralRemoved(
        bytes32 _symbol,
        uint256 _amount,
        address _to
    );

    event ERC20CollateralRemoved(bytes32 _symbol, uint256 _amount, address _to);
}
