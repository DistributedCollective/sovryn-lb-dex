// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "./helpers/TestHelper.sol";
import {LBPairUpgradeableBeacon} from "src/LBPairUpgradeableBeacon.sol";
import {PausedTarget} from "src/PausedTarget.sol";

contract LBPairBeaconProxyTest is TestHelper {
    LBPair lbPairImplementation;
    LBPairUpgradeableBeacon lbPairUpgradeableBeacon;
    PausedTarget pausedTarget;
    address DETERMINIST_TARGET_PAUSED_CONTRACT_ADDRESS = 0xC347b61589e131d5a3fb7eA64c9548095cB434a0;

    function setUp() public override {
        super.setUp();
        lbPairImplementation = new LBPair(ILBFactory(address(factory)));
        lbPairUpgradeableBeacon = new LBPairUpgradeableBeacon(address(lbPairImplementation), DEV, address(factory));
        pausedTarget = new PausedTarget();
        vm.etch(DETERMINIST_TARGET_PAUSED_CONTRACT_ADDRESS, address(pausedTarget).code);
    }

    function test_Constructor() public view {
        assertEq(lbPairUpgradeableBeacon.lbFactoryAddress(), address(factory), "test_Constructor:1");
        assertEq(lbPairUpgradeableBeacon.owner(), DEV, "test_Constructor:2");
        assertEq(lbPairUpgradeableBeacon.implementation(), address(lbPairImplementation), "test_Constructor:3");
    }

    function test_Pause() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(LBPairUpgradeableBeacon.Beacon__UnauthorizedCaller.selector, ALICE));
        lbPairUpgradeableBeacon.pause();

        vm.prank(DEV);
        lbPairUpgradeableBeacon.pause();
        assertEq(lbPairUpgradeableBeacon.pausedImplementation(), address(lbPairImplementation));
        assertEq(lbPairUpgradeableBeacon.implementation(), DETERMINIST_TARGET_PAUSED_CONTRACT_ADDRESS);

        vm.expectRevert(abi.encodeWithSelector(LBPairUpgradeableBeacon.Beacon__IsPaused.selector));
        lbPairUpgradeableBeacon.pause();
    }

    function test_PauseByAdmin() public {
        bytes32 PAUSER_ROLE = factory.PAUSER_ROLE();
        /** Test Pause by Admin */
        factory.grantRole(PAUSER_ROLE, ALICE);
        vm.prank(ALICE);
        lbPairUpgradeableBeacon.pause();
        assertEq(lbPairUpgradeableBeacon.pausedImplementation(), address(lbPairImplementation));
        assertEq(lbPairUpgradeableBeacon.implementation(), DETERMINIST_TARGET_PAUSED_CONTRACT_ADDRESS);        
    }

    function test_Unpause() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(LBPairUpgradeableBeacon.Beacon__UnauthorizedCaller.selector, ALICE));
        lbPairUpgradeableBeacon.unpause();

        vm.prank(DEV);
        vm.expectRevert(abi.encodeWithSelector(LBPairUpgradeableBeacon.Beacon__IsNotPaused.selector));
        lbPairUpgradeableBeacon.unpause();

        lbPairUpgradeableBeacon.pause();
        assertEq(lbPairUpgradeableBeacon.pausedImplementation(), address(lbPairImplementation));
        assertEq(lbPairUpgradeableBeacon.implementation(), DETERMINIST_TARGET_PAUSED_CONTRACT_ADDRESS);

        lbPairUpgradeableBeacon.unpause();
        assertEq(lbPairUpgradeableBeacon.pausedImplementation(), address(0));
        assertEq(lbPairUpgradeableBeacon.implementation(), address(lbPairImplementation));
    }

    function test_UnpauseByAdmin() public {
        bytes32 PAUSER_ROLE = factory.PAUSER_ROLE();
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(LBPairUpgradeableBeacon.Beacon__UnauthorizedCaller.selector, ALICE));
        lbPairUpgradeableBeacon.unpause();

        lbPairUpgradeableBeacon.pause();
        assertEq(lbPairUpgradeableBeacon.pausedImplementation(), address(lbPairImplementation));
        assertEq(lbPairUpgradeableBeacon.implementation(), DETERMINIST_TARGET_PAUSED_CONTRACT_ADDRESS);

        factory.grantRole(PAUSER_ROLE, ALICE);
        vm.prank(ALICE);
        lbPairUpgradeableBeacon.unpause();
        assertEq(lbPairUpgradeableBeacon.pausedImplementation(), address(0));
        assertEq(lbPairUpgradeableBeacon.implementation(), address(lbPairImplementation));
    }
}
