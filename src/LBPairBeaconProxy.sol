// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.20;

import {BeaconProxy, ERC1967Utils} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {LBPairUnstructuredStorage} from "./LBPairUnstructuredStorage.sol";
import {StringUtils} from "./libraries/StringUtils.sol";


interface IOwnable {
    function owner() external view returns (address);
}

/**
 * @dev this is the Proxy contract of the LBPair.
 * @dev this contract instantiates LBPair contract via OZ Beacon Proxy (LBPairUpgradeableBeacon in this case).
 */
contract LBPairBeaconProxy is BeaconProxy, LBPairUnstructuredStorage {

    using StringUtils for uint16; 
    receive() external payable {}

    constructor(address _beaconAddress, address _tokenX, address _tokenY, uint16 _binStep, bytes memory _data) payable BeaconProxy(_beaconAddress, "") {
        (bool successSymbolX, bytes memory symbolXData) = _tokenX.staticcall(abi.encodeWithSignature("symbol()"));
        string memory tokenXSymbol = abi.decode(symbolXData, (string));

        (bool successSymbolY, bytes memory symbolYData) = _tokenY.staticcall(abi.encodeWithSignature("symbol()"));
        string memory tokenYSymbol = abi.decode(symbolYData, (string));

        require(successSymbolX && successSymbolY , "LBPairBeaconProxy: Failed to get token symbols");
        require(
            keccak256(bytes(tokenXSymbol)) != keccak256(bytes("")) &&
            keccak256(bytes(tokenYSymbol)) != keccak256(bytes("")),
            "LBPairBeaconProxy: Invalid token symbols"
        );

        StorageSlot.getAddressSlot(_SLOT_TOKEN_X).value = _tokenX;
        StorageSlot.getAddressSlot(_SLOT_TOKEN_Y).value = _tokenY;
        StorageSlot.getUint256Slot(_SLOT_BIN_STEP).value = _binStep;
        string memory binStepStr = _binStep.uint16ToString();
        StorageSlot.getStringSlot(_SLOT_PAIR_SYMBOL).value = string.concat("LBT_", tokenXSymbol, "/", tokenYSymbol, "/", binStepStr);
        StorageSlot.getStringSlot(_SLOT_PAIR_NAME).value = string.concat("Liquidity Book Token ", tokenXSymbol, "/", tokenYSymbol,"/", binStepStr);

        ERC1967Utils.upgradeBeaconToAndCall(_beaconAddress, _data);
    }

    function getLBPairBeacon() external view returns (address) {
        return _getBeacon();
    }
}