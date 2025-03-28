// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

import "./AddRewards.sol";
import "../BrevisProofApp.sol";
import "../lib/EnumerableMap.sol";
import "../access/Whitelist.sol";
import "../rewards/cross-chain/RewardsMerkle.sol";

struct AddrAmt {
    address token;
    uint256 amount;
}

struct Config {
    address creator;
    uint64 startTime;
    uint32 duration; // how many seconds this campaign is active, end after startTime+duration
    AddrAmt[] rewards; // list of [reward token and total amount]
    address pooladdr; // which pool this campaign is for
}

// submit campaign rewards on chain Y
contract RewardsSubmissionCL is AddRewards, RewardsMerkle, BrevisProofApp {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    Config public config;
    mapping(uint8 => bytes32) public vkMap; // from circuit id to its vkhash

    // called by proxy to properly set storage of proxy contract, owner is contract owner (hw or multisig)
    function init(Config calldata cfg, IBrevisProof _brv, address owner, bytes32[] calldata vks) external {
        initOwner(owner);
        address[] memory _tokens = new address[](cfg.rewards.length);
        for (uint256 i = 0; i < cfg.rewards.length; i++) {
            _tokens[i] = cfg.rewards[i].token;
        }
        _initTokens(_tokens);
        config = cfg;
        brevisProof = _brv;
        // 1: TotalFee 2: Rewards 3+: Others
        for (uint8 i = 0; i < vks.length; i++) {
            vkMap[i + 1] = vks[i];
        }
    }

    // ----------- Rewards Submission -----------
    // _appOutput is 1(totalfee app id), pooladdr, epoch, t0, t1
    function updateTotalFee(bytes calldata _proof, bytes calldata _appOutput) external onlyWhitelisted {
        require(state == State.RewardsSubmission, "invalid state");
        _checkProof(_proof, _appOutput);
        address pooladdr = address(bytes20(_appOutput[1:21]));
        require(pooladdr == config.pooladdr, "mismatch pool addr");
        _updateFee(_appOutput[21:]);
    }

    // update rewards map w/ zk proof, _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    function updateRewards(bytes calldata _proof, bytes calldata _appOutput) external onlyWhitelisted {
        require(state == State.RewardsSubmission, "invalid state");
        _checkProof(_proof, _appOutput);
        _addRewards(_appOutput[1:], true);
    }

    // update rewards map w/ zk proof, _appOutput is x(indirect reward app id), indirect addr, [earner:amt u128:amt u128]
    function updateIndirectRewards(bytes calldata _proof, bytes calldata _appOutput) external onlyWhitelisted {
        require(state == State.RewardsSubmission, "invalid state");
        _checkProof(_proof, _appOutput);
        _addIndirectRewards(_appOutput[1:], true);
    }

    function _checkProof(bytes calldata _proof, bytes calldata _appOutput) internal {
        uint8 appid = uint8(_appOutput[0]);
        _checkBrevisProof(uint64(block.chainid), _proof, _appOutput, vkMap[appid]);
    }

    function setVk(uint8 appid, bytes32 _vk) external onlyOwner {
        vkMap[appid] = _vk;
    }
}
