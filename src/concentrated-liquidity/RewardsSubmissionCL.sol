// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BrevisProofApp.sol";
import "../rewards/cross-chain/RewardsMerkle.sol";
import "./RewardsUpdateCL.sol";

// submit campaign rewards on one chain, which will be claimed on another chain
contract RewardsSubmissionCL is BrevisProofApp, RewardsUpdateCL, RewardsMerkle {
    // called by proxy to properly set storage of proxy contract, owner is contract owner (hw or multisig)
    function init(
        ConfigCL calldata cfg,
        IBrevisProof _brv,
        address owner,
        bytes32[] calldata vks,
        address reward_updater
    ) external {
        initOwner(owner);
        _initConfig(cfg, _brv, vks);
        grantRole(REWARD_UPDATER_ROLE, reward_updater);
    }

    // update rewards map w/ zk proof, _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    function updateRewards(bytes calldata _proof, bytes calldata _appOutput, uint32 batchIndex)
        external
        onlyRole(REWARD_UPDATER_ROLE)
    {
        _updateRewards(_proof, _appOutput, true, batchIndex);
    }

    // update rewards map w/ zk proof, _appOutput is x(indirect reward app id), indirect addr, [earner:amt u128:amt u128]
    function updateIndirectRewards(bytes calldata _proof, bytes calldata _appOutput, uint32 batchIndex)
        external
        onlyRole(REWARD_UPDATER_ROLE)
    {
        _updateIndirectRewards(_proof, _appOutput, true, batchIndex);
    }
}
