// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BrevisProofApp.sol";
import "../access/AccessControl.sol";
import "../lib/EnumerableMap.sol";
import "../rewards/RewardsStorage.sol";
import "./TotalFee.sol";

struct ConfigCL {
    address creator;
    uint64 startTime;
    uint32 duration; // how many seconds this campaign is active, end after startTime+duration
    AddrAmt[] rewards; // list of [reward token and total amount]
    address poolAddr; // which pool this campaign is for
}

abstract contract RewardsUpdateCL is BrevisProofApp, TotalFee, RewardsStorage, AccessControl {
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    ConfigCL public config;

    mapping(uint8 => bytes32) public vkMap; // from circuit id to its vkhash

    event EpochUpdated(uint32 epoch, uint32 batchIndex);
    event VkUpdated(uint8 appid, bytes32 vk);

    function _initConfig(ConfigCL calldata cfg, IBrevisProof _brevisProof, bytes32[] calldata vks) internal {
        brevisProof = _brevisProof;
        config = cfg;
        address[] memory _tokens = new address[](cfg.rewards.length);
        for (uint256 i = 0; i < cfg.rewards.length; i++) {
            _tokens[i] = cfg.rewards[i].token;
        }
        _initTokens(_tokens);
        // 1: TotalFee 2: Rewards 3+: Others
        for (uint8 i = 0; i < vks.length; i++) {
            vkMap[i + 1] = vks[i];
        }
    }

    // ----- external functions -----

    // _appOutput is 1(totalfee app id), poolAddr, epoch, t0, t1
    function updateTotalFee(bytes calldata _proof, bytes calldata _appOutput) external onlyRole(REWARD_UPDATER_ROLE) {
        uint8 appid = _checkProof(_proof, _appOutput);
        require(appid == 1, "invalid app id");
        address poolAddr = address(bytes20(_appOutput[1:21]));
        require(poolAddr == config.poolAddr, "mismatch pool addr");
        _updateFee(_appOutput[21:]);
    }

    function setVk(uint8 appid, bytes32 _vk) external onlyOwner {
        vkMap[appid] = _vk;
        emit VkUpdated(appid, _vk);
    }

    // ----- internal functions -----

    // update rewards map w/ zk proof,
    // if _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    // if _appOutput is x(indirect reward app id), indirect addr, [earner:amt u128:amt u128]
    function _updateRewards(
        bytes calldata _proof,
        bytes calldata _appOutput,
        bool enumerable,
        uint32 batchIndex
    ) internal {
        uint8 appid = _checkProof(_proof, _appOutput);
        require(appid > 1, "invalid app id");
        if (appid == 2) {
            _addRewards(_appOutput[1:], enumerable, batchIndex);
        } else {
            // indirect rewards
            _addIndirectRewards(_appOutput[1:], enumerable, batchIndex);
        }
    }

    // parse circuit output, check and add new reward to total
    // epoch, totalFee0, totalFee1, [usr,amt1,amt2..]
    function _addRewards(bytes calldata raw, bool enumerable, uint32 batchIndex) internal {
        uint32 epoch = uint32(bytes4(raw[0:4]));
        uint128 t0fee = uint128(bytes16(raw[4:20]));
        uint128 t1fee = uint128(bytes16(raw[20:36]));
        Fee memory fee = totalFees[epoch];
        require(fee.token0Amt == t0fee, "token0 fee mismatch");
        require(fee.token1Amt == t1fee, "token1 fee mismatch");
        uint256 numTokens = tokens.length;
        for (uint256 idx = 36; idx < raw.length; idx += 20 + 16 * numTokens) {
            address earner = address(bytes20(raw[idx:idx + 20]));
            // skip empty address placeholders for the rest of array
            if (earner == address(0)) {
                break;
            }
            require(epoch > lastEpoch[earner], "invalid epoch");
            lastEpoch[earner] = epoch;
            uint256[] memory newRewards = new uint256[](numTokens);
            for (uint256 i = 0; i < numTokens; i += 1) {
                uint256 amount = uint128(bytes16(raw[idx + 20 + 16 * i:idx + 20 + 16 * i + 16]));
                rewards.add(earner, tokens[i], amount, enumerable);
                tokenCumulativeRewards[tokens[i]] += amount;
                newRewards[i] = amount;
            }
            emit RewardsAdded(earner, newRewards);
        }
        emit EpochUpdated(epoch, batchIndex);
    }

    // raw is epoch, indirect contract, [usr,amt1,amt2..]
    function _addIndirectRewards(bytes calldata raw, bool enumerable, uint32 batchIndex) internal {
        uint32 epoch = uint32(bytes4(raw[0:4]));
        address indirect = address(bytes20(raw[4:24]));
        uint256 numTokens = tokens.length;
        for (uint256 idx = 24; idx < raw.length; idx += 20 + 16 * numTokens) {
            address earner = address(bytes20(raw[idx:idx + 20]));
            // skip empty address placeholders for the rest of array
            if (earner == address(0)) {
                break;
            }
            require(epoch > indirectEpoch[indirect][earner], "invalid epoch");
            indirectEpoch[indirect][earner] = epoch;
            require(epoch >= lastEpoch[earner], "indirect epoch is smaller than epoch");
            if (epoch > lastEpoch[earner]) {
                // update lastEpoch to enforce indirect must be submitted after main
                lastEpoch[earner] = epoch;
            }
            uint256[] memory newRewards = new uint256[](numTokens);
            for (uint256 i = 0; i < numTokens; i += 1) {
                uint256 amount = uint128(bytes16(raw[idx + 20 + 16 * i:idx + 20 + 16 * i + 16]));
                rewards.add(earner, tokens[i], amount, enumerable);
                tokenCumulativeRewards[tokens[i]] += amount;
                newRewards[i] = amount;
            }
            emit RewardsAdded(earner, newRewards);
        }
        emit EpochUpdated(epoch, batchIndex);
    }

    function _checkProof(bytes calldata _proof, bytes calldata _appOutput) internal returns (uint8 appid) {
        appid = uint8(_appOutput[0]);
        _checkBrevisProof(uint64(block.chainid), _proof, _appOutput, vkMap[appid]);
        return appid;
    }
}
