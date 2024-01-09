// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "@script/DeployDSC.s.sol";
import {DSEngine} from "@src/DSEngine.sol";
import {DSCoin} from "@src/DSCoin.sol";
import {HelperConfig} from "@script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@test/mocks/MockV3Agreggator.sol";

contract Handler is Test { 
    DeployDSC deployer;
    DSEngine engine;
    DSCoin DSC;
    ERC20Mock wETH;
    ERC20Mock wBTC;


    address wETHPriceFeed;
    address wBTCPriceFeed;

    address[] addressWithCollateralDeposited;
    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSEngine _engine, DSCoin _DSC) {
        engine = _engine;
        DSC = _DSC;
        address[] memory collateralTokens = engine.getCollateralTokens(); 
        wETH = ERC20Mock(collateralTokens[0]);
        wBTC = ERC20Mock(collateralTokens[1]);
        wETHPriceFeed = engine.getPriceFeed(address(wETH));
        wBTCPriceFeed = engine.getPriceFeed(address(wBTC));
    }

    /*
        This function is used to update the price feed of the wETH and wBTC
        It can break the invariant, but won't be solved in this tutorial.
        Since a plummet in price breaks the protocol, this is what is called a
        known bug.
    function updateCollateralValue(uint96 newValue) public {
        MockV3Aggregator(wETHPriceFeed).updateAnswer(int256(uint256(newValue)));
    }

    */
    function  depositCollateral(uint256 collateralSeed, uint256 amount) public {
        amount = bound(amount,1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(engine), amount);
        engine.depositCollateral(address(collateral), amount);
        vm.stopPrank();
        addressWithCollateralDeposited.push(msg.sender);
        
    }

    function withdrawCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 MAX_COLLATERAL = engine.getAccountCollateral(msg.sender, address(collateral));
        amount = bound(amount, 0, MAX_COLLATERAL);
        if(amount == 0 ) {
            return;
        }
        engine.withdrawCollateral(address(collateral), amount);
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        // In this case we consider revert to fail as false, if not, we should
        // bound the amount to a max tat doesn't break the health factor
        if(addressWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = _getAddressFromSeed(addressSeed);
        (uint256 DSCMinted, uint256 collateralValue) = engine.getAccountInformation(sender);
        int256 maxDSCToMint = (int256(collateralValue)/ 2) - int256(DSCMinted);
        if(maxDSCToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDSCToMint));
        if(amount == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.mintDSC(amount);
        vm.stopPrank();
    }
    //Helpers
    function _getAddressFromSeed(uint256 seed) private view returns (address) {
        return addressWithCollateralDeposited[seed % addressWithCollateralDeposited.length];
    }

    function _getCollateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        if(seed % 2 == 0) {
            return wETH;
        } else {
            return wBTC;
        }
    }
}
