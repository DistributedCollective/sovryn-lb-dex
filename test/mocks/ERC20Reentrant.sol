// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILBPair} from "src/interfaces/ILBPair.sol";

contract ERC20Reentrant {
    function name() external {
        ILBPair(msg.sender).initialize(1, 1, 1, 1, 1, 1, 1, 1);
    }

    function symbol() external {
        ILBPair(msg.sender).initialize(1, 1, 1, 1, 1, 1, 1, 1);
    }
}
