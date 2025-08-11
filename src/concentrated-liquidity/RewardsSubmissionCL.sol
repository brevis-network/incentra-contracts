// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../rewards/cross-chain/RewardsMerkle.sol";
import "./RewardsUpdateCL.sol";

// submit campaign rewards on one chain, which will be claimed on another chain
contract RewardsSubmissionCL is RewardsUpdateCL, RewardsMerkle {
    // called by proxy to properly set storage of proxy contract, owner is contract owner (hw or multisig)
    function init(
        ConfigCL calldata cfg,
        IBrevisProof brv,
        address owner,
        bytes32[] calldata vks,
        uint64 dataChainId,
        address rewardUpdater
    ) external {
        initOwner(owner);
        _initConfig(cfg, brv, vks, dataChainId);
        _grantRole(REWARD_UPDATER_ROLE, rewardUpdater);
    }

    // ----- internal functions -----

    function _useEnumerableMap() internal pure override returns (bool) {
        return true;
    }
}
