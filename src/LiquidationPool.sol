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

// Add Event for important task
contract LiquidationPool is ILiquidationPool {
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

    uint256 public constant MINIMUM_DEPOSIT = 0.05e18;

    address[] public holders;

    // PendingStake[] private pendingStakes;
    address payable public poolManager;
    address public tokenManager;

    mapping(address => Position) private positions;
    mapping(bytes => uint256) private rewards;
    mapping(address => PendingStake) private aggregatedPendingStakes;
    mapping(address => uint256) private holdersIndex;

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

    modifier onlyPoolManager() {
        if (msg.sender != poolManager)
            revert VaultifyErrors.UnauthorizedCaller(msg.sender);
        _;
    }

    // TODO Change tokens other tokens names
    // TODO ADD Minimum amount to add to the pool as well as to the smartVaut to encourage liquidator
    // to liquidate Smartvault.
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

        // READ FROM THE STORAGE ONCE
        PendingStake storage stake = aggregatedPendingStakes[msg.sender];

        PendingStake memory updatePendingStake = PendingStake({
            holder: msg.sender,
            createdAt: block.timestamp,
            tstTokens: stake.tstTokens + _tstVal,
            eurosTokens: stake.eurosTokens + _eurosVal
        });

        aggregatedPendingStakes[msg.sender] = updatePendingStake;

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
        ILiquidationPoolManager(poolManager).distributeFees();

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

    // delete Positions and holders
    function deletePosition(address _holder) private {
        // delete holder
        deleteHolder(_holder);
        delete positions[_holder];
    }

    function addUniqueHolder(address _holder) private {
        if (holdersIndex[_holder] == 0) {
            holders.push(_holder);
            // Store the index of the new holder, which is length of the array - 1(index start at 0)
            holdersIndex[_holder] = holders.length - 1;
        } else {
            return;
        }
    }

    function deleteHolder(address _holder) private {
        uint256 index = holdersIndex[_holder];
        if (index != 0 || holders[0] == _holder) {
            // Replace the holder that we want to delete with the last holder in the array holder
            // @audit this will never be able to target the first holder 0
            holders[index] = holders[holders.length - 1];

            // set the index of the desired removed element to last holder in the array
            holdersIndex[holders[holders.length - 1]] = index;

            // Remove the last element
            holders.pop();

            delete holdersIndex[_holder];
        }
    }

    // function that allows pending stakes position to be consolidatin as position in the pool
    function consolidatePendingStakes() private {
        // Create a dealine variable to check the validity of the order
        uint256 deadline = block.timestamp - 1 days;

        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];

            // State changing operation
            PendingStake storage _pendingStake = aggregatedPendingStakes[
                holder
            ];

            // @audit-issue Check if holder == _pending.holder to avoid storage collision.
            // This is done to reduce MEV opportunities(wait at least 24H to increase position)
            // To prevent front-runing attacks to take advantage of rewards
            if (_pendingStake.createdAt < deadline) {
                // READ from STORAGE once
                Position storage position = positions[_pendingStake.holder];

                // update Changes in memory first
                Position memory updatePosition = Position({
                    holder: _pendingStake.holder,
                    tstTokens: position.tstTokens + _pendingStake.tstTokens,
                    eurosTokens: position.eurosTokens +
                        _pendingStake.eurosTokens
                });

                // WRITE TO STORAGE ONCE
                positions[_pendingStake.holder] = updatePosition;

                // Reset the pending stake
                delete aggregatedPendingStakes[holder];
            }
        }
    }

    function getMinimumStakeAmount(
        Position memory _position
    ) private pure returns (uint256) {
        return
            _position.tstTokens > _position.eurosTokens
                ? _position.eurosTokens
                : _position.tstTokens;
    }

    function getTotalStakes() private view returns (uint256 _stake) {
        for (uint256 i = 0; i < holders.length; i++) {
            Position memory _position = positions[holders[i]];
            _stake += getMinimumStakeAmount(_position);
        }
    }

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
        // iterates over each holder in the holders array and retrieves their position
        for (uint256 j = 0; j < holders.length; j++) {
            // READ get holder position
            Position memory _position = positions[holders[j]];

            // get holder stake Amount
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

                        // Calculate the portion/share of the holder in speicific amount of liquidated token from the vault
                        // based on the avaible amount of liquidated tokens * amountUsersStake / totalStakedAmountInPool;
                        // calculates the holder's portion of the asset based on their stake
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

                        if (costInEuros > _position.eurosTokens) {
                            // adjusts the portion to be proportional to the available EUROs
                            _portion =
                                (_portion * _position.eurosTokens) /
                                costInEuros;

                            costInEuros = _position.eurosTokens;
                        }

                        _position.eurosTokens -= costInEuros;

                        // add the rewards to an already exisiting rewards if any
                        rewards[
                            abi.encodePacked(
                                _position.holder,
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
            positions[holders[j]] = _position;
        }

        // Burn EUROS tokens to keep the value of the token and control tokens circulation/supply.
        if (burnEuros > 0) IEUROs(EUROs).burn(address(this), burnEuros);

        // return any excess ETH that was distributed to stakers
        returnExcessETH(_assets, nativePurchased);
    }

    // function that ETH left over after stakers purchased
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

    function claimRewards() external {
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

    function getTotalTst() public view returns (uint256 _tstTokens) {
        for (uint256 i = 0; i < holders.length; i++) {
            address _holder = holders[i];
            _tstTokens +=
                positions[_holder].tstTokens +
                aggregatedPendingStakes[_holder].tstTokens;
        }
        return _tstTokens;
    }

    function distributeRewardFees(uint256 _amount) external onlyPoolManager {
        uint256 _totalTST = getTotalTst();

        if (_totalTST > 0) {
            for (uint256 i = 0; i < holders.length; i++) {
                address _holder = holders[i];

                // distribute fees among already consolidated position
                uint256 positionsFeeShares = (_amount *
                    positions[_holder].tstTokens) / _totalTST;

                positions[_holder].eurosTokens += positionsFeeShares;

                // distribute Fees among pending position
                uint256 pendPositionFeeShares = (_amount *
                    aggregatedPendingStakes[_holder].tstTokens) / _totalTST;

                aggregatedPendingStakes[_holder]
                    .eurosTokens += pendPositionFeeShares;
            }
        }
    }

    function getHolderRewards(
        address _holder
    ) private view returns (Rewards[] memory) {
        // Get the accepted tokens by the protocol
        VaultifyStructs.Token[] memory _tokens = ITokenManager(tokenManager)
            .getAcceptedTokens();

        // Create a fixed sized array based on the length of _tokens
        Rewards[] memory _rewards = new Rewards[](_tokens.length);

        for (uint256 i = 0; i < _tokens.length; i++) {
            _rewards[i] = Rewards(
                _tokens[i].symbol,
                rewards[abi.encodePacked(_holder, _tokens[i].symbol)],
                _tokens[i].dec
            );
        }
        return _rewards;
    }

    // Returns the amount of TST and EUROS tokens of holder pendin stakes
    function getHolderPendingStakes(
        address _holder
    ) public view returns (uint256 _pendingTST, uint256 _pendingEUROS) {
        PendingStake memory _pendingStake = aggregatedPendingStakes[_holder];
        if (_pendingStake.holder == _holder) {
            _pendingTST += _pendingStake.tstTokens;
            _pendingEUROS += _pendingStake.eurosTokens;
        }
    }

    // function that returns the position of user including their pendingStake Tokens as well as rewards
    function position(
        address _holder
    )
        external
        view
        returns (Position memory _position, Rewards[] memory _rewards)
    {
        // get the user position
        _position = positions[_holder];

        // Get the holder pending stakes
        (uint256 _pendingTST, uint256 _pendingEUROs) = getHolderPendingStakes(
            _holder
        );

        // Add the total amount of the user deposit in both TST/EUROS
        // in the protocol(pending or staked)
        _position.eurosTokens += _pendingEUROs;
        _position.tstTokens += _pendingTST;

        //if a holder's staked TST is greater than zero, they receive additional
        // EUROs proportional to their TST stake. This mechanism is
        // designed to encourage holders to deposit more TST governance to the pool
        // tokens into the pool

        if (_position.tstTokens > 0) {
            uint256 rewardsEuros = (IERC20(EUROs).balanceOf(poolManager) *
                _position.tstTokens) / getTotalTst();

            _position.eurosTokens += rewardsEuros;
        }

        _rewards = getHolderRewards(_holder);
    }
}
