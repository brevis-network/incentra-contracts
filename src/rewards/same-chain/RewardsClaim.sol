// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import "../RewardsStorage.sol";
import "../../lib/EnumerableMap.sol";

// claim campaign rewards on chain X
abstract contract RewardsClaim is RewardsStorage {
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    // user -> token -> claimed amount
    mapping(address => mapping(address => uint256)) public claimed;

    // token -> total claimed amount
    mapping(address => uint256) public tokenClaimedRewards;

    event RewardsClaimed(address indexed user, uint256[] claimedRewards);

    function _claim(address earner, address to) internal {
        uint256[] memory claimedRewards = new uint256[](tokens.length);
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
            claimedRewards[i] = tosend;
        }
        require(hasUnclaimed, "no unclaimed rewards");
        emit RewardsClaimed(earner, claimedRewards);
    }
}
