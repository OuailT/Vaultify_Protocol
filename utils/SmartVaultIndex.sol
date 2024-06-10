// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ContextUpgradeable.sol";

import {ISmartVaultIndex} from "../src/interfaces/ISmartVaultIndex.sol";

contract SmartVaultIndex is
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    ISmartVaultIndex
{
    address public manager;
    mapping(address => uint256[]) private tokenIds;
    mapping(uint256 => address payable) private vaultAddresses;

    modifier onlyManager() {
        require(_msgSender() == manager, "err-unauthorised");
        _;
    }

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _manager) external initializer {
        __Ownable_init(_msgSender());
        __Context_init();
        manager = _manager;
    }

    function getTokenIds(
        address _user
    ) external view returns (uint256[] memory) {
        return tokenIds[_user];
    }

    function getVaultAddress(
        uint256 _tokenId
    ) external view returns (address payable) {
        return vaultAddresses[_tokenId];
    }

    function addVaultAddress(
        uint256 _tokenId,
        address payable _vault
    ) external onlyManager {
        vaultAddresses[_tokenId] = _vault;
    }

    function removeTokenId(address _user, uint256 _tokenId) private {
        uint256[] memory currentIds = tokenIds[_user];
        uint256 idsLength = currentIds.length;
        delete tokenIds[_user];
        for (uint256 i = 0; i < idsLength; i++) {
            if (currentIds[i] != _tokenId) tokenIds[_user].push(currentIds[i]);
        }
    }

    function transferTokenId(
        address _from,
        address _to,
        uint256 _tokenId
    ) external onlyManager {
        removeTokenId(_from, _tokenId);
        tokenIds[_to].push(_tokenId);
    }

    function setVaultManager(address _manager) external onlyOwner {
        manager = _manager;
    }
}
