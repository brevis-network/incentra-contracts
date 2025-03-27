// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./EnumerableNestedMap.sol";
import "../TotalFee.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

struct AddrAmt {
    address token;
    uint256 amount;
}

contract RewardsSubmission is TotalFee {
    using EnumerableNestedMap for EnumerableNestedMap.UserTokenAmountMap;

    event RewardsAdded(address indexed user, AddrAmt[] newRewards);

    address[] public tokens; // addr list of reward tokens
    // user -> token -> cumulative rewards
    EnumerableNestedMap.UserTokenAmountMap private rewards;

    // token -> total rewards
    mapping(address => uint256) public tokenCumulativeRewards;
    // token -> total claimed amount
    mapping(address => uint256) public tokenClaimedRewards;

    // user -> last attested epoch
    mapping(address => uint32) public lastEpoch;
    // user may opt-in to other projects to earn more rewards
    // indirect contract -> user -> last attested epoch to avoid replay
    mapping(address => mapping(address => uint32)) public indirectEpoch;

    function initTokens(address[] memory _tokens) internal {
        for (uint256 i = 0; i < _tokens.length; i += 1) {
            tokens.push(_tokens[i]);
        }
    }

    // parse circuit output, check and add new reward to total
    // epoch, totalFee0, totalFee1, [usr,amt1,amt2..]
    function addRewards(bytes calldata raw) internal {
        uint32 epoch = uint32(bytes4(raw[0:4]));
        uint128 t0fee = uint128(bytes16(raw[4:20]));
        uint128 t1fee = uint128(bytes16(raw[20:36]));
        Fee memory fee = totalFees[epoch];
        require(fee.token0Amt == t0fee, "token0 fee mismatch");
        require(fee.token1Amt == t1fee, "token1 fee mismatch");
        uint256 numTokens = tokens.length;
        for (uint256 idx = 36; idx < raw.length; idx += 20 + 16 * numTokens) {
            address earner = address(bytes20(raw[idx:idx + 20]));
            // skip empty address placeholders for the rest of array
            if (earner == address(0)) {
                break;
            }
            require(epoch > lastEpoch[earner], "invalid epoch");
            lastEpoch[earner] = epoch;
            AddrAmt[] memory newRewards = new AddrAmt[](numTokens);
            for (uint256 i = 0; i < numTokens; i += 1) {
                uint256 amount = uint128(bytes16(raw[idx + 20 + 16 * i:idx + 20 + 16 * i + 16]));
                uint256 currentAmount = rewards.get(earner, tokens[i]);
                rewards.set(earner, tokens[i], currentAmount + amount);
                tokenCumulativeRewards[tokens[i]] += amount;
                newRewards[i].token = tokens[i];
                newRewards[i].amount = amount;
            }
            emit RewardsAdded(earner, newRewards);
        }
    }

    // raw is epoch, indirect contract, [usr,amt1,amt2..]
    function addIndirectRewards(bytes calldata raw) internal {
        uint32 epoch = uint32(bytes4(raw[0:4]));
        address indirect = address(bytes20(raw[4:24]));
        uint256 numTokens = tokens.length;
        for (uint256 idx = 24; idx < raw.length; idx += 20 + 16 * numTokens) {
            address earner = address(bytes20(raw[idx:idx + 20]));
            // skip empty address placeholders for the rest of array
            if (earner == address(0)) {
                break;
            }
            require(epoch > indirectEpoch[indirect][earner], "invalid epoch");
            indirectEpoch[indirect][earner] = epoch;
            require(epoch >= lastEpoch[earner], "indirect epoch is smaller than epoch");
            if (epoch > lastEpoch[earner]) {
                // update lastEpoch to enforce indirect must be submitted after main
                lastEpoch[earner] = epoch;
            }
            AddrAmt[] memory newRewards = new AddrAmt[](numTokens);
            for (uint256 i = 0; i < numTokens; i += 1) {
                uint256 amount = uint128(bytes16(raw[idx + 20 + 16 * i:idx + 20 + 16 * i + 16]));
                uint256 currentAmount = rewards.get(earner, tokens[i]);
                rewards.set(earner, tokens[i], currentAmount + amount);
                tokenCumulativeRewards[tokens[i]] += amount;
                newRewards[i].token = tokens[i];
                newRewards[i].amount = amount;
            }
            emit RewardsAdded(earner, newRewards);
        }
    }
}
