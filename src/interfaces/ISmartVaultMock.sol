// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;
import {ITokenManager} from "src/interfaces/ITokenManager.sol";
import {VaultifyStructs} from "../libraries/VaultifyStructs.sol";
interface ISmartVaultMock {
    function euroCollateral(
        address _vaultAddress
    ) external view returns (uint256 euro);

    function getToken(
        bytes32 _symbol
    ) external view returns (VaultifyStructs.Token memory _token);

    function owner() external view returns (address);

    function vaultStatus(
        address _vaultAddr
    ) external view returns (VaultifyStructs.VaultStatus memory);

    function getAssets(
        address _vaultAddr
    ) external view returns (VaultifyStructs.SmartVaultAssets[] memory);

    function getAssetBalanceMock(
        bytes32 _symbol,
        address _tokenAddress
    ) external view returns (uint256);

    function MaxMintableEuros(
        address _vaultAddr
    ) external view returns (uint256);

    function underCollateralised(
        address _vaultAddr
    ) external view returns (bool);

    function liquidate(address _vaultAddr) external;

    function borrow(address _to, uint256 _amount, address _vaultAddr) external;

    function repay(uint256 _amount) external;

    function swap(
        address _vaultAddr,
        bytes32 _inTokenSymbol,
        bytes32 _outTokenSymbol,
        uint256 _amount
    ) external;

    function setOwner(address _newOwner) external;

    function getTokenManager() external view returns (ITokenManager);
}
