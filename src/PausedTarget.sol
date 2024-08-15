// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @notice This is a placeholder contract that is used as the beacon implementation when it's paused.
 * Since we can't use the non-contract (e.g: 0x0, 0x1) as the implementation of the beacon, so we will use this contract instead.
 */
contract PausedTarget {
    error ContractIsPaused();
    constructor() {}

    fallback() external payable {
        revert ContractIsPaused();
    }
}
