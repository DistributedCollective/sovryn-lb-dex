// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {PausedTarget} from "src/PausedTarget.sol"; // Adjust the import path according to your project structure

/**
 * @notice this a deployment script for Paused target contract.
 * PausedTarget contract is a placeholder contract that is used as the beacon implementation when it's paused.
 * Since we can't use the non-contract (e.g: 0x0, 0x1) as the implementation of the beacon, so we will use this contract instead.
 */
contract DeployPausedTarget is Script {
    function run() external {
        // Define salt and initialize the contract creation code
        bytes32 salt = keccak256(abi.encodePacked("paused-target"));
        bytes memory bytecode = type(PausedTarget).creationCode;
        address deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        // Calculate deterministic address
        address deterministicAddress = computeAddress(salt, keccak256(bytecode), deployer);
        
        console.log("Deterministic PausedTarget address will be:", deterministicAddress);

        // Deploy the contract
        vm.startPrank(deployer);
        address deployedAddress = deployCode(bytecode, salt);
        vm.stopPrank();
        console.log("Contract deployed at:", deployedAddress);

        // Assert to ensure deployment happened at the deterministic address
        require(deployedAddress == address(0x576a05E4080C23a653c3c2240DA4437e83dd50bF), "Deployment failed at deterministic address: 1");
        require(deployedAddress == deterministicAddress, "Deployment failed at deterministic address: 2");
    }

    // Helper function to deploy using create2
    function deployCode(bytes memory code, bytes32 salt) internal returns (address) {
        address addr;
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(addr)) { revert(0, 0) }
        }
        return addr;
    }

    function computeAddress(bytes32 salt, bytes32 creationCodeHash, address deployer) internal pure returns (address addr) {
        assembly {
            let ptr := mload(0x40)

            mstore(add(ptr, 0x40), creationCodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, deployer)
            let start := add(ptr, 0x0b)
            mstore8(start, 0xff)
            addr := keccak256(start, 85)
        }
    }
}
