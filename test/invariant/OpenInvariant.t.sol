/*

What we have to do.

1. Find Invariants
    a. Total supply of DSC must be lower than the total value of Collateral
    b. Getter view functions shall never revert
    */

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "@script/DeployDSC.s.sol";
import {DSEngine} from "@src/DSEngine.sol";
import {DSCoin} from "@src/DSCoin.sol";
import {HelperConfig} from "@script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*
contract InvarantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSEngine engine;
    DSCoin DSC;
    HelperConfig config;
    address wETH;
    address wBTC;


    function setUp() external {
        deployer = new DeployDSC();
        (DSC, engine, config) = deployer.run();
        (,,wETH, wBTC,) = config.activeNetworkConfig();
        targetContract(address(engine));
    }

    function invariant_ProtocolDSCSupplyGreaterThanCollateralValue() public view {
        //Get the value of all the collateral of the protocol and compare it with the DSC supply
        uint256 totalSupply = DSC.totalSupply();
        uint256 totalwETH = IERC20(wETH).balanceOf(address(engine));
        uint256 totalwBTC = IERC20(wBTC).balanceOf(address(engine));

        uint256 totalwETHValue = engine.getUSDValue(wETH, totalwETH); 
        uint256 totalwBTCValue = engine.getUSDValue(wBTC, totalwBTC);
        
        assert(totalwETHValue + totalwBTCValue >= totalSupply);
    }
}

*/
