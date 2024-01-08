// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";

import {DSCoin} from "@src/DSCoin.sol";
import {DSEngine} from "@src/DSEngine.sol";
import {HelperConfig} from "@script/HelperConfig.s.sol";


contract DeployDSC is Script {
    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function setUp() public {}

    function run() external returns (DSCoin, DSEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wETH_USDPriceFeed, address wBTC_USDPriceFeed, address wETH, address wBTC, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        tokenAddress = [wETH, wBTC];
        priceFeedAddress = [wETH_USDPriceFeed, wBTC_USDPriceFeed];
        vm.startBroadcast(deployerKey);
        DSCoin DSC = new DSCoin();
        DSEngine engine = new DSEngine(tokenAddress, priceFeedAddress, address(DSC));
        DSC.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (DSC, engine, helperConfig);
    }
}
