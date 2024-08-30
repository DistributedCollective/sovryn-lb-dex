// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./LBPairBase.sol";
import "./interfaces/ILBPairExt.sol";


/**
 * @dev we introduced this contract to solve the contract size limit issue, basically hold the implementation of some logic of the LBPair contract
 */
contract LBPairExt is LBPairBase, ILBPairExt {
    using BinHelper for bytes32;
    using FeeHelper for uint128;
    using LiquidityConfigurations for bytes32;
    using OracleHelper for OracleHelper.Oracle;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;
    using PairParameterHelper for bytes32;
    using PriceHelper for uint256;
    using PriceHelper for uint24;
    using SafeCast for uint256;
    using SampleMath for bytes32;
    using TreeMath for TreeMath.TreeUint24;
    using Uint256x256Math for uint256;

    /**
     * @dev Constructor for the Liquidity Book Pair contract that sets the Liquidity Book Factory
     * @param factory_ The Liquidity Book Factory
     */
    constructor(ILBFactory factory_ ) LBPairBase(factory_) {
        _disableInitializers();
    }

    /**
     * @notice Swap tokens iterating over the bins until the entire amount is swapped.
     * Token X will be swapped for token Y if `swapForY` is true, and token Y for token X if `swapForY` is false.
     * This function will not transfer the tokens from the caller, it is expected that the tokens have already been
     * transferred to this contract through another contract, most likely the router.
     * That is why this function shouldn't be called directly, but only through one of the swap functions of a router
     * that will also perform safety checks, such as minimum amounts and slippage.
     * The variable fee is updated throughout the swap, it increases with the number of bins crossed.
     * The oracle is updated at the end of the swap.
     * @param swapForY Whether you're swapping token X for token Y (true) or token Y for token X (false)
     * @param to The address to send the tokens to
     * @return amountsOut The encoded amounts of token X and token Y sent to `to`
     */
    function swap(bool swapForY, address to) external override returns (bytes32 amountsOut) {
        _nonReentrantBefore();

        bytes32 hooksParameters = _hooksParameters;

        bytes32 reserves = _reserves;
        bytes32 protocolFees = _protocolFees;

        bytes32 amountsLeft = swapForY ? reserves.receivedX(_tokenX()) : reserves.receivedY(_tokenY());
        if (amountsLeft == 0) revert LBPair__InsufficientAmountIn();

        bool swapForY_ = swapForY; // Avoid stack too deep error

        Hooks.beforeSwap(hooksParameters, msg.sender, to, swapForY_, amountsLeft);

        reserves = reserves.add(amountsLeft);

        bytes32 parameters = _parameters;
        uint16 binStep = _binStep();

        uint24 activeId = parameters.getActiveId();

        parameters = parameters.updateReferences(block.timestamp);

        while (true) {
            bytes32 binReserves = _bins[activeId];
            if (!binReserves.isEmpty(!swapForY_)) {
                parameters = parameters.updateVolatilityAccumulator(activeId);

                (bytes32 amountsInWithFees, bytes32 amountsOutOfBin, bytes32 totalFees) =
                    binReserves.getAmounts(parameters, binStep, swapForY_, activeId, amountsLeft);

                if (amountsInWithFees > 0) {
                    amountsLeft = amountsLeft.sub(amountsInWithFees);
                    amountsOut = amountsOut.add(amountsOutOfBin);

                    bytes32 pFees = totalFees.scalarMulDivBasisPointRoundDown(parameters.getProtocolShare());

                    if (pFees > 0) {
                        protocolFees = protocolFees.add(pFees);
                        amountsInWithFees = amountsInWithFees.sub(pFees);
                    }

                    _bins[activeId] = binReserves.add(amountsInWithFees).sub(amountsOutOfBin);

                    emit Swap(
                        msg.sender,
                        to,
                        activeId,
                        amountsInWithFees,
                        amountsOutOfBin,
                        parameters.getVolatilityAccumulator(),
                        totalFees,
                        pFees
                    );
                }
            }

            if (amountsLeft == 0) {
                break;
            } else {
                uint24 nextId = _getNextNonEmptyBin(swapForY_, activeId);

                if (nextId == 0 || nextId == type(uint24).max) revert LBPair__OutOfLiquidity();

                activeId = nextId;
            }
        }

        if (amountsOut == 0) revert LBPair__InsufficientAmountOut();

        _reserves = reserves.sub(amountsOut);
        _protocolFees = protocolFees;

        parameters = _oracle.update(parameters, activeId);
        _parameters = parameters.setActiveId(activeId);

        if (swapForY_) {
            amountsOut.transferY(_tokenY(), to);
        } else {
            amountsOut.transferX(_tokenX(), to);
        }

        _nonReentrantAfter();

        Hooks.afterSwap(hooksParameters, msg.sender, to, swapForY_, amountsOut);
    }

    /**
     * @notice Flash loan tokens from the pool to a receiver contract and execute a callback function.
     * The receiver contract is expected to return the tokens plus a fee to this contract.
     * The fee is calculated as a percentage of the amount borrowed, and is the same for both tokens.
     * @param receiver The contract that will receive the tokens and execute the callback function
     * @param amounts The encoded amounts of token X and token Y to flash loan
     * @param data Any data that will be passed to the callback function
     */
    function flashLoan(ILBFlashLoanCallback receiver, bytes32 amounts, bytes calldata data) external override {
        _nonReentrantBefore();

        if (amounts == 0) revert LBPair__ZeroBorrowAmount();

        bytes32 hooksParameters = _hooksParameters;

        bytes32 reservesBefore = _reserves;
        bytes32 totalFees = _getFlashLoanFees(amounts);

        Hooks.beforeFlashLoan(hooksParameters, msg.sender, address(receiver), amounts);

        amounts.transfer(_tokenX(), _tokenY(), address(receiver));

        (bool success, bytes memory rData) = address(receiver).call(
            abi.encodeWithSelector(
                ILBFlashLoanCallback.LBFlashLoanCallback.selector,
                msg.sender,
                _tokenX(),
                _tokenY(),
                amounts,
                totalFees,
                data
            )
        );

        if (!success || rData.length != 32 || abi.decode(rData, (bytes32)) != Constants.CALLBACK_SUCCESS) {
            revert LBPair__FlashLoanCallbackFailed();
        }

        bytes32 balancesAfter = bytes32(0).received(_tokenX(), _tokenY());

        if (balancesAfter.lt(reservesBefore.add(totalFees))) revert LBPair__FlashLoanInsufficientAmount();

        bytes32 feesReceived = balancesAfter.sub(reservesBefore);

        _reserves = balancesAfter;
        _protocolFees = _protocolFees.add(feesReceived);

        emit FlashLoan(msg.sender, receiver, _parameters.getActiveId(), amounts, feesReceived, feesReceived);

        _nonReentrantAfter();

        Hooks.afterFlashLoan(hooksParameters, msg.sender, address(receiver), totalFees, feesReceived);
    }

    /**
     * @notice Mint liquidity tokens by depositing tokens into the pool.
     * It will mint Liquidity Book (LB) tokens for each bin where the user adds liquidity.
     * This function will not transfer the tokens from the caller, it is expected that the tokens have already been
     * transferred to this contract through another contract, most likely the router.
     * That is why this function shouldn't be called directly, but through one of the add liquidity functions of a
     * router that will also perform safety checks.
     * @dev Any excess amount of token will be sent to the `to` address.
     * @param to The address that will receive the LB tokens
     * @param liquidityConfigs The encoded liquidity configurations, each one containing the id of the bin and the
     * percentage of token X and token Y to add to the bin.
     * @param refundTo The address that will receive the excess amount of tokens
     * @return amountsReceived The amounts of token X and token Y received by the pool
     * @return amountsLeft The amounts of token X and token Y that were not added to the pool and were sent to `to`
     * @return liquidityMinted The amounts of LB tokens minted for each bin
     */
    function mint(address to, bytes32[] calldata liquidityConfigs, address refundTo)
        external
        override
        returns (bytes32 amountsReceived, bytes32 amountsLeft, uint256[] memory liquidityMinted)
    {
        _nonReentrantBefore();

        if (liquidityConfigs.length == 0) revert LBPair__EmptyMarketConfigs();

        bytes32 hooksParameters = _hooksParameters;

        MintArrays memory arrays = MintArrays({
            ids: new uint256[](liquidityConfigs.length),
            amounts: new bytes32[](liquidityConfigs.length),
            liquidityMinted: new uint256[](liquidityConfigs.length)
        });

        bytes32 reserves = _reserves;

        amountsReceived = reserves.received(_tokenX(), _tokenY());

        Hooks.beforeMint(hooksParameters, msg.sender, to, liquidityConfigs, amountsReceived);

        amountsLeft = _mintBins(liquidityConfigs, amountsReceived, to, arrays);

        _reserves = reserves.add(amountsReceived.sub(amountsLeft));

        liquidityMinted = arrays.liquidityMinted;

        emit TransferBatch(msg.sender, address(0), to, arrays.ids, liquidityMinted);
        emit DepositedToBins(msg.sender, to, arrays.ids, arrays.amounts);

        if (amountsLeft > 0) amountsLeft.transfer(_tokenX(), _tokenY(), refundTo);

        _nonReentrantAfter();

        Hooks.afterMint(hooksParameters, msg.sender, to, liquidityConfigs, amountsReceived.sub(amountsLeft));
    }

    /**
     * @notice Burn Liquidity Book (LB) tokens and withdraw tokens from the pool.
     * This function will burn the tokens directly from the caller
     * @param from The address that will burn the LB tokens
     * @param to The address that will receive the tokens
     * @param ids The ids of the bins from which to withdraw
     * @param amountsToBurn The amounts of LB tokens to burn for each bin
     * @return amounts The amounts of token X and token Y received by the user
     */
    function burn(address from, address to, uint256[] calldata ids, uint256[] calldata amountsToBurn)
        external
        override
        returns (bytes32[] memory amounts)
    {
        _nonReentrantBefore();

        if (ids.length == 0 || ids.length != amountsToBurn.length) revert LBPair__InvalidInput();

        bytes32 hooksParameters = _hooksParameters;

        Hooks.beforeBurn(hooksParameters, msg.sender, from, to, ids, amountsToBurn);

        address from_ = from; // Avoid stack too deep error

        amounts = new bytes32[](ids.length);

        bytes32 amountsOut;

        for (uint256 i; i < ids.length;) {
            uint24 id = ids[i].safe24();
            uint256 amountToBurn = amountsToBurn[i];

            if (amountToBurn == 0) revert LBPair__ZeroAmount(id);

            bytes32 binReserves = _bins[id];
            uint256 supply = totalSupply(id);

            _burn(from_, id, amountToBurn);

            bytes32 amountsOutFromBin = binReserves.getAmountOutOfBin(amountToBurn, supply);

            if (amountsOutFromBin == 0) revert LBPair__ZeroAmountsOut(id);

            binReserves = binReserves.sub(amountsOutFromBin);

            if (supply == amountToBurn) _tree.remove(id);

            _bins[id] = binReserves;
            amounts[i] = amountsOutFromBin;
            amountsOut = amountsOut.add(amountsOutFromBin);

            unchecked {
                ++i;
            }
        }

        _reserves = _reserves.sub(amountsOut);

        emit TransferBatch(msg.sender, from_, address(0), ids, amountsToBurn);
        emit WithdrawnFromBins(msg.sender, to, ids, amounts);

        amountsOut.transfer(_tokenX(), _tokenY(), to);

        _nonReentrantAfter();

        Hooks.afterBurn(hooksParameters, msg.sender, from_, to, ids, amountsToBurn);
    }

    /**
     * @notice Collect the protocol fees from the pool.
     * @return collectedProtocolFees The amount of protocol fees collected
     */
    function collectProtocolFees()
        external
        override
        returns (bytes32 collectedProtocolFees)
    {
        bytes32 protocolFees = _protocolFees;

        (uint128 x, uint128 y) = protocolFees.decode();
        bytes32 ones = uint128(x > 0 ? 1 : 0).encode(uint128(y > 0 ? 1 : 0));

        collectedProtocolFees = protocolFees.sub(ones);

        if (collectedProtocolFees != 0) {
            _protocolFees = ones;
            _reserves = _reserves.sub(collectedProtocolFees);

            emit CollectedProtocolFees(msg.sender, collectedProtocolFees);

            collectedProtocolFees.transfer(_tokenX(), _tokenY(), msg.sender);
        }
    }

    /**
     * @notice Increase the length of the oracle used by the pool
     * @param newLength The new length of the oracle
     */
    function increaseOracleLength(uint16 newLength) external override {
        bytes32 parameters = _parameters;

        uint16 oracleId = parameters.getOracleId();

        // activate the oracle if it is not active yet
        if (oracleId == 0) {
            oracleId = 1;
            _parameters = parameters.setOracleId(oracleId);
        }

        _oracle.increaseLength(oracleId, newLength);

        emit OracleLengthIncreased(msg.sender, newLength);
    }

    /**
     * @notice Sets the static fee parameters of the pool
     * @dev Can only be called by the factory
     * @param baseFactor The base factor of the static fee
     * @param filterPeriod The filter period of the static fee
     * @param decayPeriod The decay period of the static fee
     * @param reductionFactor The reduction factor of the static fee
     * @param variableFeeControl The variable fee control of the static fee
     * @param protocolShare The protocol share of the static fee
     * @param maxVolatilityAccumulator The max volatility accumulator of the static fee
     */
    function setStaticFeeParameters(
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator
    ) external override {
        _setStaticFeeParameters(
            _parameters,
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulator
        );
    }

    /**
     * @notice Forces the decay of the volatility reference variables
     * @dev Can only be called by the factory
     */
    function forceDecay() external override {
        bytes32 parameters = _parameters;

        _parameters = parameters.updateIdReference().updateVolatilityReference();

        emit ForcedDecay(msg.sender, parameters.getIdReference(), parameters.getVolatilityReference());
    }

    /**
     * @notice Overrides the batch transfer function to call the hooks before and after the transfer
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param ids The ids of the tokens to transfer
     * @param amounts The amounts of the tokens to transfer
     */
    function batchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata amounts)
        public
        override(LBToken, ILBPairExt)
    {
        _nonReentrantBefore();

        bytes32 hooksParameters = _hooksParameters;

        Hooks.beforeBatchTransferFrom(hooksParameters, msg.sender, from, to, ids, amounts);

        LBToken.batchTransferFrom(from, to, ids, amounts);

        _nonReentrantAfter();

        Hooks.afterBatchTransferFrom(hooksParameters, msg.sender, from, to, ids, amounts);
    }

    /**
     * @dev Helper function to mint liquidity in each bin in the liquidity configurations
     * @param liquidityConfigs The liquidity configurations
     * @param amountsReceived The amounts received
     * @param to The address to mint the liquidity to
     * @param arrays The arrays to store the results
     * @return amountsLeft The amounts left
     */
    function _mintBins(
        bytes32[] calldata liquidityConfigs,
        bytes32 amountsReceived,
        address to,
        MintArrays memory arrays
    ) private returns (bytes32 amountsLeft) {
        uint16 binStep = _binStep();

        bytes32 parameters = _parameters;
        uint24 activeId = parameters.getActiveId();

        amountsLeft = amountsReceived;

        for (uint256 i; i < liquidityConfigs.length;) {
            (bytes32 maxAmountsInToBin, uint24 id) = liquidityConfigs[i].getAmountsAndId(amountsReceived);
            (uint256 shares, bytes32 amountsIn, bytes32 amountsInToBin) =
                _updateBin(binStep, activeId, id, maxAmountsInToBin, parameters);

            amountsLeft = amountsLeft.sub(amountsIn);

            arrays.ids[i] = id;
            arrays.amounts[i] = amountsInToBin;
            arrays.liquidityMinted[i] = shares;

            _mint(to, id, shares);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Helper function to update a bin during minting
     * @param binStep The bin step of the pair
     * @param activeId The id of the active bin
     * @param id The id of the bin
     * @param maxAmountsInToBin The maximum amounts in to the bin
     * @param parameters The parameters of the pair
     * @return shares The amount of shares minted
     * @return amountsIn The amounts in
     * @return amountsInToBin The amounts in to the bin
     */
    function _updateBin(uint16 binStep, uint24 activeId, uint24 id, bytes32 maxAmountsInToBin, bytes32 parameters)
        internal
        returns (uint256 shares, bytes32 amountsIn, bytes32 amountsInToBin)
    {
        bytes32 binReserves = _bins[id];

        uint256 price = id.getPriceFromId(binStep);
        uint256 supply = totalSupply(id);

        (shares, amountsIn) = binReserves.getSharesAndEffectiveAmountsIn(maxAmountsInToBin, price, supply);
        amountsInToBin = amountsIn;

        if (id == activeId) {
            parameters = parameters.updateVolatilityParameters(id, block.timestamp);

            bytes32 fees = binReserves.getCompositionFees(parameters, binStep, amountsIn, supply, shares);

            if (fees != 0) {
                uint256 userLiquidity = amountsIn.sub(fees).getLiquidity(price);
                bytes32 protocolCFees = fees.scalarMulDivBasisPointRoundDown(parameters.getProtocolShare());

                if (protocolCFees != 0) {
                    amountsInToBin = amountsInToBin.sub(protocolCFees);
                    _protocolFees = _protocolFees.add(protocolCFees);
                }

                uint256 binLiquidity = binReserves.add(fees.sub(protocolCFees)).getLiquidity(price);
                shares = userLiquidity.mulDivRoundDown(supply, binLiquidity);

                parameters = _oracle.update(parameters, id);
                _parameters = parameters;

                emit CompositionFees(msg.sender, id, fees, protocolCFees);
            }
        } else {
            amountsIn.verifyAmounts(activeId, id);
        }

        if (shares == 0 || amountsInToBin == 0) revert LBPair__ZeroShares(id);

        if (supply == 0) _tree.add(id);

        _bins[id] = binReserves.add(amountsInToBin);
    }
}