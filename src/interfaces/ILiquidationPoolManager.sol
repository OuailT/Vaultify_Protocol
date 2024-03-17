// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./ITokenManager.sol";

interface ILiquidationPoolManager {
    struct Asset {
        ITokenManager.Token token;
        uint256 amount;
    }

    function pool() external view returns (address);
    function distributeFees() external;
    function runLiquidation(uint256 _tokenId) external;
}
