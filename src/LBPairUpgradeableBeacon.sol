// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {BaseUpgradeableBeacon} from "./BaseUpgradeableBeacon.sol";
import {ILBFactory} from "./interfaces/ILBFactory.sol";

contract LBPairUpgradeableBeacon is BaseUpgradeableBeacon {
    error Beacon__UnauthorizedCaller(address caller);
    error Beacon__IsPaused();
    error Beacon__IsNotPaused();
    error Beacon__NoPausedImplementation();

    address private _pausedImplementation;
    ILBFactory private _lbFactoryAddress;

    // @notice this is the determenistic PausedTarget contract address that is deployed from deploy-paused-target.s.sol
    // the deployment script using this "keccak256(abi.encodePacked("paused-target"))" as salt
    address public constant TARGET_PAUSED_CONTRACT_ADDRESS = 0xC347b61589e131d5a3fb7eA64c9548095cB434a0;

    modifier onlyAuthorized() {
        if(msg.sender != owner() && _lbFactoryAddress.getAdmin() != msg.sender) revert Beacon__UnauthorizedCaller(msg.sender);
        _;
    }

    modifier whenNotPaused() {
        if(isPaused()) revert Beacon__IsPaused();
        _;
    }

    modifier whenPaused() {
        if(!isPaused()) revert Beacon__IsNotPaused();
        _;
    }

    constructor (address _implementation, address _owner, address _factoryAddress) BaseUpgradeableBeacon(_implementation, _owner) {
        if(_owner != address(0)) {
            _transferOwnership(_owner);
        }

        _lbFactoryAddress = ILBFactory(_factoryAddress);
    }

    /**
     * @notice toggle function to pause
     * Can only be called by owner of this contract or admin addresses that is stored in the factory
     * Can only be called when contract is not in paused mode
     * Will set the implementation to TARGET_PAUSED_CONTRACT_ADDRESS
     */
    function pause() external virtual onlyAuthorized whenNotPaused {
        _pausedImplementation = BaseUpgradeableBeacon.implementation();
        _setImplementation(TARGET_PAUSED_CONTRACT_ADDRESS);
    }

    /**
     * @notice toggle function to unpause
     * Can only be called by owner of this contract or admin addresses that is stored in the factory
     * Can only be called when contract is in paused mode
     * Will set the implementation from TARGET_PAUSED_CONTRACT_ADDRESS to the paused implementation
     */
    function unpause() external virtual onlyAuthorized whenPaused {
        if(_pausedImplementation == address(0)) revert Beacon__NoPausedImplementation();
        _setImplementation(_pausedImplementation);
        _pausedImplementation = address(0);
    }

    /**
     * @dev Upgrades the beacon to a new implementation.
     *
     * Emits an {Upgraded} event.
     *
     * Requirements:
     *
     * - msg.sender must be the owner of the contract.
     * - `newImplementation` must be a contract.
     */
    function upgradeTo(address newImplementation) public override onlyOwner {
        _setImplementation(newImplementation);
        _pausedImplementation = address(0);
    }

    /**
     * @notice function to check if contract is in paused mode.
     * @return true if contract paused, otherwise will return false.
     */
    function isPaused() public view returns(bool){
        return implementation() == address(TARGET_PAUSED_CONTRACT_ADDRESS);
    }

    /**
     * @notice getter function for paused implementation
     * @return paused implementation address
     */
    function pausedImplementation() external view returns(address) {
        return _pausedImplementation;
    }

    /**
     * @notice getter function for lbFactoryAddress
     * @return lb factory address
     */
    function lbFactoryAddress() external view returns(address) {
        return address(_lbFactoryAddress);
    }
}