// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import {ILBFactory} from "./interfaces/ILBFactory.sol";

contract LBDexUpgradeableBeacon is UpgradeableBeacon, Pausable {
    error Beacon__UnauthorizedCaller(address caller);
    error Beacon__IsPaused();
    error Beacon__NoPreviousImplementation();

    address private _previousImplementation;
    ILBFactory private _lbFactoryAddress;
    address public constant TARGET_PAUSED_CONTRACT_ADDRESS = 0xC347b61589e131d5a3fb7eA64c9548095cB434a0;

    modifier onlyAuthorized() {
        if(msg.sender != owner() && !_lbFactoryAddress.isAdmin(msg.sender)) revert Beacon__UnauthorizedCaller(msg.sender);
        _;
    }

    constructor (address _implementation, address _owner, address _factoryAddress) UpgradeableBeacon(_implementation, _owner) {
        if(_owner != address(0)) {
            _transferOwnership(_owner);
        }

        _lbFactoryAddress = ILBFactory(_factoryAddress);
    }

    /**
     * @notice toggle function to pause
     * Can only be called by owner of this contract or admin addresses that is stored in the factory
     * Will set the implementation to TARGET_PAUSED_CONTRACT_ADDRESS
     */
    function pause() external virtual onlyAuthorized {
        if(implementation() == address(TARGET_PAUSED_CONTRACT_ADDRESS)) revert Beacon__IsPaused();
        _previousImplementation = UpgradeableBeacon.implementation();
        upgradeTo(TARGET_PAUSED_CONTRACT_ADDRESS);
    }

    /**
     * @notice toggle function to unpause
     * Can only be called by owner of this contract or admin addresses that is stored in the factory
     * Will set the implementation from TARGET_PAUSED_CONTRACT_ADDRESS to the previous implementation
     */
    function unpause() external virtual onlyAuthorized {
        if(_previousImplementation == address(0)) revert Beacon__NoPreviousImplementation();
        upgradeTo(_previousImplementation);
        _previousImplementation = address(0);
    }

    /**
     * @notice getter function for current implementation
     * @return current implementation address
     */
    function implementation() public view virtual override whenNotPaused() returns (address) {
        return UpgradeableBeacon.implementation();
    }

    /**
     * @notice getter function for previous implementation
     * @return previous implementation address
     */
    function previousImplementation() external view returns(address) {
        return _previousImplementation;
    }

    /**
     * @notice getter function for lbFactoryAddress
     * @return lb factory address
     */
    function lbFactoryAddress() external view returns(address) {
        return address(_lbFactoryAddress);
    }
}