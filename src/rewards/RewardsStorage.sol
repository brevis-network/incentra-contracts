// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../lib/EnumerableMap.sol";

abstract contract RewardsStorage {
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    address[] public tokens; // addr list of reward tokens
    // user -> token -> cumulative rewards
    EnumerableMap.UserTokenAmountMap internal rewards;

    // token -> total rewards
    mapping(address => uint256) public tokenCumulativeRewards;

    // user -> last attested epoch
    mapping(address => uint32) public lastEpoch;
    // user may opt-in to other projects to earn more rewards
    // indirect contract -> user -> last attested epoch to avoid replay
    mapping(address => mapping(address => uint32)) public indirectEpoch;

    event RewardsAdded(address indexed user, uint256[] newRewards);

    function _initTokens(address[] memory _tokens) internal {
        for (uint256 i = 0; i < _tokens.length; i += 1) {
            tokens.push(_tokens[i]);
        }
    }

    function getTokens() public view returns (address[] memory) {
        return tokens;
    }

    function getRewardAmount(address user, address token) public view returns (uint256) {
        return rewards.get(user, token);
    }
}
