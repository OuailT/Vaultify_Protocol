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

    constructor(
        bytes32 _native,
        address _manager,
        address _onwer,
        address _euros,
        address _priceCalculator
    ) {
        NATIVE = _native;
        owner = _onwer;
        
    }
}
