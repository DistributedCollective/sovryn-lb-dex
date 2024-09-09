pragma solidity ^0.8.20;

contract IDeployment {
    struct Deployment {
        address factoryV1;
        address factoryV2;
        address feeRecipient;
        address lbPairImplementation;
        address lbPairUpgradeableBeacon;
        address owner;
        address proxyAdmin;
        address quoter;
        address routerV2;
        address wNative;
    }
}