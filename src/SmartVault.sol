// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEUROs} from "./interfaces/IEUROs.sol";
import {IPriceCalculator} from "./interfaces/IPriceCalculator.sol";
import {ISmartVault} from "./interfaces/ISmartVault.sol";
import {ISmartVaultManagerV3} from "./interfaces/ISmartVaultManagerV3.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {ITokenManager} from "./interfaces/ITokenManager.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {VaultifyErrors} from "./libraries/VaultifyErrors.sol";
import {VaultifyEvents} from "./libraries/VaultifyEvents.sol";

contract SmartVault is ISmartVault {
    using SafeERC20 for IERC20;

    uint8 private constant VERSION = 2;
    bytes32 private constant VAULT_TYPE = bytes32("Euros");

    // Immutable variables
    bytes32 private immutable NATIVE; ///< Symbol of the native asset.
    address public immutable manager; ///< Address of the SmartVaultManager contract.
    IEUROs public immutable EUROs; ///< EUROs token contract interface.
    IPriceCalculator public immutable calculator; ///< Price calculator contract interface.

    // State variables
    address public owner; ///< Owner of the Smart Vault.
    uint256 private vaultEurosMinted; ///< Amount of EUROs minted in this vault.
    bool private liquidated; ///< Flag indicating if the vault has been liquidated.

    /// @notice Initializes a new Smart Vault.
    /// @dev Sets initial values for the Smart Vault.
    /// @param _native Symbol of the native asset.
    /// @param _manager Address of the SmartVaultManager contract.
    /// @param _owner Address of the owner of this vault.
    /// @param _euros Address of the EUROs token contract.
    /// @param _priceCalculator Address of the Price Calculator contract.
    constructor(
        bytes32 _native,
        address _manager,
        address _onwer,
        address _euros,
        address _priceCalculator
    ) {
        NATIVE = _native;
        owner = _onwer;
        manager = _manager;
        EUROs = IEUROs(_euros);
        calculator = IPriceCalculator(_priceCalculator);
    }

    // The vault owner
    /// @notice Modifier to allow only the owner of the vault to call a function.
    modifier onlyVaultOwner() {
        if (owner != msg.sender)
            revert VaultifyErrors.UnauthorizedCalled(msg.sender);
        _;
    }

    /// @notice Retrieves the Token Manager contract.
    /// @dev Calls the manager contract to get the Token Manager's address.
    /// @return The Token Manager contract.
    function getTokenManager() private view returns (ITokenManager) {
        return ITokenManager(ISmartVaultManagerV3(manager).tokenManager());
    }

    /// @notice Calculates the total collateral value in EUROs within the vault.
    /// @dev Sums up the EURO value of all accepted tokens in the vault.
    /// @return euros Total collateral value in EUROs.
    function euroCollateral() internal view returns (uint256 euro) {
        // Get accepted tokens by the manager
        ITokenManager.Token[] memory acceptedTokens = getTokenManager()
            .getAcceptedTokens();
        for (uint256 i; acceptedTokens.length; i++) {
            ITokenManager.Token memory token = getAcceptedTokens[i];
            euro += calculator.tokenToEuroAvg(
                token,
                getAssetBalance(token.symbol, token.addr)
            );
        }
    }

    function getAssetBalance(
        bytes32 _sybmol,
        address addr
    ) internal view returns (uint256) {
        _sybmol == NATIVE
            ? address(this).balance
            : IERC20(addr).balanceOf(address(this));
    }


    function MaxMintableEuros() internal view returns(uint256) {
        returns 
    }
}
