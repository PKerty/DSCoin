// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DSCoin} from "./DSCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/*
    @title Decentralized Stable Engine
    @author PKerty
    
    System with minimalistic design. Objective is to keep 1 DSCoin = 1 USD.
    Our sys shall be "overcollateralized".
    Collateral >= DSC

    @notice This contract is the core for DSC System. On charge of minting/burning
    & Deposit/Withdrawal collateral
    @notice Inspired by MakerDao DSS (DAI) system.
*/

contract DSEngine is ReentrancyGuard {
    //////////////////
    // Errors      //
    /////////////////
    error DSEngine__MustBeGreaterThanZero();
    error DSEngine__MissingTokenOrPriceFeed();
    error DSEngine__tokenNotAllowed();

    error DSEngine__TransferFailed();
    error DSEngine__BreaksHealthFactor(uint256 healthFactor);

    error DSEngine__MintFailed();

    error DSEngine__HealthFactorNotBroken();
    error DSEngine__HealthFactorNotImproved();

    //////////////////
    //State vars   //
    /////////////////
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private s_userToMintedDSC;
    mapping(address token => address priceFeed) private s_priceFeeds;
    address[] private s_collateralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MAX_HEALTH_FACTOR = type(uint256).max;
    DSCoin private immutable i_DSCoin;

    //////////////////
    // Events      //
    /////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralWidthrawn(address indexed from, address indexed to, address indexed token, uint256 amount);
    //////////////////
    // Modifiers   //
    /////////////////
    modifier greaterThanZero(uint256 _toCheck) {
        if (_toCheck <= 0) {
            revert DSEngine__MustBeGreaterThanZero();
        }
        _;
    }

    modifier allowedCollateral(address _collateral) {
        if (s_priceFeeds[_collateral] == address(0)) {
            revert DSEngine__tokenNotAllowed();
        }
        _;
    }
    //////////////////
    // Functions   //
    /////////////////

    constructor(
        address[] memory tokens,
        address[] memory priceFeeds, //USDPriceFeed
        address _DSCoin
    ) {
        if (tokens.length != priceFeeds.length) {
            revert DSEngine__MissingTokenOrPriceFeed();
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            s_priceFeeds[tokens[i]] = priceFeeds[i];
            s_collateralTokens.push(tokens[i]);
        }
        i_DSCoin = DSCoin(_DSCoin);
    }

    //////////////////
    // External Fns//
    /////////////////
    function depositCollateralAndMintDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /*
        @param collateralTokenAddress -> The address of the token to deposit as 
        collateral
        @param amountCollateral -> Amount of collateral to deposit
        */
    function depositCollateral(address collateralTokenAddress, uint256 amountCollateral)
        public
        greaterThanZero(amountCollateral)
        allowedCollateral(collateralTokenAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][collateralTokenAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, collateralTokenAddress, amountCollateral);
        bool success = IERC20(collateralTokenAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSEngine__TransferFailed();
        }
    }
    /*
        @notice follows CEI
        @param amountDSCToMint -> Amount of DSCoin to mint
        @notice they must give more value in collateral that value minted

    */

    function mintDSC(uint256 amountDSCToMint) public greaterThanZero(amountDSCToMint) nonReentrant {
        s_userToMintedDSC[msg.sender] += amountDSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_DSCoin.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSEngine__MintFailed();
        }
    }

    /*
        @param amountDSCToBurn -> Amount of DSCoin to burn
        @param amountCollateral -> Amount of collateral to withdraw
        @param tokenCollateralAddress -> The address of the token to withdraw as collateral
    */

    function withdrawCollateralWithDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn) external {
        burnDSC(amountDSCToBurn);
        withdrawCollateral(tokenCollateralAddress, amountCollateral);
        //redeemCollateral already checks healthFactor
    }

    function withdrawCollateral(address tokenCollateralAddress, uint256 amountCollateral)
    public greaterThanZero(amountCollateral) allowedCollateral(tokenCollateralAddress) nonReentrant {
        _withdrawCollateral(tokenCollateralAddress, amountCollateral ,msg.sender, msg.sender );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDSC(uint256 amount) public greaterThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);
        // @dev Not probable to happen
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    /*
        @notice If someone is almost undercollateralized, you can liquidate them!
        @param collateral -> The address of the collateral token to liquidate
        @param user -> The address of the user to liquidate since he broke his health factor
        @param debtToCover -> The amount of DSC to burn to improve the broken Health Factor

        @notice You can partially liquidate the user
        @notice You get a liquidation bonus for taking the debt, around 10%
        @notice This function working asumes the protocol will be 200% overcollateralized in order for this to work
        @notice A known bug would be if the protocol were 100% or less collateralized, then the incentive is gone
        @notice If price of collateral lummeted before anyone could be liquidated, this brokes.
        @TODO: add a feature to liquidate in the event the protocol is insolvent
    */
    function liquidate(address collateral, address user, uint256 debtToCover) 
    external greaterThanZero(debtToCover) nonReentrant{
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSEngine__HealthFactorNotBroken();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusAmount = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralAmount = tokenAmountFromDebtCovered + bonusAmount;
        
        _withdrawCollateral(collateral, totalCollateralAmount ,user, msg.sender );
        _burnDSC(debtToCover, user, msg.sender);
        uint256 finalUserHealthFactor = _healthFactor(user);
        if(finalUserHealthFactor <= startingUserHealthFactor) {
            revert DSEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }


    function getHealthFactor(address user) external view returns (uint256){
        return _healthFactor(user);
    }

    //////////////////
    // Internal Fns //
    //////////////////

    function _getAddressInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_userToMintedDSC[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /*
        Returns factor of collateral value divided by minted value. If below 1
        they can get liquidated
        */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAddressInformation(user);
        if(totalDSCMinted == 0) {
            return MAX_HEALTH_FACTOR;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        //1. checkHealthFactor
        //  - if not met, revert

        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _withdrawCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralWidthrawn(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!success) {
            revert DSEngine__TransferFailed();
        }

    }
    // @dev Should check health factor, this is a low-level
    function  _burnDSC(uint256 amountDSCToBurn, address onBehalfOf, address DSCFrom) private {
        s_userToMintedDSC[onBehalfOf] -= amountDSCToBurn;
        bool success = i_DSCoin.transferFrom(DSCFrom, address(this), amountDSCToBurn);
        if(!success) {
            revert DSEngine__TransferFailed();
        }
        i_DSCoin.burn(amountDSCToBurn);

    }
    /////////////////////////////
    // Public & External View //
    ////////////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        address[] memory collateralTokens = s_collateralTokens;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUSDValue(token, amount);
        }
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address user) external view returns(uint256 totalDSCMinted, uint256 collateralValueInUSD) {
        (totalDSCMinted, collateralValueInUSD) = _getAddressInformation(user);
    }

    function getCollateralTokens() public view returns(address[] memory) {
        return s_collateralTokens;

    }

    function getAccountCollateral(address user, address token) public view returns (uint256) {
       return s_collateralDeposited[user][token];
    }

}
