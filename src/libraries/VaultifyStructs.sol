// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

library VaultifyStructs {
    /// @notice Represents a user's position in the liquidation pool
    struct Position {
        /// @notice The Ethereum address of the staker
        address stakerAddress;
        /// @notice The amount of TST tokens staked
        uint256 stakedTstAmount;
        /// @notice The amount of EUROs tokens staked
        uint256 stakedEurosAmount;
    }

    /// @notice Represents a pending stake that hasn't been added to the main position yet
    struct PendingStake {
        /// @notice The Ethereum address of the staker
        address stakerAddress;
        /// @notice The Unix timestamp when this pending stake was created
        uint256 createdAt;
        /// @notice The amount of TST tokens in this pending stake
        uint256 pendingTstAmount;
        /// @notice The amount of EUROs tokens in this pending stake
        uint256 pendingEurosAmount;
    }

    /// @notice Represents rewards earned by a user in the liquidation pool
    struct Reward {
        /// @notice The symbol of the reward token (e.g., "ETH", "USDC")
        bytes32 tokenSymbol;
        /// @notice The amount of rewards earned
        uint256 rewardAmount;
        /// @notice The number of decimal places for the reward token
        uint8 tokenDecimals;
    }

    // Tokens
    struct Token {
        bytes32 symbol;
        address addr;
        uint8 dec;
        address clAddr; // oracle address
        uint8 clDec;
    }

    // Liquidated assets held by the liquation Pool Manager when run liquidation.
    struct Asset {
        Token token;
        uint256 amount;
    }

    // Assets held as collateral in the smart vault
    struct SmartVaultAssets {
        VaultifyStructs.Token token;
        uint256 amount;
        uint256 collateralValue;
    }

    // The Status of the smart vault
    struct VaultStatus {
        address vaultAddress;
        uint256 borrowedAmount;
        uint256 maxBorrowableEuros;
        uint256 totalCollateralValue;
        SmartVaultAssets[] collateralAssets;
        bool isLiquidated;
        uint8 version;
        bytes32 vaultType;
    }

    // to store the vault data
    struct SmartVaultData {
        uint256 tokenId;
        uint256 collateralRate;
        uint256 mintFeeRate;
        uint256 burnFeeRate;
        VaultStatus status;
    }
}
