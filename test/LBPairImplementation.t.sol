// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../src/LBPair.sol";
import "../src/libraries/ImmutableClone.sol";
import "../src/LBFactory.sol";
import {LBDexUpgradeableBeacon} from "../src/LBDexUpgradeableBeacon.sol";
import {LBDexBeaconProxy} from "../src/LBDexBeaconProxy.sol";
import "./helpers/TestHelper.sol";



contract LBPairImplementationTest is Test, TestHelper {
    address implementation;

    function setUp() override public {
        super.setUp();
    }

    function testFuzz_Getters(address tokenX, address tokenY, uint16 binStep) public {
        factory = new LBFactory();
        LBPair lbPairImplementation = new LBPair(ILBFactory(address(factory)));
        LBDexUpgradeableBeacon lbDexUpgradeableBeacon = new LBDexUpgradeableBeacon(address(lbPairImplementation), DEV);
        ILBFactory(factory).initialize(DEV, DEV, DEFAULT_FLASHLOAN_FEE, address(lbDexUpgradeableBeacon));

        LBDexBeaconProxy lbDexBeaconProxy = new LBDexBeaconProxy(address(lbDexUpgradeableBeacon), tokenX, tokenY, binStep, "");

        ILBPair pair = ILBPair(address(lbDexBeaconProxy));

        assertEq(address(pair.getTokenX()), tokenX, "testFuzz_Getters::1");
        assertEq(address(pair.getTokenY()), tokenY, "testFuzz_Getters::2");
        assertEq(pair.getBinStep(), binStep, "testFuzz_Getters::3");
    }

    function testFuzz_revert_InitializeImplementation() public {
        factory = LBFactory(makeAddr("factory"));
        implementation = address(new LBPair(ILBFactory(factory)));

        vm.expectRevert(ILBPair.LBPair__OnlyFactory.selector);
        LBPair(implementation).initialize(1, 1, 1, 1, 1, 1, 1, 1);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vm.prank(address(factory));
        LBPair(implementation).initialize(1, 1, 1, 1, 1, 1, 1, 1);
    }
}
