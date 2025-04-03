// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../lib/EnumerableMap.sol";

struct AddrAmt {
    address token;
    uint256 amount;
}

abstract contract RewardsStorage {
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    // 82531167a8e1b9df58acc5f105c04f72009b9ff406bf7d722b527a2f45d626ae
    bytes32 public constant REWARD_UPDATER_ROLE = keccak256("reward_updater");

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

    function viewTotalRewards(address earner) external view returns (AddrAmt[] memory) {
        AddrAmt[] memory ret = new AddrAmt[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            ret[i] = AddrAmt({token: tokens[i], amount: rewards.get(earner, tokens[i])});
        }
        return ret;
    }
}
