// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ClaimEventHub {
    event RewardsClaimed(
        address indexed campaign, address indexed earner, uint256[] newAmounts, uint256[] cumulativeAmounts
    );

    function emitRewardsClaimed(address earner, uint256[] memory newAmounts, uint256[] memory cumulativeAmounts)
        external
    {
        emit RewardsClaimed(msg.sender, earner, newAmounts, cumulativeAmounts);
    }
}
