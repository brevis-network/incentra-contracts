// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BrevisProofApp.sol";
import "../access/Whitelist.sol";
import "../rewards/cross-chain/RewardsMerkle.sol";
import "./RewardsUpdateTH.sol";

// submit campaign rewards on one chain, which will be claimed on another chain
contract RewardsSubmissionTH is BrevisProofApp, RewardsUpdateTH, RewardsMerkle {
    // called by proxy to properly set storage of proxy contract, owner is contract owner (hw or multisig)
    function init(ConfigTH calldata cfg, IBrevisProof _brv, address owner, bytes32[] calldata vks) external {
        initOwner(owner);
        _initConfig(cfg, _brv, vks);
    }

    // update rewards map w/ zk proof, _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    function updateRewards(bytes calldata _proof, bytes calldata _appOutput, uint32 batchIndex)
        external
        onlyWhitelisted
    {
        _updateRewards(_proof, _appOutput, true, batchIndex);
    }
}
