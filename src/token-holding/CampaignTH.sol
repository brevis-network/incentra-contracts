// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../brevis/BrevisProofApp.sol";
import "../lib/EnumerableMap.sol";
import "../rewards/same-chain/RewardsClaim.sol";
import "../access/AccessControl.sol";
import "./RewardsUpdateTH.sol";

contract CampaignTH is BrevisProofApp, RewardsUpdateTH, RewardsClaim, AccessControl {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    uint64 public constant GRACE_PERIOD = 3600 * 24 * 10; // seconds after campaign end

    // called by proxy to properly set storage of proxy contract, owner is contract owner (hw or multisig)
    function init(
        ConfigTH calldata cfg,
        IBrevisProof brv,
        address owner,
        bytes32[] calldata vks,
        uint64 dataChainId,
        address rewardUpdater
    ) external {
        initOwner(owner);
        _initConfig(cfg, brv, vks, dataChainId);
        grantRole(REWARD_UPDATER_ROLE, rewardUpdater);
    }

    // after grace period, refund all remaining balance to creator
    function refund() external {
        ConfigTH memory cfg = config;
        require(block.timestamp > cfg.startTime + cfg.duration + GRACE_PERIOD, "too soon");
        for (uint256 i = 0; i < cfg.rewards.length; i++) {
            address erc20 = cfg.rewards[i].token;
            IERC20(erc20).safeTransfer(cfg.creator, IERC20(erc20).balanceOf(address(this)));
        }
    }

    // claim reward, send erc20 to earner
    function claim(address earner) external {
        _claim(earner, earner);
    }

    // msg.sender is the earner
    function claimWithRecipient(address to) external {
        _claim(msg.sender, to);
    }

    // update rewards map w/ zk proof, _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    function updateRewards(bytes calldata _proof, bytes calldata _appOutput, uint32 batchIndex)
        external
        onlyRole(REWARD_UPDATER_ROLE)
    {
        _updateRewards(_proof, _appOutput, false, batchIndex);
    }
}
