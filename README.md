# Incentra Contracts

## Contract Types

### Same-chain reward submission and claim

Main contracts: `CampaignXX.sol`, examples:
- `CampaignCL.sol`: concentrated liquidity campaign
- `CampaignTH.sol`: token holding campaign

### Cross-chain reward submission and claim

To reduce gas cost of campaign on an expensive chain (e.g., Ethereum), submit zk attested rewards on another chain (e.g., Arbitrum), then bridge the merkle root of all rewards back to the campaign chain.

- Rewards submission contract: `RewardsSubmissionXX.sol`, e.g., `RewardsSubmissionCL.sol`
- Rewards claim contract: [`RewardsClaim.sol`](./src/rewards/cross-chain/RewardsClaim.sol)

## Concentrated Liquidity
- CampaignCL: main contract, accept zk attested rewards and user claim, inherits Rewards which inherits TotalFee
- Rewards: keep track of per user per token reward amount and claimed. also tracks each user's last attested epoch. indirect rewards(eg. ALM) has additional map of contract-user-epoch
- TotalFee: epoch-fee map