// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// claim all rewards for the user
contract ClaimAll {
    struct CampaignReward {
        address campaignAddr;
        uint256[] cumulativeAmounts;
        uint64 epoch;
        bytes32[] proof;
    }

    // claim all same-chain rewards
    function claimAll(address earner, address[] calldata campaignAddrs) public {
        for (uint256 i = 0; i < campaignAddrs.length; i++) {
            IRewardContract(campaignAddrs[i]).claim(earner);
        }
    }

    // claim all cross-chain rewards
    function claimAll(address earner, CampaignReward[] calldata campaignRewards) public {
        for (uint256 i = 0; i < campaignRewards.length; i++) {
            IRewardContract(campaignRewards[i].campaignAddr).claim(
                earner, campaignRewards[i].cumulativeAmounts, campaignRewards[i].epoch, campaignRewards[i].proof
            );
        }
    }

    // claim all same-chain and cross-chain rewards
    function claimAll(address earner, address[] calldata campaignAddrs, CampaignReward[] calldata campaignRewards)
        external
    {
        claimAll(earner, campaignAddrs);
        claimAll(earner, campaignRewards);
    }
}

interface IRewardContract {
    // claim same-chain rewards, send rewards token to earner
    function claim(address earner) external;

    // claim cross-chain rewards, send rewards token to earner
    function claim(address earner, uint256[] calldata cumulativeAmounts, uint64 _epoch, bytes32[] calldata proof)
        external;
}
