//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

import {DeployDSC} from "@script/DeployDSC.s.sol";
import {DSCoin} from "@src/DSCoin.sol";
import {DSEngine} from "@src/DSEngine.sol";
import {HelperConfig} from "@script/HelperConfig.s.sol";
import {ERC20Mock} from  "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockV3Aggregator} from "@test/mocks/MockV3Agreggator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";

contract DSEngineTest is Test {

    DeployDSC deployer;
    DSCoin DSC;
    DSEngine engine;
    HelperConfig helperConfig;
    address wETH_USDPriceFeed; 
    address wETH;
    address wBTC_USDPriceFeed; 
    address wBTC;

    address public USER = makeAddr("User");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    uint256 public constant USER_MINTED_AMOUNT = 10 ether;
    
    function setUp() public {
        deployer = new DeployDSC();
        (DSC, engine, helperConfig) = deployer.run();
        (wETH_USDPriceFeed,
         wBTC_USDPriceFeed,
         wETH,
         wBTC, ) = helperConfig.activeNetworkConfig();

         ERC20Mock(wETH).mint(USER, USER_MINTED_AMOUNT);
    } 

    ////////////////////
    // Const Tests    //
    ////////////////////

    address[] public tokenAddress;
    address[] public priceFeedAddress;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddress.push(wETH);
        priceFeedAddress.push(wETH_USDPriceFeed);
        priceFeedAddress.push(wBTC_USDPriceFeed);

        vm.expectRevert(DSEngine.DSEngine__MissingTokenOrPriceFeed.selector);
        new DSEngine(tokenAddress, priceFeedAddress, address(DSC));

    }



    ////////////////////
    // PriceFeed tests//
    ////////////////////

    function testGetUsdValue() public {
        uint256 wETHAmount  = 15e18;
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = engine.getUSDValue(wETH, wETHAmount);
        assertEq(actualUSD, expectedUSD);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount  = 100 ether;
        uint256 expectedWETH = 0.05 ether;
        uint256 actualWETH = engine.getTokenAmountFromUsd(wETH, usdAmount);
        assertEq(expectedWETH, actualWETH);
    }

    ////////////////////////////
    // depositCollateral tests//
    ////////////////////////////
    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSEngine.DSEngine__MustBeGreaterThanZero.selector);
        engine.depositCollateral(wETH, 0);
        vm.stopPrank();
    }

    function testRevertsIfCollateralIsNotAllowed() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSEngine.DSEngine__tokenNotAllowed.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
    }

    function testRevertsIfDepositCollateralTransferFromFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom failedTransferFrom = new MockFailedTransferFrom();
        tokenAddress = [address(failedTransferFrom)];
        priceFeedAddress = [wETH_USDPriceFeed];
        vm.prank(owner);
        DSEngine mockEngine = new DSEngine(tokenAddress, priceFeedAddress, address(failedTransferFrom));
        failedTransferFrom.mint(USER, AMOUNT_COLLATERAL);
        vm.prank(owner);
        failedTransferFrom.transferOwnership(address(mockEngine));

        vm.startPrank(USER);
        ERC20Mock(address(failedTransferFrom)).approve(address(mockEngine), AMOUNT_COLLATERAL);
        
        vm.expectRevert(DSEngine.DSEngine__TransferFailed.selector);
        mockEngine.depositCollateral(address(failedTransferFrom), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }



    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(wETH, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }



    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDSCMinted, 
         uint256 collateralValueInUSD) = engine.getAccountInformation(USER);
        uint256 expectedTotalDSCMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(wETH, collateralValueInUSD);
        assertEq(totalDSCMinted, expectedTotalDSCMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }
    ////////////////////////////
    // MINT DSC tests         //
    ////////////////////////////
    
    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(wETH, AMOUNT_COLLATERAL, USER_MINTED_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testMintDSCRevertsIfHealthCheckFails() public {
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(DSEngine.DSEngine__BreaksHealthFactor.selector, 0));
        engine.mintDSC(AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
    
    function testDepositCollateralAndMintDSCRevertsIfHealthCheckFails() public {
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert();
        uint256 amountToMint = 11000 ether;
        engine.depositCollateralAndMintDSC(wETH, AMOUNT_COLLATERAL, amountToMint);
    }

    function testDepositCollateralAndMintDSC() public depositedCollateralAndMintedDsc {
        assertEq(USER_MINTED_AMOUNT, DSC.balanceOf(USER));
    }   


    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSEngine.DSEngine__MustBeGreaterThanZero.selector);
        engine.mintDSC(0);
    }
    ////////////////////////////
    // Withdraw tests         //
    ////////////////////////////
    function testWithdrawRevertsIfAmountToWithdrawIsZero() public {
        vm.prank(USER);
        vm.expectRevert(DSEngine.DSEngine__MustBeGreaterThanZero.selector);
        engine.withdrawCollateral(wETH,0);
    }

    function testWithdrawRevertsIfTokenIsNotAllowed() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSEngine.DSEngine__tokenNotAllowed.selector);
        engine.withdrawCollateral(address(ranToken), AMOUNT_COLLATERAL);
    }

    function testWithdrawRevertsIfHealthCheckFails() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert();
        engine.withdrawCollateral(wETH, AMOUNT_COLLATERAL);
    }
    
    function testRevertsIfTransferFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDSC = new MockFailedTransfer();
        tokenAddress = [address(mockDSC)];
        priceFeedAddress = [wETH_USDPriceFeed];
        vm.prank(owner);
        DSEngine mockEngine = new DSEngine(tokenAddress, priceFeedAddress, address(mockDSC));
        mockDSC.mint(USER, AMOUNT_COLLATERAL);
        vm.prank(owner);
        mockDSC.transferOwnership(address(mockEngine));
        vm.startPrank(USER);
        ERC20Mock(address(mockDSC)).approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateral(address(mockDSC), AMOUNT_COLLATERAL);


        vm.expectRevert(DSEngine.DSEngine__TransferFailed.selector);
        mockEngine.withdrawCollateral(address(mockDSC), AMOUNT_COLLATERAL);
        vm.stopPrank();

    }

    ////////////////////
    // Burn DSC Tests //
    ////////////////////
    function testBurnRevertsIfAmountToBurnIsZero() public {
        vm.prank(USER);
        vm.expectRevert(DSEngine.DSEngine__MustBeGreaterThanZero.selector);
        engine.burnDSC(0);
    }

    function testBurnRevertsIfGreaterThanUserHas() public {
        vm.startPrank(USER);
        vm.expectRevert();
        engine.burnDSC(AMOUNT_COLLATERAL);
    }  

    function testCanBurnDSC() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        DSC.approve(address(engine), USER_MINTED_AMOUNT);

        engine.burnDSC(USER_MINTED_AMOUNT);
        vm.stopPrank();

        uint256 balance = DSC.balanceOf(USER);
        assertEq(0, balance);
    }


    ///////////////////////////////////////
    // WithrawCollateralAndBurnDSC tests //
    ///////////////////////////////////////

    function testMustWithdrawMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        DSC.approve(address(engine), USER_MINTED_AMOUNT);
        vm.expectRevert(DSEngine.DSEngine__MustBeGreaterThanZero.selector);
        engine.withdrawCollateralWithDSC(wETH, 0, USER_MINTED_AMOUNT);
        vm.stopPrank();
    }
    function testCanWithdrawDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDSC(wETH, AMOUNT_COLLATERAL, USER_MINTED_AMOUNT);
        DSC.approve(address(engine), USER_MINTED_AMOUNT);
        engine.withdrawCollateralWithDSC(wETH, AMOUNT_COLLATERAL, USER_MINTED_AMOUNT);
        vm.stopPrank();

        uint256 balance = DSC.balanceOf(USER);
        assertEq(0, balance);
    }

    /////////////////////////////////
    // Health Factor Tests         //
    /////////////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 1000 ether;
        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        assertEq(expectedHealthFactor, actualHealthFactor);
    }

    function testHealthFactorCanBeLowerThanZero() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 1.8e8;
        MockV3Aggregator(wETH_USDPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);

        assertEq(0.9 ether, userHealthFactor);
    }
    
    /////////////////////////
    //Liquidity Tests      //   
    /////////////////////////
    function testMustImproveHealthFactorOnLiquidation() public {
        MockMoreDebtDSC mockDSC = new MockMoreDebtDSC(wETH_USDPriceFeed);
        tokenAddress = [address(wETH)];
        priceFeedAddress = [wETH_USDPriceFeed];
        address owner = msg.sender;

        vm.prank(owner);
        DSEngine mockEngine = new DSEngine(tokenAddress, priceFeedAddress, address(mockDSC));

        mockDSC.transferOwnership(address(mockEngine));
        uint256 amountToMint = 100 ether;
        vm.startPrank(USER);
        ERC20Mock(wETH).approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateralAndMintDSC(wETH, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        uint256 collateralToCover = 1 ether;
        ERC20Mock(wETH).mint(LIQUIDATOR, collateralToCover);
    
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wETH).approve(address(mockEngine), collateralToCover);
        uint256 debtToCover = 10 ether;
        mockEngine.depositCollateralAndMintDSC(wETH, collateralToCover, amountToMint);
        mockDSC.approve(address(mockEngine), debtToCover);

        //ACT

        int256 ethUsdUpdatedPrice = 18e8;
        MockV3Aggregator(wETH_USDPriceFeed).updateAnswer(ethUsdUpdatedPrice);


        vm.expectRevert(DSEngine.DSEngine__HealthFactorNotImproved.selector);
        mockEngine.liquidate(wETH, USER, debtToCover);
        vm.stopPrank();
    }
}
