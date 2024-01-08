// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/*
    @title Decentralized Stable Coin - DSC
    @author PKerty
    Collateral: wETH & wBTC
    Minting: Algorithmic
    Relative Stability: Pegged to US dollar

    It's meant to be governed by the Decentralized Stable Engine - DSE. This
    is only the ERC-20 implementation of our system
*/
contract DSCoin is ERC20Burnable, Ownable {
    error DSCoin__MustBeGreaterThanZero();
    error DSCoin__NotEnoughBalance();
    error DSCoin__NotZeroAddress();

    constructor() ERC20("DSCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DSCoin__MustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert DSCoin__NotEnoughBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DSCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DSCoin__MustBeGreaterThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
