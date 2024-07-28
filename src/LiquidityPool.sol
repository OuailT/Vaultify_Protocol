// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {ISmartVaultManager} from "src/interfaces/ISmartVaultManager.sol";
import {IEUROs} from "src/interfaces/IEUROs.sol";
import {AggregatorV3Interface} from "src/interfaces/IChainlinkAggregatorV3.sol";
import {ILiquidityPool} from "src/interfaces/ILiquidityPool.sol";
import {ILiquidationPoolManager} from "src/interfaces/ILiquidationPoolManager.sol";
import {ITokenManager} from "src/interfaces/ITokenManager.sol";
import {VaultifyErrors} from "src/libraries/VaultifyErrors.sol";
import {VaultifyEvents} from "src/libraries/VaultifyEvents.sol";
import {VaultifyStructs} from "src/libraries/VaultifyStructs.sol";

/// @title Liquidity Pool Contract
/// @notice This contract manages liquidated assets and distributing them to stakestakers
contract LiquidityPool is ILiquidityPool, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address private immutable TST;
    address private immutable EUROs;
    address private immutable euroUsdFeed;

    uint256 public constant MINIMUM_DEPOSIT = 20e18; //

    address[] public stakers;

    // PendingStake[] private pendingStakes;
    address payable public poolManager;
    address public tokenManager;
    bool public isEmergencyActive;

    mapping(address => VaultifyStructs.Position) private positions;
    mapping(bytes => uint256) public rewards;
    mapping(address => VaultifyStructs.PendingStake) private pendingStakes;
    mapping(address => uint256) private stakersIndex;

    /// @notice Initializes the Liquidation Pool
    /// @param _TST Address of the TST token contract
    /// @param _EUROs Address of the EUROs token contract
    /// @param _euroUsdFeed Address of the EUR/USD price feed contract
    /// @param _tokenManager Address of the Token Manager contract
    constructor(
        address _TST,
        address _EUROs,
        address _euroUsdFeed,
        address _tokenManager
    ) {
        TST = _TST;
        EUROs = _EUROs;
        euroUsdFeed = _euroUsdFeed;
        tokenManager = _tokenManager;
        poolManager = payable(msg.sender);
    }

    modifier onlyPoolManager() {
        if (msg.sender != poolManager)
            revert VaultifyErrors.UnauthorizedCaller(msg.sender);
        _;
    }

    /// @dev Ensures the function can only be called during an emergency
    modifier onlyDuringEmergency() {
        if (!isEmergencyActive) revert VaultifyErrors.EmergencyStateNotActive();
        _;
    }

    /// @dev Ensures the function can only be called when not in an emergency state
    modifier onlyWhenNotEmergency() {
        if (isEmergencyActive) revert VaultifyErrors.EmergencyStateIsActive();
        _;
    }

    /// @notice Increases a user's position in the liquidity pool
    /// @dev Allows users to deposit TST and EUROs tokens into the pool
    /// @param _tstVal The amount of TST tokens to deposit
    /// @param _eurosVal The amount of EUROs tokens to deposit
    function increasePosition(
        uint256 _tstVal,
        uint256 _eurosVal
    ) external onlyWhenNotEmergency {
        if (_tstVal < MINIMUM_DEPOSIT || _eurosVal < MINIMUM_DEPOSIT)
            revert VaultifyErrors.DepositBelowMinimum();

        // Check if the contract has allowance to transfer both tokens
        bool isTstApproved = IERC20(TST).allowance(msg.sender, address(this)) >=
            _tstVal;

        bool isEurosApproved = IERC20(EUROs).allowance(
            msg.sender,
            address(this)
        ) >= _eurosVal;

        if (!isEurosApproved) revert VaultifyErrors.NotEnoughEurosAllowance();
        if (!isTstApproved) revert VaultifyErrors.NotEnoughTstAllowance();

        ILiquidationPoolManager(poolManager).allocateFeesAndAssetsToPool();

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

        VaultifyStructs.PendingStake memory stake = pendingStakes[msg.sender];

        VaultifyStructs.PendingStake memory updatePendingStake = VaultifyStructs
            .PendingStake({
                stakerAddress: msg.sender,
                pendingDuration: block.timestamp + 1 days,
                pendingTstAmount: stake.pendingTstAmount + _tstVal,
                pendingEurosAmount: stake.pendingEurosAmount + _eurosVal
            });

        pendingStakes[msg.sender] = updatePendingStake;

        addUniqueStaker(msg.sender);

        emit VaultifyEvents.PositionIncreased(
            msg.sender,
            block.timestamp,
            _tstVal,
            _eurosVal
        );
    }

    /// @notice Decreases a user's position in the liquidity pool
    /// @dev Allows users to withdraw TST and EUROs tokens from the pool
    /// @param _tstVal The amount of TST tokens to withdraw
    /// @param _eurosVal The amount of EUROs tokens to withdraw
    function decreasePosition(
        uint256 _tstVal,
        uint256 _eurosVal
    ) external onlyWhenNotEmergency {
        ILiquidationPoolManager(poolManager).allocateFeesAndAssetsToPool();

        // get the current user position from the storage.
        VaultifyStructs.Position storage currentPosition = positions[
            msg.sender
        ];

        // calculate the maximum amounts that can be withdrawn
        uint256 maxTstWithdrawal = currentPosition.stakedTstAmount;
        uint256 maxEurosWithdrawal = currentPosition.stakedEurosAmount;

        // Adjust withdrawal amounts if they exceed the current stake
        uint256 tstToWithdraw = _tstVal > maxTstWithdrawal
            ? maxTstWithdrawal
            : _tstVal;

        uint256 eurosToWithdraw = _eurosVal > maxEurosWithdrawal
            ? maxEurosWithdrawal
            : _eurosVal;

        // Perform withdrawals
        if (tstToWithdraw > 0) {
            currentPosition.stakedTstAmount -= tstToWithdraw;
            IERC20(TST).safeTransfer(msg.sender, tstToWithdraw);
        }

        if (eurosToWithdraw > 0) {
            currentPosition.stakedEurosAmount -= eurosToWithdraw;
            IERC20(EUROs).safeTransfer(msg.sender, eurosToWithdraw);
        }

        // Check if position should be deleted
        if (
            currentPosition.stakedTstAmount == 0 &&
            currentPosition.stakedEurosAmount == 0
        ) {
            deletePosition(msg.sender);
        }

        emit VaultifyEvents.PositionDecreased(
            msg.sender,
            tstToWithdraw,
            eurosToWithdraw
        );
    }

    // NOTE: change visibility from private to external for testing
    /// @notice Deletes a staker's position from the pool
    /// @dev This function is called when a staker's position becomes empty
    /// @param _staker The address of the staker whose position is to be deleted
    function deletePosition(address _staker) private {
        // delete staker
        deleteStaker(_staker);
        delete positions[_staker];
    }

    /// @notice Adds a new unique staker to the pool
    /// @dev This function ensures that each staker is only added once to the holders array
    /// @param _staker The address of the new staker to be added
    function addUniqueStaker(address _staker) private {
        if (stakersIndex[_staker] == 0) {
            stakers.push(_staker);
            // Store the index of the new staker, which is length of the array - 1(index start at 0)
            stakersIndex[_staker] = stakers.length - 1;
        } else {
            return;
        }
    }

    /// @notice Removes a staker from the pool
    /// @dev This function is called when a staker's position is fully withdrawn
    /// @param _staker The address of the staker to be removed
    function deleteStaker(address _staker) private {
        uint256 index = stakersIndex[_staker];
        if (index != 0 || stakers[0] == _staker) {
            // Replace the staker that we want to delete with the last staker in the array staker
            // @audit this will never be able to target the first staker 0
            stakers[index] = stakers[stakers.length - 1];

            // set the index of the desired removed element to last staker in the array
            stakersIndex[stakers[stakers.length - 1]] = index;

            // Remove the last element
            stakers.pop();

            delete stakersIndex[_staker];
        }
    }

    // @audit-info change visibility from private to public to test it out.
    /// @notice Consolidates pending stakes into active positions
    /// @dev This function is called internally to process pending stakes that are older than 24 hours
    /// @dev It helps prevent front-running attacks and ensures fair reward distribution
    function consolidatePendingStakes() public {
        for (uint256 i = 0; i < stakers.length; i++) {
            address _staker = stakers[i];

            // @audit-info double check this
            // State changing operation
            VaultifyStructs.PendingStake memory _pendingStake = pendingStakes[
                _staker
            ];

            // This ensures that only pending stakes created more than 24 hours ago will be consolidated
            // This is done to reduce MEV opportunities(wait at least 24H to increase position)
            // To prevent front-runing attacks to take advantage of rewards
            if (_pendingStake.pendingDuration < block.timestamp) {
                positions[_staker].stakerAddress = _staker;
                positions[_staker].stakedTstAmount += _pendingStake
                    .pendingTstAmount;
                positions[_staker].stakedEurosAmount += _pendingStake
                    .pendingEurosAmount;
                // Reset the pending stake
                delete pendingStakes[_staker];
            }
        }
    }

    /// @notice Calculates the minimum stake amount for a given position
    /// @dev Returns the smaller of TST or EUROs amounts in the position
    /// @param _position The position to evaluate
    /// @return The minimum stake amount
    function getMinimumStakeAmount(
        VaultifyStructs.Position memory _position
    ) private pure returns (uint256) {
        return
            _position.stakedTstAmount > _position.stakedEurosAmount
                ? _position.stakedEurosAmount
                : _position.stakedTstAmount;
    }

    /// @notice Calculates the total stakes in the pool
    /// @dev Sums up the minimum stake amounts across all positions
    /// @return _stake The total stake amount in the pool
    function getTotalStakes() private view returns (uint256 _stake) {
        for (uint256 i = 0; i < stakers.length; i++) {
            VaultifyStructs.Position memory _position = positions[stakers[i]];
            _stake += getMinimumStakeAmount(_position);
        }
    }

    /// @notice Distributes liquidated assets to pool participants
    /// @dev Called when assets are liquidated, distributes them among stakers
    /// @dev collateralRate who permit a discount. It takes the euros in exchange of the asset for e,g 90,9% of the real asset price
    /// @param _assets Array of liquidated assets to distribute
    /// @param _collateralRate The collateral rate used for calculations
    /// @param _hundredPRC Constant representing 100% (used for percentage calculations)
    function distributeLiquatedAssets(
        VaultifyStructs.Asset[] memory _assets,
        uint256 _collateralRate,
        uint256 _hundredPRC
    ) external payable onlyPoolManager {
        // get the price of EURO/USD from chainlink
        (, int256 priceEurUsd, , , ) = AggregatorV3Interface(euroUsdFeed)
            .latestRoundData();
        if (priceEurUsd <= 0) revert VaultifyErrors.InvalidPrice();

        // calculates the total staked amount in the pool using the getStakeTotal() function.
        uint256 stakeTotal = getTotalStakes();

        // keep track of the total EUROs to be burned after purchased liquidated asset
        uint256 burnEuros;

        // Keep track if the native tokens purchased
        uint256 nativePurchased;

        // NOTE To do later change forloop to avoid out of gas
        // iterates over each stakerAddress in the stakers array and retrieves their position
        for (uint256 j = 0; j < stakers.length; j++) {
            // READ get stakerAddress position
            VaultifyStructs.Position memory _position = positions[stakers[j]];

            // get stakerAddress stake Amount
            uint256 _stakedAmount = getMinimumStakeAmount(_position);

            if (_stakedAmount > 0) {
                // Iterate throught all the liquidated assets array and buy them automatically
                for (uint256 i = 0; i < _assets.length; i++) {
                    VaultifyStructs.Asset memory asset = _assets[i];

                    if (asset.amount > 0) {
                        // retrieves the asset's USD price from a Chainlink oracle
                        (, int256 assetPriceUsd, , , ) = AggregatorV3Interface(
                            asset.token.clAddr
                        ).latestRoundData();

                        // Calculate the portion/share of the stakerAddress in speicific amount of liquidated token from the vault
                        // based on the avaible amount of liquidated tokens * amountUsersStake / totalStakedAmountInPool;
                        // calculates the stakerAddress's portion of the asset based on their stake
                        uint256 _portion = (asset.amount * _stakedAmount) /
                            stakeTotal;

                        // The cost in Euros that the staker will use to automatically purchase
                        // //their share of the liquidated asset.
                        uint256 costInEuros = (((_portion *
                            10 ** (18 - asset.token.dec) *
                            uint256(assetPriceUsd)) / uint256(priceEurUsd)) *
                            _hundredPRC) / _collateralRate;

                        if (costInEuros > _position.stakedEurosAmount) {
                            // adjusts the portion to be proportional to the available EUROs
                            _portion =
                                (_portion * _position.stakedEurosAmount) /
                                costInEuros;

                            costInEuros = _position.stakedEurosAmount;
                        }

                        _position.stakedEurosAmount -= costInEuros;

                        // add the rewards to an already exisiting rewards if any
                        rewards[
                            abi.encodePacked(
                                _position.stakerAddress,
                                asset.token.symbol
                            )
                        ] += _portion;

                        // burn Euros that the stakers paid the liquidated asset with
                        burnEuros += costInEuros;

                        // Handle tokens transfer from the manager to liquidity pool
                        if (asset.token.addr == address(0)) {
                            // Keep track of totalAmount of purchased ETH by the user to use it to get any leftovers.
                            nativePurchased += _portion;
                        } else {
                            // transferring  portion of tokens FROM the poolManager TO
                            // the LiquidityPool contract (address(this)) to be claimed later
                            IERC20(asset.token.addr).safeTransferFrom(
                                poolManager,
                                address(this),
                                _portion
                            );
                        }
                    }
                }
            }
            // WRITE
            positions[stakers[j]] = _position;
        }

        uint256 actualBurnAmount = Math.min(
            burnEuros,
            IEUROs(EUROs).balanceOf(address(this))
        );

        // Burn EUROS tokens to keep the value of the token and control tokens circulation/supply.
        if (actualBurnAmount > 0)
            IEUROs(EUROs).burn(address(this), actualBurnAmount);

        // return any excess ETH that was distributed to stakers
        returnExcessETH(_assets, nativePurchased);
    }

    // @audit-info change visibility back to private when the test is finished
    // function that ETH left over after stakers purchased
    /// @notice Returns excess ETH to the pool manager after asset distribution
    /// @dev This function is called internally after distributing liquidated assets
    /// @param _assets Array of assets that were distributed
    /// @param _nativePurchased Total amount of ETH purchased by stakers
    function returnExcessETH(
        VaultifyStructs.Asset[] memory _assets,
        uint256 _nativePurchased
    ) public {
        // Loop throught all the the liquidated assets until _asset.token.addr == address(0)
        // if so check of there any leftovers
        for (uint256 i = 0; i < _assets.length; i++) {
            address _assetAddr = _assets[i].token.addr;
            bytes32 _assetSymbol = _assets[i].token.symbol;
            uint256 excessAmount = _assets[i].amount > _nativePurchased
                ? _assets[i].amount - _nativePurchased
                : 0;

            if (_assetAddr == address(0) && _assetSymbol != bytes32(0)) {
                (bool sent, ) = poolManager.call{value: excessAmount}("");
                if (!sent) revert VaultifyErrors.NativeTxFailed();
            }
        }
    }

    /// @notice Allows users to claim their accumulated rewards
    /// @dev Users can claim rewards earned from their staked positions
    function claimRewards() public {
        // Get the accepted Tokens by the admin
        VaultifyStructs.Token[] memory _tokens = ITokenManager(tokenManager)
            .getAcceptedTokens();

        for (uint256 i = 0; i < _tokens.length; i++) {
            VaultifyStructs.Token memory _token = _tokens[i];
            uint256 _rewardsAmount = rewards[
                abi.encodePacked(msg.sender, _token.symbol)
            ];

            if (_rewardsAmount > 0) {
                // First we delete the rewards before making external calls(Reentracy attacks)
                delete rewards[abi.encodePacked(msg.sender, _token.symbol)];

                if (_token.addr == address(0)) {
                    (bool sent, ) = payable(msg.sender).call{
                        value: _rewardsAmount
                    }("");
                    if (!sent) revert VaultifyErrors.NativeTxFailed();
                } else {
                    IERC20(_token.addr).safeTransfer(
                        msg.sender,
                        _rewardsAmount
                    );
                }
            }
        }
    }

    // @notice Calculates the total amount of TST tokens in the pool
    /// @dev Includes both staked and pending TST tokens
    /// @return _totalTstTokens The total amount of TST tokens in the pool
    function getTotalTst() public view returns (uint256 _totalTstTokens) {
        for (uint256 i = 0; i < stakers.length; i++) {
            address _staker = stakers[i];
            _totalTstTokens +=
                positions[_staker].stakedTstAmount +
                pendingStakes[_staker].pendingTstAmount;
        }
        return _totalTstTokens;
    }

    /// @notice Distributes reward fees to pool participants
    /// @dev Called by the pool manager to distribute fees among stakers
    /// @param _amount The total amount of fees to distribute
    function distributeRewardFees(uint256 _amount) external onlyPoolManager {
        uint256 _totalTST = getTotalTst();

        if (_totalTST > 0) {
            for (uint256 i = 0; i < stakers.length; i++) {
                address _staker = stakers[i];

                // distribute fees among already consolidated position
                uint256 positionsFeeShares = (_amount *
                    positions[_staker].stakedTstAmount) / _totalTST;

                positions[_staker].stakedEurosAmount += positionsFeeShares;

                // distribute Fees among pending position
                uint256 pendPositionFeeShares = (_amount *
                    pendingStakes[_staker].pendingTstAmount) / _totalTST;

                pendingStakes[_staker]
                    .pendingEurosAmount += pendPositionFeeShares;
            }
        }
    }

    // @audit visibility changes from private to external
    /// @notice Retrieves the accumulated rewards for a specific staker
    /// @dev Calculates and returns the rewards across all supported tokens
    /// @param _staker The address of the staker
    /// @return An array of Reward structs representing the staker's rewards
    function getStakerRewards(
        address _staker
    ) public view returns (VaultifyStructs.Reward[] memory) {
        // Get the accepted tokens by the protocol
        VaultifyStructs.Token[] memory _tokens = ITokenManager(tokenManager)
            .getAcceptedTokens();

        // Create a fixed sized array based on the length of _tokens
        VaultifyStructs.Reward[] memory _reward = new VaultifyStructs.Reward[](
            _tokens.length
        );

        for (uint256 i = 0; i < _tokens.length; i++) {
            _reward[i] = VaultifyStructs.Reward({
                tokenSymbol: _tokens[i].symbol,
                rewardAmount: rewards[
                    abi.encodePacked(_staker, _tokens[i].symbol)
                ],
                tokenDecimals: _tokens[i].dec
            });
        }
        return _reward;
    }

    /// @notice Retrieves the pending stakes of a specific holder
    /// @dev Returns the amounts of TST and EUROs tokens in pending stakes
    /// @param _staker The address of the stake holder
    /// @return _pendingTST The amount of pending TST tokens
    /// @return _pendingEUROS The amount of pending EUROs tokens
    function getStakerPendingStakes(
        address _staker
    ) public view returns (uint256 _pendingTST, uint256 _pendingEUROS) {
        VaultifyStructs.PendingStake memory _pendingStake = pendingStakes[
            _staker
        ];
        if (_pendingStake.stakerAddress == _staker) {
            _pendingTST += _pendingStake.pendingTstAmount;
            _pendingEUROS += _pendingStake.pendingEurosAmount;
        }
    }

    /// @notice Retrieves the current position and rewards of a holder
    /// @dev Returns the staked amounts and accumulated rewards
    /// @param _staker The address of the position holder
    /// @return _position The current staked position of the holder
    /// @return _rewards An array of accumulated rewards for the holder
    function getPosition(
        address _staker
    )
        external
        view
        returns (
            VaultifyStructs.Position memory _position,
            VaultifyStructs.Reward[] memory _rewards
        )
    {
        // get the user position
        _position = positions[_staker];

        // Get the stakerAddress pending stakes
        (uint256 _pendingTST, uint256 _pendingEUROs) = getStakerPendingStakes(
            _staker
        );

        // Add the total amount of the user deposit in both TST/EUROS
        // in the protocol(pending and staked)
        _position.stakedEurosAmount += _pendingEUROs;
        _position.stakedTstAmount += _pendingTST;

        //if a stakerAddress's staked TST is greater than zero, they receive additional
        // EUROs proportional to their TST stake. This mechanism is
        // designed to encourage stakers to deposit more TST governance to the pool
        // tokens into the pool

        if (_position.stakedTstAmount > 0) {
            uint256 rewardsEuros = (IERC20(EUROs).balanceOf(poolManager) *
                _position.stakedTstAmount) / getTotalTst();

            _position.stakedEurosAmount += rewardsEuros;
        }

        _rewards = getStakerRewards(_staker);
    }

    /// @notice Allows users to withdraw all their staked tokens during an emergency state
    function emergencyWithdraw() external onlyDuringEmergency nonReentrant {
        claimRewards();

        VaultifyStructs.Position memory _position = positions[msg.sender];
        VaultifyStructs.PendingStake memory _pendingStake = pendingStakes[
            msg.sender
        ];
        uint256 totalEuros;
        uint256 totalTst;

        {
            totalEuros =
                _position.stakedEurosAmount +
                _pendingStake.pendingEurosAmount;

            if (totalEuros > 0) {
                IERC20(EUROs).safeTransfer(msg.sender, totalEuros);
            }
        }

        {
            totalTst =
                _position.stakedTstAmount +
                _pendingStake.pendingTstAmount;

            if (totalTst > 0) {
                IERC20(TST).safeTransfer(msg.sender, totalTst);
            }
        }

        deletePosition(msg.sender);
        delete pendingStakes[msg.sender];

        emit VaultifyEvents.EmergencyWithdrawal(
            msg.sender,
            totalEuros,
            totalTst
        );
    }

    /// @notice Toggles the emergency state of the contract
    /// @dev Can only be called by the pool manager
    /// @param _isEmergencyActive The new emergency state
    function toggleEmergencyState(
        bool _isEmergencyActive
    ) external onlyPoolManager {
        isEmergencyActive = _isEmergencyActive;
        emit VaultifyEvents.EmergencyStateChanged(_isEmergencyActive);
    }
}
