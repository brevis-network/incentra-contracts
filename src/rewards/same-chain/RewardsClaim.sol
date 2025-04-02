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

    event RewardsClaimed(address indexed earner, uint256[] claimedRewards);

    function _claim(address earner, address to) internal {
        uint256[] memory claimedRewards = new uint256[](tokens.length);
        bool hasUnclaimed = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 cumulativeAmount = rewards.get(earner, token);
            uint256 tosend = cumulativeAmount - claimed[earner][token];
            claimed[earner][token] = cumulativeAmount;
            // send token
            if (tosend > 0) {
                IERC20(token).transfer(to, tosend);
                tokenClaimedRewards[token] += tosend;
                hasUnclaimed = true;
            }
            claimedRewards[i] = tosend;
        }
        require(hasUnclaimed, "no unclaimed rewards");
        emit RewardsClaimed(earner, claimedRewards);
    }

    function viewUnclaimedRewards(address earner) external view returns (AddrAmt[] memory) {
        AddrAmt[] memory ret = new AddrAmt[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 tosend = rewards.get(earner, token) - claimed[earner][token];
            ret[i] = AddrAmt({token: token, amount: tosend});
        }
        return ret;
    }
}
