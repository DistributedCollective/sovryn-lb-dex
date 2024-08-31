// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.20;

contract LBPairUnstructuredStorage {
    bytes32 internal constant _SLOT_TOKEN_X = 0x3441ab29b24daf7a3fd59500b0e08396ec08ec96f5cc2d0362924cdd45cfec31; // keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.TokenX")) - 1));
    bytes32 internal constant _SLOT_TOKEN_Y = 0x7e1935766b7c49e7482a018a5ee52ca183a2ddfcb6810787916934079aa58264; // keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.TokenY")) - 1));
    bytes32 internal constant _SLOT_BIN_STEP = 0xff057b3b4d4500dda208cde5d654db7aa2ec63ac10ab9f9956a1f56973842782; // keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.BinStep")) - 1));
    bytes32 internal constant _SLOT_PAIR_SYMBOL = 0x64fb4ecf63a4059a0bb1412609335673d4954bff8e9740d216d9469d190cbb3f; // keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.PairTokenSymbol")) - 1));
    bytes32 internal constant _SLOT_PAIR_NAME = 0xd668863f064048ee8c87390227ca6556d110ecf41306c7b64aab5c1c530b2d84; // keccak256(abi.encode(uint256(keccak256("sovrynlbdex.pair.storage.PairTokenName")) - 1));

}