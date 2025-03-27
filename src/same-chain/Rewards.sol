// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../AddRewards.sol";
import "../lib/EnumerableMap.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

abstract contract Rewards is AddRewards {
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    event RewardsClaimed(address indexed user, AddrAmt[] claimedRewards);

    // user -> token -> claimed amount
    mapping(address => mapping(address => uint256)) public claimed;

    function _claim(address earner, address to) internal {
        AddrAmt[] memory claimedRewards = new AddrAmt[](tokens.length);
        bool hasUnclaimed = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            address erc20 = tokens[i];
            uint256 tosend = rewards.get(earner, erc20) - claimed[earner][erc20];
            claimed[earner][erc20] = rewards.get(earner, erc20);
            // send token
            if (tosend > 0) {
                IERC20(erc20).transfer(to, tosend);
                tokenClaimedRewards[erc20] += tosend;
                hasUnclaimed = true;
            }
            claimedRewards[i].token = erc20;
            claimedRewards[i].amount = tosend;
        }
        require(hasUnclaimed, "no unclaimed rewards");
        emit RewardsClaimed(earner, claimedRewards);
    }
}
