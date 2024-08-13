// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {ILBFactory, LBFactory} from "src/LBFactory.sol";
import {ILBRouter, ISovrynLBFactoryV1, ILBLegacyFactory, ILBLegacyRouter, IWNATIVE, LBRouter} from "src/LBRouter.sol";
import {IERC20, LBPair} from "src/LBPair.sol";
import {LBQuoter} from "src/LBQuoter.sol";

import {BipsConfig} from "./config/bips-config.sol";
import {LBDexUpgradeableBeacon} from "src/LBDexUpgradeableBeacon.sol";

contract CoreDeployer is Script {
    using stdJson for string;

    uint256 private constant FLASHLOAN_FEE = 5e12;

    struct Deployment {
        address factoryV1;
        address factoryV2;
        address multisig;
        address routerV1;
        address routerV2;
        address wNative;
    }

    string[] chains = ["bob_testnet"];

    function setUp() public {
        _overwriteDefaultArbitrumRPC();
    }

    function run() public {
        string memory json = vm.readFile("script/config/deployments.json");
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        console.log("Deployer address: %s", deployer);

        for (uint256 i = 0; i < chains.length; i++) {
            bytes memory rawDeploymentData = json.parseRaw(string(abi.encodePacked(".", chains[i])));
            Deployment memory deployment = abi.decode(rawDeploymentData, (Deployment));

            console.log("\nDeploying V2.1 on %s", chains[i]);

            vm.createSelectFork(StdChains.getChain(chains[i]).rpcUrl);

            vm.broadcast(deployer);
            LBFactory factoryV2 = new LBFactory();
            LBPair lbPairImplementation = new LBPair(ILBFactory(address(factoryV2)));
            LBDexUpgradeableBeacon lbDexUpgradeableBeacon = new LBDexUpgradeableBeacon(address(lbPairImplementation), deployer, address(factoryV2));
            factoryV2.initialize(deployer, deployer, FLASHLOAN_FEE, address(lbDexUpgradeableBeacon));
            
            console.log("LBFactory deployed -->", address(factoryV2));

            vm.broadcast(deployer);
            LBPair pairImplementation = new LBPair(factoryV2);
            console.log("LBPair implementation deployed -->", address(pairImplementation));

            vm.broadcast(deployer);
            LBRouter routerV2 = new LBRouter(factoryV2, ISovrynLBFactoryV1(deployment.factoryV1), IWNATIVE(deployment.wNative));
            console.log("LBRouter deployed -->", address(routerV2));

            vm.startBroadcast(deployer);
            LBQuoter quoter = new LBQuoter(
                deployment.factoryV1,
                address(factoryV2),
                address(routerV2)
            );
            console.log("LBQuoter deployed -->", address(quoter));

            factoryV2.setLBPairImplementation(address(pairImplementation));
            console.log("LBPair implementation set on factoryV2\n");

            uint256 quoteAssets = ILBLegacyFactory(deployment.factoryV2).getNumberOfQuoteAssets();
            for (uint256 j = 0; j < quoteAssets; j++) {
                IERC20 quoteAsset = ILBLegacyFactory(deployment.factoryV2).getQuoteAsset(j);
                factoryV2.addQuoteAsset(quoteAsset);
                console.log("Quote asset whitelisted -->", address(quoteAsset));
            }

            uint256[] memory presetList = BipsConfig.getPresetList();
            for (uint256 j; j < presetList.length; j++) {
                BipsConfig.FactoryPreset memory preset = BipsConfig.getPreset(presetList[j]);
                factoryV2.setPreset(
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

            factoryV2.transferOwnership(deployment.multisig);
            vm.stopBroadcast();
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
