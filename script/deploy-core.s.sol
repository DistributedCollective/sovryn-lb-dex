// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {ILBFactory, LBFactory} from "src/LBFactory.sol";
import {ILBRouter, ISovrynLBFactoryV1, ILBLegacyFactory, ILBLegacyRouter, IWNATIVE, LBRouter} from "src/LBRouter.sol";
import {IERC20, LBPair} from "src/LBPair.sol";
import {LBQuoter} from "src/LBQuoter.sol";

import {BipsConfig} from "./config/bips-config.sol";
import {LBPairUpgradeableBeacon} from "src/LBPairUpgradeableBeacon.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";


contract CoreDeployer is Script {
    using stdJson for string;

    uint256 private constant FLASHLOAN_FEE = 0.05e16; //0.05%
    address deployer;

    struct Deployment {
        address factoryV1;
        address factoryV2;
        address feeRecipient;
        address lbPairImplementation;
        address lbPairUpgradeableBeacon;
        address owner;
        address quoter;
        address routerV2;
        address wNative;
    }

    // string[] chains = ["anvil"];
    string[] chains = ["bob_testnet"];

    function setUp() public {
        // _overwriteDefaultArbitrumRPC();
    }

    function run() public {
        string memory jsonAssets = vm.readFile("script/config/deployment_assets.json");
        deployer = tx.origin;
        uint256 envPK = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0)); 
        if(envPK != 0 && vm.envBool("USE_ENV_PK")) {
            // CLI command would look like USE_ENV_PK=true forge script ...
            deployer = vm.addr(envPK);
        }

        console.log("Deployer address: %s", deployer);

        address factoryV2;
        address routerV2;
        address lbPairUpgradeableBeacon;
        address lbPairImplementation;
        address quoter;

        for (uint256 i = 0; i < chains.length; i++) {
            vm.createSelectFork(StdChains.getChain(chains[i]).rpcUrl);
            vm.startBroadcast(deployer);

            bytes memory quoteAssetsRaw = jsonAssets.parseRaw(string(abi.encodePacked(".", chains[i],".quoteAssets")));
            console.log("quoteAssetsRaw");
            console.logBytes(quoteAssetsRaw);
            address[] memory quoteAssets = abi.decode(quoteAssetsRaw, (address[]));
            console.log("quoteAssets ->");
            for (uint256 i = 0; i < quoteAssets.length; i++) {
                console.log(quoteAssets[i]);
            }
            console.log("quoteAssets <-");
            
            string memory jsonBase = vm.readFile("script/config/deployments.json");
            bytes memory rawDeploymentData = jsonBase.parseRaw(string(abi.encodePacked(".", chains[i])));
            //console.logBytes(rawDeploymentData);
            Deployment memory deployment = abi.decode(rawDeploymentData, (Deployment));

            console.log("\nDeploying V2 on %s", chains[i]);

            if(deployment.factoryV2 == address(0)) {
                console.log("Deploying factory v2...");
                factoryV2 = Upgrades.deployTransparentProxy(
                    "LBFactory.sol",
                    deployment.owner,
                    ""
                );

                deployment.factoryV2 = factoryV2;
                console.log("LBFactory deployed -->", factoryV2);
            } else {
                factoryV2 = deployment.factoryV2;
            }

            if(deployment.lbPairImplementation == address(0)) {
                console.log("Deploying lbPairImplementation...");
                lbPairImplementation = address(new LBPair(ILBFactory(factoryV2)));
                deployment.lbPairImplementation = lbPairImplementation;
                console.log("lbPairImplementation deployed -->", lbPairImplementation);
            } else {
                lbPairImplementation = deployment.lbPairImplementation;
            }

            
            if(deployment.lbPairUpgradeableBeacon == address(0)) {
                console.log("Deploying lbPairUpgradeableBeacon...");
                lbPairUpgradeableBeacon = address(new LBPairUpgradeableBeacon(lbPairImplementation, deployer, factoryV2));
                deployment.lbPairUpgradeableBeacon = lbPairUpgradeableBeacon;
                console.log("lbPairUpgradeableBeacon deployed -->", lbPairUpgradeableBeacon);
            } else {
                lbPairUpgradeableBeacon = deployment.lbPairUpgradeableBeacon;
            }

            console.log("initializing lbFactory...");
            LBFactory(factoryV2).initialize(deployment.feeRecipient, deployer, FLASHLOAN_FEE, lbPairUpgradeableBeacon);
            console.log("LBFactory initialized, owner --> ", LBFactory(factoryV2).owner());

            if(deployment.routerV2 == address(0)) {
                Options memory opts;
                opts.constructorData = abi.encode(ILBFactory(factoryV2), ISovrynLBFactoryV1(deployment.factoryV1), IWNATIVE(deployment.wNative));
                console.log("Deploying routerV2...");
                routerV2 = Upgrades.deployTransparentProxy(
                    "LBRouter.sol",
                    deployment.owner,
                    "",
                    opts
                );
                console.log("LBRouter deployed -->", routerV2);
            } else {
                routerV2 = deployment.routerV2;
            }

            deployment.routerV2 = routerV2;


            if(deployment.quoter == address(0)) {
                console.log("Deploying LBQuoter...");
                quoter = address(new LBQuoter(
                    deployment.factoryV1,
                    factoryV2,
                    routerV2
                ));
                deployment.quoter = quoter;
                console.log("LBQuoter deployed -->", address(quoter));
            } else {
                quoter = deployment.quoter;
            }
            // Serialize the updated deployment struct back to JSON
            // @dev Moving the updatedJsonBase assignment down will cause Stack too deep issue
            string memory updatedJsonBase = jsonBase.serialize(string(abi.encodePacked(".", chains[i])), abi.encode(deployment));

            // address[] memory quoteAssets = deployment.quoteAssets;
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

            LBFactory(factoryV2).transferOwnership(deployment.owner);

            console.log("The new pendingOwner: ", LBFactory(factoryV2).pendingOwner());
            console.log("Please accept the ownership of factory at: ", address(factoryV2));

            vm.stopBroadcast();
            //@todo this approach messes up the json formatting - need to find the right way:
            // Write the updated JSON back to the file
            // vm.writeFile("script/config/deployments.json", abi.decode(updatedJsonBase)); 
        }
    }

    // function _overwriteDefaultArbitrumRPC() private {
    //     StdChains.setChain(
    //         "arbitrum_one_goerli",
    //         StdChains.ChainData({
    //             name: "Arbitrum One Goerli",
    //             chainId: 421613,
    //             rpcUrl: vm.envString("ARBITRUM_TESTNET_RPC_URL")
    //         })
    //     );
    // }
}
