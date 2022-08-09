//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITreasury {
    function validatePayout() external;
}

contract HunterFee {
    using SafeMath for uint256;

    IERC20 public hunter;
    address public hunterATreasury;
    address public hunterBTreasury;
    address public dead;
    address public operator;

    constructor(address _hunter, address _hunterATreasury, address _hunterBTreasury, address _operator) {
        hunter = IERC20(_hunter);
        hunterATreasury = _hunterATreasury;
        hunterBTreasury = _hunterBTreasury;
        dead = address(0x000000000000000000000000000000000000dEaD);
        operator = _operator;
    }

    function distribution() external{
        uint256 balance = hunter.balanceOf(address(this));

        if (balance == 0){
            return;
        }

        // hunterATreasury 40%
        hunter.transfer(hunterATreasury, balance.mul(40).div(100));
        // hunterBTreasury 10%
        hunter.transfer(hunterBTreasury, balance.mul(10).div(100));
        // dead 10%
        hunter.transfer(dead, balance.mul(10).div(100));
        // operator 40%
        hunter.transfer(operator, balance.mul(40).div(100));

        ITreasury(hunterATreasury).validatePayout();
        ITreasury(hunterBTreasury).validatePayout();
    }
}