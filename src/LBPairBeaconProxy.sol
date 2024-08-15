// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";


interface IOwnable {
    function owner() external view returns (address);
}

contract LBPairBeaconProxy is BeaconProxy {
    string public TOKEN_NAME;
    string public TOKEN_SYMBOL;

    receive() external payable {}

    /**
     * @notice Returns the name of the token.
     * @return tokenName_ The name of the token.
     */
    function name() public view returns (string memory) {
        return TOKEN_NAME;
    }

    /**
     * @notice Returns the symbol of the token, usually a shorter version of the name.
     * @return tokenSymbol_ The symbol of the token.
     */
    function symbol() public view returns (string memory) {
        return TOKEN_SYMBOL;
    }

    constructor(address _beaconAddress, address _tokenX, address _tokenY, uint16 _binStep, bytes memory _data) payable BeaconProxy(_beaconAddress, "") {
        bytes32 slotTokenX = keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.TokenX")) - 1));
        bytes32 slotTokenY = keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.TokenY")) - 1));
        bytes32 slotBinStep = keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.BinStep")) - 1));

        string memory tokenXSymbol = IERC20Metadata(_tokenX).symbol();
        string memory tokenYSymbol = IERC20Metadata(_tokenY).symbol();

        TOKEN_NAME = string.concat("Liquidity Book Token ", tokenXSymbol, " - ", tokenYSymbol);
        TOKEN_SYMBOL = string.concat("LBT_", tokenXSymbol, "-", tokenYSymbol);

        // bytes32 slotLBPairTokenName = keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.LBPairTokenName")) - 1));
        // bytes32 slotLBPairTokenSymbol = keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.LBPairTokenSymbol")) - 1));

        // string memory tokenXSymbol = IERC20Metadata(_tokenX).symbol();
        // string memory tokenYSymbol = IERC20Metadata(_tokenY).symbol();
        // string memory tokenName = string.concat("Liquidity Book Token ", tokenXSymbol, " - ", tokenYSymbol);
        // string memory tokenSymbol = string.concat("LBT_", tokenXSymbol, "-", tokenYSymbol);
        assembly {
            // Slot for _tokenX
            sstore(slotTokenX, _tokenX)

            // Slot for _tokenY
            sstore(slotTokenY, _tokenY)

            // Slot for _binStep
            sstore(slotBinStep, _binStep)

            // // Slot for token name
            // sstore(slotLBPairTokenName, tokenName)

            // // Slot for token symbol
            // sstore(slotLBPairTokenSymbol, tokenSymbol)
        }

        ERC1967Utils.upgradeBeaconToAndCall(_beaconAddress, _data);
    }

    function getLBPairBeacon() external view returns (address) {
        return _getBeacon();
    }

    modifier onlyLBPairBeaconOwner {
        require(msg.sender == IOwnable(_getBeacon()).owner(), "Only beacon owner");
        _;
    }
}