//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/*
    @title OracleLib
    @author PKerty
    @notice This library is used to check the Chainlink Oracle for stale data
    @notice If a price stales, the DSEngine will be halted to avoid a break in
        the health factor
    */

import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    
    error OracleLib__StaledPrice();


    uint256 private constant TIMEOUT = 3 hours;
    
    function staleCheckLatestRoundData(AggregatorV3Interface aggregator) public view returns (uint80, int256, uint256, uint256, uint80) {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = aggregator.latestRoundData();
        uint256 secondsSice = block.timestamp - startedAt;
        if(secondsSice > TIMEOUT) {
            revert OracleLib__StaledPrice();           
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
