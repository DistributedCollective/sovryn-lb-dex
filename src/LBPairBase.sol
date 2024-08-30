// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BinHelper} from "./libraries/BinHelper.sol";
import {Constants} from "./libraries/Constants.sol";
import {FeeHelper} from "./libraries/FeeHelper.sol";
import {LiquidityConfigurations} from "./libraries/math/LiquidityConfigurations.sol";
import {ReentrancyGuardUpgradeable} from "./libraries/ReentrancyGuardUpgradeable.sol";
import {ILBFactory} from "./interfaces/ILBFactory.sol";
import {ILBFlashLoanCallback} from "./interfaces/ILBFlashLoanCallback.sol";
import {ILBPair} from "./interfaces/ILBPair.sol";
import {LBToken, ILBToken} from "./LBToken.sol";
import {OracleHelper} from "./libraries/OracleHelper.sol";
import {PackedUint128Math} from "./libraries/math/PackedUint128Math.sol";
import {PairParameterHelper} from "./libraries/PairParameterHelper.sol";
import {PriceHelper} from "./libraries/PriceHelper.sol";
import {SafeCast} from "./libraries/math/SafeCast.sol";
import {SampleMath} from "./libraries/math/SampleMath.sol";
import {TreeMath} from "./libraries/math/TreeMath.sol";
import {Uint256x256Math} from "./libraries/math/Uint256x256Math.sol";
import {Hooks} from "./libraries/Hooks.sol";
import {ILBHooks} from "./interfaces/ILBHooks.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {StringUtils} from "./libraries/StringUtils.sol";
import {ILBPairExt} from "./interfaces/ILBPairExt.sol";
import {ILBPairErrors, ILBPairEvents, ILBPairStructs} from "./interfaces/ILBPair.sol";

/**
 * @title Liquidity Book Pair
 * @notice The Liquidity Book Pair contract is the core contract of the Liquidity Book protocol
 */
contract LBPairBase is LBToken, ReentrancyGuardUpgradeable, ILBPairErrors, ILBPairEvents, ILBPairStructs  {
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

    uint256 internal constant _MAX_TOTAL_FEE = 0.1e18; // 10%

    ILBFactory internal immutable _factory;

    bytes32 internal _parameters;

    bytes32 internal _reserves;
    bytes32 internal _protocolFees;

    mapping(uint256 => bytes32) internal _bins;

    TreeMath.TreeUint24 internal _tree;
    OracleHelper.Oracle internal _oracle;

    bytes32 internal _hooksParameters;

    string internal _tokenName;
    string internal _tokenSymbol;

    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    modifier onlyProtocolFeeRecipient() {
        if (msg.sender != _factory.getFeeRecipient()) revert LBPair__OnlyProtocolFeeRecipient();
        _;
    }

    /**
     * @dev Constructor for the Liquidity Book Pair contract that sets the Liquidity Book Factory
     * @param factory_ The Liquidity Book Factory
     */
    constructor(ILBFactory factory_ ) {
        _factory = factory_;

        _disableInitializers();
    }

    /**
     * @dev Reverts if the caller is not the factory
     */
    function _onlyFactory() private view {
        if (msg.sender != address(_factory)) revert LBPair__OnlyFactory();
    }

    /**
     * @dev Returns the address of the token X
     * @return The address of the token X
     */
    function _tokenX() internal view returns (IERC20) {
        address tokenX_;
        bytes32 slot = 0x3441ab29b24daf7a3fd59500b0e08396ec08ec96f5cc2d0362924cdd45cfec31; //keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.TokenX")) - 1));
        assembly {
            tokenX_ := sload(slot)
        }

        return IERC20(tokenX_);
    }

    /**
     * @dev Returns the address of the token Y
     * @return The address of the token Y
     */
    function _tokenY() internal view returns (IERC20) {
        address tokenY_;
        bytes32 slot = 0x7e1935766b7c49e7482a018a5ee52ca183a2ddfcb6810787916934079aa58264; // keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.TokenY")) - 1));
        assembly {
            tokenY_ := sload(slot)
        }

        return IERC20(tokenY_);
    }

    /**
     * @dev Returns the bin step of the pool, in basis points
     * @return binStep_ The bin step of the pool
     */
    function _binStep() internal view returns (uint16 binStep_) {
        bytes32 slot = 0xff057b3b4d4500dda208cde5d654db7aa2ec63ac10ab9f9956a1f56973842782; //keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.BinStep")) - 1));
        assembly {
            binStep_ := sload(slot)
        }
    }

    /**
     * @dev Returns next non-empty bin
     * @param swapForY Whether the swap is for Y
     * @param id The id of the bin
     * @return The id of the next non-empty bin
     */
    function _getNextNonEmptyBin(bool swapForY, uint24 id) internal view returns (uint24) {
        return swapForY ? _tree.findFirstRight(id) : _tree.findFirstLeft(id);
    }

    /**
     * @dev Returns the encoded fees amounts for a flash loan
     * @param amounts The amounts of the flash loan
     * @return The encoded fees amounts
     */
    function _getFlashLoanFees(bytes32 amounts) internal view returns (bytes32) {
        uint128 fee = uint128(_factory.getFlashLoanFee());
        (uint128 x, uint128 y) = amounts.decode();

        unchecked {
            uint256 precisionSubOne = Constants.PRECISION - 1;
            x = ((uint256(x) * fee + precisionSubOne) / Constants.PRECISION).safe128();
            y = ((uint256(y) * fee + precisionSubOne) / Constants.PRECISION).safe128();
        }

        return x.encode(y);
    }

    /**
     * @dev Sets the static fee parameters of the pair
     * @param parameters The current parameters of the pair
     * @param baseFactor The base factor of the static fee
     * @param filterPeriod The filter period of the static fee
     * @param decayPeriod The decay period of the static fee
     * @param reductionFactor The reduction factor of the static fee
     * @param variableFeeControl The variable fee control of the static fee
     * @param protocolShare The protocol share of the static fee
     * @param maxVolatilityAccumulator The max volatility accumulator of the static fee
     */
    function _setStaticFeeParameters(
        bytes32 parameters,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator
    ) internal {
        if (
            baseFactor == 0 && filterPeriod == 0 && decayPeriod == 0 && reductionFactor == 0 && variableFeeControl == 0
                && protocolShare == 0 && maxVolatilityAccumulator == 0
        ) {
            revert LBPair__InvalidStaticFeeParameters();
        }

        parameters = parameters.setStaticFeeParameters(
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulator
        );

        {
            uint16 binStep = _binStep();
            bytes32 maxParameters = parameters.setVolatilityAccumulator(maxVolatilityAccumulator);
            uint256 totalFee = maxParameters.getBaseFee(binStep) + maxParameters.getVariableFee(binStep);
            if (totalFee > _MAX_TOTAL_FEE) {
                revert LBPair__MaxTotalFeeExceeded();
            }
        }

        _parameters = parameters;

        emit StaticFeeParametersSet(
            msg.sender,
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulator
        );
    }
}
