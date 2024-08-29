// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";


interface IOwnable {
    function owner() external view returns (address);
}

/**
 * @dev this is the Proxy contract of the LBPair.
 * @dev this contract instantiates LBPair contract via OZ Beacon Proxy (LBPairUpgradeableBeacon in this case).
 */
contract LBPairBeaconProxy is BeaconProxy {
    receive() external payable {}

    bytes32 public constant slotTokenX = 0x3441ab29b24daf7a3fd59500b0e08396ec08ec96f5cc2d0362924cdd45cfec31; // keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.TokenX")) - 1));
    bytes32 public constant slotTokenY = 0x7e1935766b7c49e7482a018a5ee52ca183a2ddfcb6810787916934079aa58264; // keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.TokenY")) - 1));
    bytes32 public constant slotBinStep = 0xff057b3b4d4500dda208cde5d654db7aa2ec63ac10ab9f9956a1f56973842782; //keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.BinStep")) - 1))

    constructor(address _beaconAddress, address _tokenX, address _tokenY, uint16 _binStep, bytes memory _data) payable BeaconProxy(_beaconAddress, "") {
        assembly {
            // Slot for _tokenX
            sstore(slotTokenX, _tokenX)

            // Slot for _tokenY
            sstore(slotTokenY, _tokenY)

            // Slot for _binStep
            sstore(slotBinStep, _binStep)
        }

        ERC1967Utils.upgradeBeaconToAndCall(_beaconAddress, _data);
    }

    function getLBPairBeacon() external view returns (address) {
        return _getBeacon();
    }
}