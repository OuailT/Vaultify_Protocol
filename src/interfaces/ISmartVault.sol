// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {VaultifyStructs} from "../libraries/VaultifyStructs.sol";
interface ISmartVault {
    function status() external view returns (VaultifyStructs.Status memory);
    function underCollateralised() external view returns (bool);
    function setOwner(address _newOwner) external;
    function liquidate() external;
    function borrowMint(uint256 _amount, address _to) external;
    function burnEuros(uint256 _amount) external;
    function swap(
        bytes32 _inTokenSybmol,
        bytes32 _outTokenSymbol,
        uint256 _amount
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
}
