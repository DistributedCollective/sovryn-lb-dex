// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "./helpers/TestHelper.sol";
import {LBDexUpgradeableBeacon} from "src/LBDexUpgradeableBeacon.sol";
import {PausedTarget} from "src/PausedTarget.sol";

contract LBDexUpgradeableBeaconTest is TestHelper {
    LBPair lbPairImplementation;
    LBDexUpgradeableBeacon lbDexUpgradeableBeacon;
    PausedTarget pausedTarget;
    address DETERMINIST_TARGET_PAUSED_CONTRACT_ADDRESS = 0xC347b61589e131d5a3fb7eA64c9548095cB434a0;

    function setUp() public override {
        super.setUp();
        lbPairImplementation = new LBPair(ILBFactory(address(factory)));
        lbDexUpgradeableBeacon = new LBDexUpgradeableBeacon(address(lbPairImplementation), DEV, address(factory));
        pausedTarget = new PausedTarget();
        vm.etch(DETERMINIST_TARGET_PAUSED_CONTRACT_ADDRESS, address(pausedTarget).code);
    }

    function test_Constructor() public {
        assertEq(lbDexUpgradeableBeacon.lbFactoryAddress(), address(factory), "test_Constructor:1");
        assertEq(lbDexUpgradeableBeacon.owner(), DEV, "test_Constructor:2");
        assertEq(lbDexUpgradeableBeacon.implementation(), address(lbPairImplementation), "test_Constructor:3");
    }

    function test_Pause() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(LBDexUpgradeableBeacon.Beacon__UnauthorizedCaller.selector, ALICE));
        lbDexUpgradeableBeacon.pause();

        vm.prank(DEV);
        lbDexUpgradeableBeacon.pause();
        assertEq(lbDexUpgradeableBeacon.previousImplementation(), address(lbPairImplementation));
        assertEq(lbDexUpgradeableBeacon.implementation(), DETERMINIST_TARGET_PAUSED_CONTRACT_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(LBDexUpgradeableBeacon.Beacon__IsPaused.selector));
        lbDexUpgradeableBeacon.pause();
    }

    function test_Unpause() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(LBDexUpgradeableBeacon.Beacon__UnauthorizedCaller.selector, ALICE));
        lbDexUpgradeableBeacon.unpause();

        vm.prank(DEV);
        vm.expectRevert(abi.encodeWithSelector(LBDexUpgradeableBeacon.Beacon__NoPreviousImplementation.selector));
        lbDexUpgradeableBeacon.unpause();

        lbDexUpgradeableBeacon.pause();
        assertEq(lbDexUpgradeableBeacon.previousImplementation(), address(lbPairImplementation));
        assertEq(lbDexUpgradeableBeacon.implementation(), DETERMINIST_TARGET_PAUSED_CONTRACT_ADDRESS);

        lbDexUpgradeableBeacon.unpause();
        assertEq(lbDexUpgradeableBeacon.previousImplementation(), address(0));
        assertEq(lbDexUpgradeableBeacon.implementation(), address(lbPairImplementation));
    }
}
