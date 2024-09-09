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
import {StringUtils} from "../src/libraries/StringUtils.sol";

contract LBPairImplementationTest is Test, TestHelper {
    address implementation;
    ERC20Mock tokenX;
    ERC20Mock tokenY;
    function setUp() override public {
        tokenX = new ERC20Mock(18);
        tokenY = new ERC20Mock(18);    
        super.setUp();
    }

    function testFuzz_Getters(address _tokenX, address _tokenY, uint16 binStep) public {
        assumeNotPrecompile(_tokenX);
        assumeNotPrecompile(_tokenY);
        vm.etch(_tokenX, address(tokenX).code);
        vm.etch(_tokenY, address(tokenX).code);
        console2.log("X/Y symbol", ERC20(_tokenX).symbol(), "/", ERC20(_tokenY).symbol());
        LBFactory factoryImpl = new LBFactory();
        LBFactory factory = LBFactory(address(new TransparentUpgradeableProxy(address(factoryImpl), DEV, "")));
        LBPair lbPairImplementation = new LBPair(ILBFactory(address(factory)));
        LBPairUpgradeableBeacon lbPairUpgradeableBeacon = new LBPairUpgradeableBeacon(address(lbPairImplementation), DEV, address(factory));
        ILBFactory(factory).initialize(DEV, DEV, DEFAULT_FLASHLOAN_FEE, address(lbPairUpgradeableBeacon));

        LBPairBeaconProxy lbDexBeaconProxy = new LBPairBeaconProxy(address(lbPairUpgradeableBeacon), address(tokenX), address(tokenY), binStep, "");

        ILBPair pair = ILBPair(address(lbDexBeaconProxy));

        vm.prank(address(factory));
        pair.initialize(1, 1, 1, 1, 1, 1, 1, 1);

        assertEq(address(pair.getTokenX()), address(tokenX), "testFuzz_Getters::1");
        assertEq(address(pair.getTokenY()), address(tokenY), "testFuzz_Getters::2");
        assertEq(pair.getBinStep(), binStep, "testFuzz_Getters::3");
        console2.log("tokenX.symbol()", tokenX.symbol());
        console2.log("tokenY.symbol()", tokenY.symbol());
        console2.log("pair.name()", pair.name());
        console2.log("pair.symbol()", pair.symbol());
        string memory binStepStr = StringUtils.uint16ToString(binStep);
        assertEq(pair.name(), string.concat("Liquidity Book Token ", tokenX.symbol(), "/", tokenY.symbol(),"/", binStepStr), "testFuzz_Getters::4");
        assertEq(pair.symbol(), string.concat("LBT_", tokenX.symbol(), "/", tokenY.symbol(),"/", binStepStr), "testFuzz_Getters::5");
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
