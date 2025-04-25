// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../rewards/cross-chain/RewardsMerkle.sol";
import "./RewardsUpdateTH.sol";

// submit campaign rewards on one chain, which will be claimed on another chain
contract RewardsSubmissionTH is RewardsUpdateTH, RewardsMerkle {
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

    // ----- internal functions -----

    function _useEnumerableMap() internal pure override returns (bool) {
        return true;
    }
}
