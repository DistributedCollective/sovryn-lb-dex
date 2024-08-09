// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

contract LBDexUpgradeableBeacon is UpgradeableBeacon, Pausable {
    address private _previousImplementation;

    constructor (address _implementation, address _owner) UpgradeableBeacon(_implementation, _owner) {
        if(_owner != address(0)) {
            _transferOwnership(_owner);
        }
    }
    
    function pause() external virtual onlyOwner {
        require(_previousImplementation != address(0x1), "beacon is in paused mode");
        _previousImplementation = UpgradeableBeacon.implementation();
        upgradeTo(address(0x1));
    }

    function unpause() external virtual onlyOwner {
        require(_previousImplementation != address(0), "No previous implementation");
        upgradeTo(_previousImplementation);
        _previousImplementation = address(0);
    }

    function implementation() public view virtual override whenNotPaused() returns (address) {
        return UpgradeableBeacon.implementation();
    }
}