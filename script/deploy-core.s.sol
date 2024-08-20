// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {ILBFactory, LBFactory} from "src/LBFactory.sol";
import {ILBRouter, ISovrynLBFactoryV1, ILBLegacyFactory, ILBLegacyRouter, IWNATIVE, LBRouter} from "src/LBRouter.sol";
import {IERC20, LBPair} from "src/LBPair.sol";
import {LBQuoter} from "src/LBQuoter.sol";

import {BipsConfig} from "./config/bips-config.sol";
import {LBPairUpgradeableBeacon} from "src/LBPairUpgradeableBeacon.sol";

contract CoreDeployer is Script {
    using stdJson for string;

    uint256 private constant FLASHLOAN_FEE = 5e12;

    struct Deployment {
        address factoryV1;
        address factoryV2;
        address newOwner;
        address routerV2;
        address wNative;
        address lbPairImplementation;
        address lbPairUpgradeableBeacon;
        address quoter;
        address[] quoteAssets;
    }

    string[] chains = ["bob_testnet"];

    function setUp() public {
        _overwriteDefaultArbitrumRPC();
    }

    function run() public {
        string memory json = vm.readFile("script/config/deployments.json");
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        console.log("Deployer address: %s", deployer);

        address factoryV2;
        address routerV2;
        address lbPairUpgradeableBeacon;
        address lbPairImplementation;
        address quoter;

        for (uint256 i = 0; i < chains.length; i++) {
            bytes memory rawDeploymentData = json.parseRaw(string(abi.encodePacked(".", chains[i])));
            Deployment memory deployment = abi.decode(rawDeploymentData, (Deployment));

            console.log("\nDeploying V2.1 on %s", chains[i]);

            vm.createSelectFork(StdChains.getChain(chains[i]).rpcUrl);

            if(deployment.factoryV2 == address(0)) {
                console.log("Deploying factory v2...");
                vm.broadcast(deployer);
                factoryV2 = address(new LBFactory());

                console.log("LBFactory deployed -->", factoryV2);
            } else {
                factoryV2 = deployment.factoryV2;
            }

            deployment.factoryV2 = factoryV2;

            if(deployment.lbPairImplementation == address(0)) {
                console.log("Deploying lbPairImplementation...");
                vm.broadcast(deployer);
                lbPairImplementation = address(new LBPair(ILBFactory(factoryV2)));
                console.log("lbPairImplementation deployed -->", lbPairImplementation);
            } else {
                lbPairImplementation = deployment.lbPairImplementation;
            }

            deployment.lbPairImplementation = lbPairImplementation;

            
            if(deployment.lbPairUpgradeableBeacon == address(0)) {
                console.log("Deploying lbPairUpgradeableBeacon...");
                vm.broadcast(deployer);
                lbPairUpgradeableBeacon = address(new LBPairUpgradeableBeacon(lbPairImplementation, deployer, factoryV2));
                console.log("lbPairUpgradeableBeacon deployed -->", lbPairUpgradeableBeacon);
            } else {
                lbPairUpgradeableBeacon = deployment.lbPairUpgradeableBeacon;
            }

            deployment.lbPairUpgradeableBeacon = lbPairUpgradeableBeacon;

            console.log("initializing lbFactory...");
            vm.broadcast(deployer);
            LBFactory(factoryV2).initialize(deployer, deployer, FLASHLOAN_FEE, lbPairUpgradeableBeacon);
            console.log("LBFactory initialized, owner --> ", LBFactory(factoryV2).owner());

            if(deployment.routerV2 == address(0)) {
                console.log("Deploying routerV2...");
                vm.broadcast(deployer);
                routerV2 = address(new LBRouter(LBFactory(factoryV2), ISovrynLBFactoryV1(deployment.factoryV1), IWNATIVE(deployment.wNative)));
                console.log("LBRouter deployed -->", address(routerV2));
            } else {
                routerV2 = deployment.routerV2;
            }

            deployment.routerV2 = routerV2;


            vm.startBroadcast(deployer);
            if(deployment.quoter == address(0)) {
                console.log("Deploying LBQuoter...");
                quoter = address(new LBQuoter(
                    deployment.factoryV1,
                    factoryV2,
                    routerV2
                ));
                console.log("LBQuoter deployed -->", address(quoter));
            } else {
                quoter = deployment.quoter;
            }

            deployment.quoter = quoter;


            console.log("Setting LBPair implementation set on factoryV2\n");
            LBFactory(factoryV2).setLBPairImplementation(lbPairImplementation);
            console.log("LBPair implementation set on factoryV2\n");

            address[] memory quoteAssets = deployment.quoteAssets;
            for (uint256 j = 0; j < quoteAssets.length; j++) {
                IERC20 quoteAsset = IERC20(quoteAssets[j]);
                if(LBFactory(factoryV2).isQuoteAsset(quoteAsset)) continue;

                /** Add asset quote asset */
                LBFactory(factoryV2).addQuoteAsset(quoteAsset);
                console.log("Quote asset whitelisted -->", address(quoteAsset));
            }

            uint256[] memory presetList = BipsConfig.getPresetList();
            for (uint256 j; j < presetList.length; j++) {
                BipsConfig.FactoryPreset memory preset = BipsConfig.getPreset(presetList[j]);
                LBFactory(factoryV2).setPreset(
                    preset.binStep,
                    preset.baseFactor,
                    preset.filterPeriod,
                    preset.decayPeriod,
                    preset.reductionFactor,
                    preset.variableFeeControl,
                    preset.protocolShare,
                    preset.maxVolatilityAccumulated,
                    preset.isOpen
                );
            }

            LBFactory(factoryV2).transferOwnership(deployment.newOwner);
            vm.stopBroadcast();

            console.log("The new pendingOwner: ", LBFactory(factoryV2).pendingOwner());
            console.log("Please accept the ownership of factory at: ", address(factoryV2));

            // Serialize the updated deployment struct back to JSON
            bytes memory updatedDeployment = abi.encode(deployment);
            json = json.serialize(string(abi.encodePacked(".", chains[i])), updatedDeployment);

            // Write the updated JSON back to the file
            vm.writeFile("script/config/deployments.json", json);
        }
    }

    function _overwriteDefaultArbitrumRPC() private {
        StdChains.setChain(
            "arbitrum_one_goerli",
            StdChains.ChainData({
                name: "Arbitrum One Goerli",
                chainId: 421613,
                rpcUrl: vm.envString("ARBITRUM_TESTNET_RPC_URL")
            })
        );
    }
}
