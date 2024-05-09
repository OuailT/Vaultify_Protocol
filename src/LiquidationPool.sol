// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISmartVaultManager} from "./interfaces/ISmartVaultManager.sol";
import {IEUROs} from "./interfaces/IEUROs.sol";
import {AggregatorV3Interface} from "./interfaces/IChainlinkAggregatorV3.sol";
import {ILiquidationPool} from "./interfaces/ILiquidationPool.sol";
import {ILiquidationPoolManager} from "./interfaces/ILiquidationPoolManager.sol";
import {ITokenManager} from "./interfaces/ITokenManager.sol";
import {VaultifyErrors} from "./libraries/VaultifyErrors.sol";
import {VaultifyEvents} from "./libraries/VaultifyEvents.sol";

abstract contract LiquidationPool is ILiquidationPool {
    using SafeERC20 for IERC20;

    address private immutable TST;
    address private immutable EUROs;
    address private immutable eurUsd;

    // struct
    struct Position {
        address holder;
        uint256 tstTokens;
        uint256 eurosTokens;
    }

    struct PendingStake {
        address holder;
        uint256 createdAt;
        uint256 tstTokens;
        uint256 eurosTokens;
    }

    struct Rewards {
        bytes32 symbol;
        uint256 amount;
        uint8 dec;
    }

    address[] public holders;
    mapping(address => Position) private positions;
    mapping(bytes => uint256) private rewards;

    PendingStake[] private pendingStakes;

    address payable public poolManager;
    address public tokenManager;

    /// @notice Initializes the Liquidation Pool.
    /// @param _TST Address of the TST token contract.
    /// @param _EUROs Address of the EUROs token contract.
    /// @param _eurUsd Address of the EUR/USD price feed contract.
    /// @param _tokenManager Address of the Token Manager contract.
    constructor(
        address _TST,
        address _EUROs,
        address _eurUsd,
        address _tokenManager
    ) {
        TST = _TST;
        EUROs = _EUROs;
        eurUsd = _eurUsd;
        tokenManager = _tokenManager;
        poolManager = payable(msg.sender);
    }

    // TODO Change tokens other tokens names
    function increasePosition(uint256 _tstVal, uint256 _eurosVal) external {
        require(_tstVal > 0 || _eurosVal > 0);

        // Check if the contract has allowance to transfer both tokens
        bool isTstApproved = IERC20(TST).allowance(msg.sender, address(this)) >=
            _tstVal;

        bool isEurosApproved = IERC20(EUROs).allowance(
            msg.sender,
            address(this)
        ) >= _eurosVal;

        if (!isEurosApproved) revert VaultifyErrors.NotEnoughEurosAllowance();
        if (!isTstApproved) revert VaultifyErrors.NotEnoughTstAllowance();

        consolidatePendingStakes(); // [x] TODO
        ILiquidationPoolManager(poolManager).distributeFees(); // [x] TODO

        if (_tstVal > 0) {
            IERC20(TST).safeTransferFrom(msg.sender, address(this), _tstVal);
        }

        if (_eurosVal > 0) {
            IERC20(EUROs).safeTransferFrom(
                msg.sender,
                address(this),
                _eurosVal
            );
        }

        // Push the stake request to pendingStake
        pendingStakes.push(
            PendingStake({
                holder: msg.sender,
                createdAt: block.timestamp,
                tstTokens: _tstVal,
                eurosTokens: _eurosVal
            })
        );

        // Add the staker/holder as unique to avoid duplicate address
        addUniqueHolder(msg.sender); // TODO

        emit VaultifyEvents.PositionIncreased(
            msg.sender,
            block.timestamp,
            _tstVal,
            _eurosVal
        );
    }

    // decrease position function
    function decreasePosition(uint256 _tstVal, uint256 _eurosVal) external {
        // READ from memory
        Position memory _userPosition = positions[msg.sender];
        // Check if the user has enough tst or Euros tokens to remove from it position

        if (
            _userPosition.tstTokens < _tstVal &&
            _userPosition.eurosTokens < _eurosVal
        ) revert VaultifyErrors.InvalidDecrementAmount();

        consolidatePendingStakes();
        // NOTE ILiquidationPoolManager(poolManager).distributeFees(); 

        if (_tstVal > 0) {
            IERC20(TST).safeTransfer(msg.sender, _tstVal);
            unchecked {
                _userPosition.tstTokens -= _tstVal;
            }
        }

        if (_eurosVal > 0) {
            IERC20(EUROs).safeTransfer(msg.sender, _eurosVal);
            unchecked {
                _userPosition.eurosTokens -= _eurosVal;
            }
        }

        // create function to check if the positon is Empty
        if (_userPosition.tstTokens == 0 && _userPosition.eurosTokens == 0) {
            deletePosition(_userPosition.holder);
        }

        emit VaultifyEvents.positionDecreased(msg.sender, _tstVal, _eurosVal);
    }

    function deleteHolder(address _holder) private {
        for (uint256 i = 0; i < holders.length; ) {
            // the element to be deleted is found at index i
            if (holders[i] == _holder) {
                // replace the amount to be deleted with the last element in the array: to save gas
                holders[i] == holders[holders.length - 1];
                holders.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    // delete Positions and holders
    function deletePosition(address _holder) private {
        // delete holder
        deleteHolder(_holder);
        delete positions[_holder];
    }

    // deletePendingStake
    function deletePendingStake(uint256 _i) private {
        for (uint256 i = _i; i < pendingStakes.length - 1; ) {
            pendingStakes[i] = pendingStakes[i + 1];
            unchecked {
                ++i;
            }
        }
        pendingStakes.pop();
    }

    function addUniqueHolder(address _holder) private {
        for (uint256 i = 0; i < holders.length; ) {
            // Check for duplicate
            if (holders[i] == _holder) return;
            unchecked {
                ++i;
            }
        }
        holders.push(_holder);
    }

    // function that allows pending stakes position to be consolidatin as position in the pool
    function consolidatePendingStakes() private {
        // Create a dealine variable to check the validity of the order
        uint256 deadline = block.timestamp - 1 days;

        for (int256 i = 0; uint256(i) < pendingStakes.length; i++) {
            // get the data at the index(i)
            PendingStake memory _stakePending = pendingStakes[uint256(i)];

            // To prevent front-runing attacks to take advantage of rewards
            if (_stakePending.createdAt < deadline) {
                // WRITE to STORAGE
                Position storage position = positions[_stakePending.holder];
                position.holder = _stakePending.holder;
                position.tstTokens += _stakePending.tstTokens;
                position.eurosTokens += _stakePending.eurosTokens;

                // Delete Pending Stakes of the users
                deletePendingStake(uint256(i));
                i--;
            }
        }
    }

    function getMinimumStakeAmount(Position memory _position) private pure returns(uint256) {
        return _position.tstTokens > _position.eurosTokens ? _position.eurosTokens : _position.tstTokens;
    }


    function getTotalStakes() external returns(uint256 _stake) {
        for(uint256 i =0; i < holders.length; i++) {
            Position memory _position = positions[holders[i]];
            _stake += getMinimumStakeAmount(_position);
        }
    }

    function distributeLiquatedAssets(ILiquidationPoolManager.Asset memory _assets,
        uint256 _collateralRate, 
        uint256 _hundredPRC) external payable {

        // Consolidate pending stakes
        consolidatePendingStakes();

        
        // get the price of EURO/USD from chainlink
        (,int256 priceEurUsd,,,)= AggregatorV3Interface(eurUsd).latestRoundData();
        if(priceEurUsd <= 0) revert VaultifyErrors.InvalidPrice();

        // calculates the total staked amount in the pool using the getStakeTotal() function.
        uint256 stakeTotal = getTotalStakes();

        // keep track of the total EUROs to be burned after purchased liquidated asset 
        uint256 burnEuros;

        // Keep track if the native tokens purchased
        uint256 nativePuchased;
        
        // NOTE To do later change forloop to avoid out of gas
        // iterates over each holder in the holders array and retrieves their position
        for(uint256 j = 0; j < holders.length; j++) {
            
            // READ get holder position
            Position memory _position = positions[holders[j]];

            // get holder stake Amount
            uint256 stakedAmount = getMinimumStakeAmount(_position);

            if(stakedAmount > 0) {
                // Iterate throught all the liquidated assets array and buy them automatically 
                for(uint256 i = 0; i < _assets.length; i++) {
                    ILiquidationPoolManager.Asset memory asset = _assets[i];

                    if(asset.amount > 0) {
                        // retrieves the asset's USD price from a Chainlink oracle
                        (, int256 assetPriceUsd, , , ) = AggregatorV3Interface(asset.token.clAddr)
                            .latestRoundData();

                        // Calculate the portion/share of the holder in speicific amount of liquidated token from the vault
                        // based on the avaible amount of liquidated tokens * amountUsersStake / totalStakedAmountInPool;
                        // calculates the holder's portion of the asset based on their stake
                        uint256 _portion = (asset.amount * _stakedAmount) / stakeTotal;

                        // The cost in Euros that the staker will use to automatically purchase
                        // //their share of the liquidated asset.
                        uint256 costInEuros = _portion * 10 ** (18 - asset.token.dec)
                        * uint256(assetPriceUsd) / uint256(priceEurUsd)
                            * _hundredPC / _collateralRate;
                        
                        ///TODO  Ask AI how can I think like or how can I develop this mathematical mindset as DeFi developer.
                        // Ask for resources.
                    }
                    
                }

            }
        }
    }    I
}