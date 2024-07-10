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
import {VaultifyStructs} from "./libraries/VaultifyStructs.sol";

// @audit IF THE CONTRACT IS NOT PAUSED
/// @title LiquidationPool Contract
/// @notice This contract manages liquidated assets and distributing them to stakestakers
contract LiquidationPool is ILiquidationPool {
    using SafeERC20 for IERC20;

    address private immutable TST;
    address private immutable EUROs;
    address private immutable eurUsd;

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

    uint256 public constant MINIMUM_DEPOSIT = 0.5e18;

    address[] public stakers;

    // PendingStake[] private pendingStakes;
    address payable public poolManager;
    address public tokenManager;
    bool public isEmergencyActive;

    mapping(address => Position) private positions;
    mapping(bytes => uint256) private rewards;
    mapping(address => PendingStake) private pendingStakes;
    mapping(address => uint256) private stakersIndex;

    /// @notice Initializes the Liquidation Pool
    /// @param _TST Address of the TST token contract
    /// @param _EUROs Address of the EUROs token contract
    /// @param _eurUsd Address of the EUR/USD price feed contract
    /// @param _tokenManager Address of the Token Manager contract
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

    modifier onlyPoolManager() {
        if (msg.sender != poolManager)
            revert VaultifyErrors.UnauthorizedCaller(msg.sender);
        _;
    }

    modifier onlyDuringEmergency() {
        if (!isEmergencyActive) revert VaultifyErrors.EmergencyStateNotActive();
        _;
    }

    /// @notice Increases a user's position in the liquidity pool
    /// @dev Allows users to deposit TST and EUROs tokens into the pool
    /// @param _tstVal The amount of TST tokens to deposit
    /// @param _eurosVal The amount of EUROs tokens to deposit
    function increasePosition(uint256 _tstVal, uint256 _eurosVal) external {
        require(
            _tstVal >= MINIMUM_DEPOSIT || _eurosVal >= MINIMUM_DEPOSIT,
            "Deposit must exceed minimum requirement"
        );

        // Check if the contract has allowance to transfer both tokens
        bool isTstApproved = IERC20(TST).allowance(msg.sender, address(this)) >=
            _tstVal;

        bool isEurosApproved = IERC20(EUROs).allowance(
            msg.sender,
            address(this)
        ) >= _eurosVal;

        if (!isEurosApproved) revert VaultifyErrors.NotEnoughEurosAllowance();
        if (!isTstApproved) revert VaultifyErrors.NotEnoughTstAllowance();

        consolidatePendingStakes();
        ILiquidationPoolManager(poolManager).distributeFees();

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

        // READ FROM THE STORAGE ONCE
        PendingStake storage stake = pendingStakes[msg.sender];

        PendingStake memory updatePendingStake = PendingStake({
            stakerAddress: msg.sender,
            createdAt: block.timestamp,
            pendingTstAmount: stake.pendingTstAmount + _tstVal,
            pendingEurosAmount: stake.pendingEurosAmount + _eurosVal
        });

        pendingStakes[msg.sender] = updatePendingStake;

        // Add the staker/stakerAddress as unique to avoid duplicate address
        addUniqueStaker(msg.sender); // TODO

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
    function decreasePosition(uint256 _tstVal, uint256 _eurosVal) external {
        // READ from memory
        Position memory _stakerPosition = positions[msg.sender];

        // Check if the user has enough tst or Euros tokens to remove from it position

        if (
            _stakerPosition.stakedTstAmount < _tstVal &&
            _stakerPosition.stakedEurosAmount < _eurosVal
        ) revert VaultifyErrors.InvalidDecrementAmount();

        consolidatePendingStakes();
        ILiquidationPoolManager(poolManager).distributeFees();

        if (_tstVal > 0) {
            IERC20(TST).safeTransfer(msg.sender, _tstVal);
            unchecked {
                _stakerPosition.stakedTstAmount -= _tstVal;
            }
        }

        if (_eurosVal > 0) {
            IERC20(EUROs).safeTransfer(msg.sender, _eurosVal);
            unchecked {
                _stakerPosition.stakedEurosAmount -= _eurosVal;
            }
        }

        // create function to check if the positon is Empty
        if (
            _stakerPosition.stakedTstAmount == 0 &&
            _stakerPosition.stakedEurosAmount == 0
        ) {
            deletePosition(_stakerPosition.stakerAddress);
        }

        emit VaultifyEvents.positionDecreased(msg.sender, _tstVal, _eurosVal);
    }

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

    /// @notice Consolidates pending stakes into active positions
    /// @dev This function is called internally to process pending stakes that are older than 24 hours
    /// @dev It helps prevent front-running attacks and ensures fair reward distribution
    function consolidatePendingStakes() private {
        // Create a dealine variable to check the validity of the order
        uint256 deadline = block.timestamp - 1 days;

        for (uint256 i = 0; i < stakers.length; i++) {
            address stakerAddress = stakers[i];

            // State changing operation
            PendingStake storage _pendingStake = pendingStakes[stakerAddress];

            // @audit-issue Check if stakerAddress == _pending.stakerAddress to avoid storage collision.
            // This is done to reduce MEV opportunities(wait at least 24H to increase position)
            // To prevent front-runing attacks to take advantage of rewards
            if (_pendingStake.createdAt < deadline) {
                // READ from STORAGE once
                Position storage _position = positions[
                    _pendingStake.stakerAddress
                ];

                // update Changes in memory first
                Position memory updatePosition = Position({
                    stakerAddress: _pendingStake.stakerAddress,
                    stakedTstAmount: _position.stakedTstAmount +
                        _pendingStake.pendingTstAmount,
                    stakedEurosAmount: _position.stakedEurosAmount +
                        _pendingStake.pendingEurosAmount
                });

                // WRITE TO STORAGE ONCE
                positions[_pendingStake.stakerAddress] = updatePosition;

                // Reset the pending stake
                delete pendingStakes[stakerAddress];
            }
        }
    }

    /// @notice Calculates the minimum stake amount for a given position
    /// @dev Returns the smaller of TST or EUROs amounts in the position
    /// @param _position The position to evaluate
    /// @return The minimum stake amount
    function getMinimumStakeAmount(
        Position memory _position
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
            Position memory _position = positions[stakers[i]];
            _stake += getMinimumStakeAmount(_position);
        }
    }

    /// @notice Distributes liquidated assets to pool participants
    /// @dev Called when assets are liquidated, distributes them among stakers
    /// @param _assets Array of liquidated assets to distribute
    /// @param _collateralRate The collateral rate used for calculations
    /// @param _hundredPRC Constant representing 100% (used for percentage calculations)
    function distributeLiquatedAssets(
        VaultifyStructs.Asset[] memory _assets,
        uint256 _collateralRate,
        uint256 _hundredPRC
    ) external payable {
        // Consolidate pending stakes
        consolidatePendingStakes();

        // get the price of EURO/USD from chainlink
        (, int256 priceEurUsd, , , ) = AggregatorV3Interface(eurUsd)
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
            Position memory _position = positions[stakers[j]];

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

                        ///TODO  Ask AI how can I think like or how can I develop this mathematical mindset as DeFi developer.
                        // Ask for resources.

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

        // Burn EUROS tokens to keep the value of the token and control tokens circulation/supply.
        if (burnEuros > 0) IEUROs(EUROs).burn(address(this), burnEuros);

        // return any excess ETH that was distributed to stakers
        returnExcessETH(_assets, nativePurchased);
    }

    // function that ETH left over after stakers purchased
    /// @notice Returns excess ETH to the pool manager after asset distribution
    /// @dev This function is called internally after distributing liquidated assets
    /// @param _assets Array of assets that were distributed
    /// @param _nativePurchased Total amount of ETH purchased by stakers
    function returnExcessETH(
        VaultifyStructs.Asset[] memory _assets,
        uint256 _nativePurchased
    ) private {
        // Loop throught all the the assets until _asset.token.addr == address(0)
        // if so check of there any leftovers
        for (uint256 i = 0; i < _assets.length; i++) {
            address _assetAddr = _assets[i].token.addr;
            bytes32 _assetSymbol = _assets[i].token.symbol;

            if (_assetAddr == address(0) && _assetSymbol != bytes32(0)) {
                (bool sent, ) = poolManager.call{
                    value: _assets[i].amount - _nativePurchased
                }("");
                require(sent);
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
                    IERC20(_token.addr).transfer(msg.sender, _rewardsAmount);
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

    /// @notice Retrieves the accumulated rewards for a specific staker
    /// @dev Calculates and returns the rewards across all supported tokens
    /// @param _staker The address of the staker
    /// @return An array of Reward structs representing the staker's rewards
    function getStakerRewards(
        address _staker
    ) private view returns (Reward[] memory) {
        // Get the accepted tokens by the protocol
        VaultifyStructs.Token[] memory _tokens = ITokenManager(tokenManager)
            .getAcceptedTokens();

        // Create a fixed sized array based on the length of _tokens
        Reward[] memory _reward = new Reward[](_tokens.length);

        for (uint256 i = 0; i < _tokens.length; i++) {
            _reward[i] = Reward({
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
        PendingStake memory _pendingStake = pendingStakes[_staker];
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
        returns (Position memory _position, Reward[] memory _rewards)
    {
        // get the user position
        _position = positions[_staker];

        // Get the stakerAddress pending stakes
        (uint256 _pendingTST, uint256 _pendingEUROs) = getStakerPendingStakes(
            _staker
        );

        // Add the total amount of the user deposit in both TST/EUROS
        // in the protocol(pending or staked)
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

    // function that allow user to remove their stakes in case of of a potential hacks.
    function emergencyWithdraw() external onlyDuringEmergency {
        claimRewards();

        Position memory _position = positions[msg.sender];
        PendingStake memory _pendingStake = pendingStakes[msg.sender];
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
    function setEmergencyState(
        bool _isEmergencyActive
    ) external onlyPoolManager {
        isEmergencyActive = _isEmergencyActive;
        emit VaultifyEvents.EmergencyStateChanged(_isEmergencyActive);
    }
}
