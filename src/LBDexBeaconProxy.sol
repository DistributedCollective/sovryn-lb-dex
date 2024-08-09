// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract LBDexBeaconProxy is BeaconProxy {
    address private _previousBeacon;

    receive() external payable {}

    constructor(address _beaconAddress, address _tokenX, address _tokenY, uint16 _binStep, bytes memory _data) payable BeaconProxy(_beaconAddress, "") {
        bytes32 slotTokenX = keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.TokenX")) - 1));
        bytes32 slotTokenY = keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.TokenY")) - 1));
        bytes32 slotBinStep = keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.BinStep")) - 1));
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

    function getBeacon() external view returns (address) {
        return _getBeacon();
    }

    modifier onlyBeaconOwner {
        require(msg.sender == IOwnable(_getBeacon()).owner(), "Only beacon owner");
        _;
    }
}