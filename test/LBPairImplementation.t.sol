// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../src/LBPair.sol";
import "../src/libraries/ImmutableClone.sol";
import "../src/LBFactory.sol";
import {LBPairBeaconProxy} from "../src/LBPairBeaconProxy.sol";
import {LBPairBeaconProxy} from "../src/LBPairBeaconProxy.sol";
import "./helpers/TestHelper.sol";
import "./mocks/ERC20Reentrant.sol";



contract LBPairImplementationTest is Test, TestHelper {
    address implementation;
    ERC20Mock tokenX = new ERC20Mock(18);
    ERC20Mock tokenY = new ERC20Mock(18);
    ERC20Reentrant tokenXReentrant = new ERC20Reentrant();
    ERC20Reentrant tokenYReentrant = new ERC20Reentrant();

    function setUp() override public {
        super.setUp();
    }

    function testFuzz_Getters(address _tokenX, address _tokenY, uint16 binStep) public {
        assumeNotPrecompile(_tokenX);
        assumeNotPrecompile(_tokenY);
        vm.etch(_tokenX, address(tokenX).code);
        vm.etch(_tokenY, address(tokenY).code);
        LBFactory factoryImpl = new LBFactory();
        LBFactory factory = LBFactory(address(new TransparentUpgradeableProxy(address(factoryImpl), DEV, "")));
        LBPairExt lbPairExt = new LBPairExt(ILBFactory(address(factory)));
        LBPair lbPairImplementation = new LBPair(ILBFactory(address(factory)), ILBPairExt(address(lbPairExt)));
        LBPairUpgradeableBeacon lbPairUpgradeableBeacon = new LBPairUpgradeableBeacon(address(lbPairImplementation), DEV, address(factory));
        ILBFactory(factory).initialize(DEV, DEV, DEFAULT_FLASHLOAN_FEE, address(lbPairUpgradeableBeacon));

        LBPairBeaconProxy lbDexBeaconProxy = new LBPairBeaconProxy(address(lbPairUpgradeableBeacon), address(tokenX), address(tokenY), binStep, "");

        ILBPair pair = ILBPair(address(lbDexBeaconProxy));

        vm.prank(address(factory));
        pair.initialize(1, 1, 1, 1, 1, 1, 1, 1);

        string memory binStepStr = StringUtils.uint16ToString(binStep);

        assertEq(address(pair.getTokenX()), address(tokenX), "testFuzz_Getters::1");
        assertEq(address(pair.getTokenY()), address(tokenY), "testFuzz_Getters::2");
        assertEq(pair.getBinStep(), binStep, "testFuzz_Getters::3");
        assertEq(pair.name(), string.concat("Liquidity Book Token ", tokenX.symbol(), "/", tokenY.symbol(), "/", binStepStr), "testFuzz_Getters::4");
        assertEq(pair.symbol(), string.concat("LBT_", tokenX.symbol(), "/", tokenY.symbol(), "/", binStepStr), "testFuzz_Getters::5");
    }

    function testFuzz_Getters_Reentrant(address _tokenX, address _tokenY, uint16 binStep) public {
        assumeNotPrecompile(_tokenX);
        assumeNotPrecompile(_tokenY);
        vm.etch(_tokenX, address(tokenXReentrant).code);
        vm.etch(_tokenY, address(tokenYReentrant).code);
        LBPairExt lbPairExt = new LBPairExt(ILBFactory(address(factory)));
        LBFactory factoryImpl = new LBFactory();
        LBFactory factory = LBFactory(address(new TransparentUpgradeableProxy(address(factoryImpl), DEV, "")));
        LBPair lbPairImplementation = new LBPair(ILBFactory(address(factory)), ILBPairExt(address(lbPairExt)));
        LBPairUpgradeableBeacon lbPairUpgradeableBeacon = new LBPairUpgradeableBeacon(address(lbPairImplementation), DEV, address(factory));
        ILBFactory(factory).initialize(DEV, DEV, DEFAULT_FLASHLOAN_FEE, address(lbPairUpgradeableBeacon));

        LBPairBeaconProxy lbDexBeaconProxy = new LBPairBeaconProxy(address(lbPairUpgradeableBeacon), address(tokenXReentrant), address(tokenYReentrant), binStep, "");

        ILBPair pair = ILBPair(address(lbDexBeaconProxy));

        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        vm.prank(address(factory));
        pair.initialize(1, 1, 1, 1, 1, 1, 1, 1);

        assertEq(address(pair.getTokenX()), address(tokenXReentrant), "testFuzz_Getters::1");
        assertEq(address(pair.getTokenY()), address(tokenYReentrant), "testFuzz_Getters::2");
        assertEq(pair.getBinStep(), binStep, "testFuzz_Getters::3");

        /** Name & symbol should not be set */
        assertEq(pair.name(), "", "testFuzz_Getters::4");
        assertEq(pair.symbol(), "", "testFuzz_Getters::5");
    }

    function testFuzz_revert_InitializeImplementation() public {
        LBPairExt lbPairExt = new LBPairExt(ILBFactory(address(factory)));
        factory = LBFactory(makeAddr("factory"));
        implementation = address(new LBPair(ILBFactory(factory), ILBPairExt(address(lbPairExt))));

        vm.expectRevert(ILBPairErrors.LBPair__OnlyFactory.selector);
        LBPair(implementation).initialize(1, 1, 1, 1, 1, 1, 1, 1);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vm.prank(address(factory));
        LBPair(implementation).initialize(1, 1, 1, 1, 1, 1, 1, 1);
    }
}
