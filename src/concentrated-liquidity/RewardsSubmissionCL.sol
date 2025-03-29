// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

import "../BrevisProofApp.sol";
import "../lib/EnumerableMap.sol";
import "../access/Whitelist.sol";
import "../rewards/cross-chain/RewardsMerkle.sol";
import "./RewardsUpdate.sol";

// submit campaign rewards on one chain, which will be claimed on another chain
contract RewardsSubmissionCL is BrevisProofApp, RewardsUpdate, RewardsMerkle {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    // called by proxy to properly set storage of proxy contract, owner is contract owner (hw or multisig)
    function init(Config calldata cfg, IBrevisProof _brv, address owner, bytes32[] calldata vks) external {
        initOwner(owner);
        _initConfig(cfg, _brv, vks);
    }

    // update rewards map w/ zk proof, _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    function updateRewards(bytes calldata _proof, bytes calldata _appOutput) external onlyWhitelisted {
        _updateRewards(_proof, _appOutput, true);
    }

    // update rewards map w/ zk proof, _appOutput is x(indirect reward app id), indirect addr, [earner:amt u128:amt u128]
    function updateIndirectRewards(bytes calldata _proof, bytes calldata _appOutput) external onlyWhitelisted {
        _updateIndirectRewards(_proof, _appOutput, true);
    }
}
