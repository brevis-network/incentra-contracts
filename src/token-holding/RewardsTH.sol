// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import "../lib/EnumerableMap.sol";
import "../rewards/RewardsStorage.sol";
import "../rewards/same-chain/RewardsClaim.sol";

abstract contract RewardsTH is RewardsStorage, RewardsClaim {
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    // parse circuit output, check and add new reward to total
    // epoch, [usr,amt1,amt2..]
    function _addRewards(bytes calldata raw) internal {
        uint32 epoch = uint32(bytes4(raw[0:4]));
        uint256 numTokens = tokens.length;
        for (uint256 idx = 4; idx < raw.length; idx += 20 + 16 * numTokens) {
            address earner = address(bytes20(raw[idx:idx + 20]));
            // skip empty address placeholders for the rest of array
            if (earner == address(0)) {
                break;
            }
            require(epoch > lastEpoch[earner], "invalid epoch");
            lastEpoch[earner] = epoch;
            uint256[] memory newRewards = new uint256[](numTokens);
            for (uint256 i = 0; i < numTokens; i += 1) {
                uint256 amount = uint128(bytes16(raw[idx + 20 + 16 * i:idx + 20 + 16 * i + 16]));
                rewards.add(earner, tokens[i], amount, false);
                newRewards[i] = amount;
            }
            emit RewardsAdded(earner, newRewards);
        }
    }
}
