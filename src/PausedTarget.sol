// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

contract PausedTarget {
    error ContractIsPaused();
    constructor() {}

    fallback() external payable {
        revert ContractIsPaused();
    }
}
