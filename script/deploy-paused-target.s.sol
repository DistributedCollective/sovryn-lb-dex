// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {PausedTarget} from "src/PausedTarget.sol"; // Adjust the import path according to your project structure

contract DeployPausedTarget is Script {
    function run() external {
        // Define salt and initialize the contract creation code
        bytes32 salt = keccak256(abi.encodePacked("paused-target"));
        bytes memory bytecode = abi.encodePacked(type(PausedTarget).creationCode);

        // Calculate deterministic address
        address deterministicAddress = computeAddress(salt, keccak256(bytecode), address(this));
        
        console.log("Deterministic PausedTarget address will be:", deterministicAddress);

        // Deploy the contract
        address deployedAddress = deployCode(bytecode, salt);
        console.log("Contract deployed at:", deployedAddress);

        // Assert to ensure deployment happened at the deterministic address
        require(deployedAddress == deterministicAddress, "Deployment failed at deterministic address");
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
