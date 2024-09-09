// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.10;

library StringUtils {
    function uint16ToString(uint16 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint16 temp = value;
        uint16 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint16(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
