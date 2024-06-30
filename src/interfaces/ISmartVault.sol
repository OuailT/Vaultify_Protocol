// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {VaultifyStructs} from "../libraries/VaultifyStructs.sol";
import {ITokenManager} from "src/interfaces/ITokenManager.sol";
interface ISmartVault {
    function getAssetBalance(
        bytes32 _symbol,
        address addr
    ) external view returns (uint256);
    function vaultStatus()
        external
        view
        returns (VaultifyStructs.VaultStatus memory);
    function underCollateralized() external view returns (bool);
    function setOwner(address _newOwner) external;
    function liquidate() external;
    function borrow(address _to, uint256 _amount) external;
    function repay(uint256 _amount) external;
    function getTokenManager() external view returns (ITokenManager);
    function swap(
        bytes32 _inTokenSybmol,
        bytes32 _outTokenSymbol,
        uint256 _amount,
        uint24 _fee,
        uint256 _minAmountOut
    ) external;

    function removeNativeCollateral(
        uint256 _amount,
        address payable _to
    ) external;
    function removeERC20Collateral(
        bytes32 _symbol,
        uint256 _amount,
        address _to
    ) external;

    function borrowedEuros() external view returns (uint256);

    function manager() external view returns (address);
}
