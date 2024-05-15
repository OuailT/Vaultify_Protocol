// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {VaultifyStructs} from "../libraries/VaultifyStructs.sol";
interface ISmartVault {
    function status() external view returns (VaultifyStructs.Status memory);
    function undercollateralised() external view returns (bool);
    // function setOwner(address _newOwner) external;
    function liquidate() external;
}
