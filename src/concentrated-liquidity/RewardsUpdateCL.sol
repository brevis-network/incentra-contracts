// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

abstract contract RewardsUpdateCL is TotalFee, RewardsStorage {
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    ConfigCL public config;
    uint64 public dataChainId; // chain id of the data source

    // For each app ID and each epoch, tracks the last earner from the last proof segment.
    mapping(uint8 => mapping(uint32 => address)) internal _lastDirectEarnerOfLastSegment;
    mapping(address => mapping(uint32 => address)) internal _lastIndirectEarnerOfLastSegment;

    function _initConfig(ConfigCL calldata cfg, IBrevisProof _brevisProof, bytes32[] calldata vks, uint64 _dataChainId)
        internal
    {
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
        dataChainId = _dataChainId;
    }

    // ----- external functions -----

    // _appOutput is 1(totalfee app id), poolAddr, epoch, t0, t1
    function updateTotalFee(bytes calldata proof, bytes calldata appOutput) external onlyRole(REWARD_UPDATER_ROLE) {
        (, uint8 appId) = _checkProofAndGetAppId(proof, appOutput);
        require(appId == 1, "invalid app id");
        address poolAddr = address(bytes20(appOutput[1:21]));
        require(poolAddr == config.poolAddr, "mismatch pool addr");
        _updateFee(appOutput[21:]);
    }

    function getCampaignRewardConfig() public view returns (AddrAmt[] memory) {
        return config.rewards;
    }

    // ----- internal functions -----

    function _getDataChainId() internal view override returns (uint64) {
        return dataChainId;
    }

    function _getHeaderSize(uint8 appId) internal pure override returns (uint256) {
        if (appId == 2) { // direct
            return 32; // uint128 t0fee + uint128 t1fee
        } else if (appId == 3) { // indirect
            return 20; // address indirect
        } else {
            revert("invalid app id");
        }
    }

    function _getSizePerEarner() internal view override returns (uint256) {
        return 20 + 16 * tokens.length; // address + uint128 * numTokens
    }

    // update rewards map w/ zk proof,
    // if _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    // if _appOutput is x(indirect reward app id), indirect addr, [earner:amt u128:amt u128]
    function _updateRewards(
        uint8 appId,
        uint32 epoch,
        bytes calldata appOutputWithoutAppIdEpoch,
        bool enumerable,
        uint256 startEarnerIndex,
        uint256 endEarnerIndex
    ) internal override returns (bool allEarnersProcessed) {
        require(appId > 1, "invalid app id");
        if (appId == 2) {
            return _addDirectRewards(
                appId, epoch, appOutputWithoutAppIdEpoch, enumerable, startEarnerIndex, endEarnerIndex
            );
        } else {
            // indirect rewards
            return _addIndirectRewards(
                appId, epoch, appOutputWithoutAppIdEpoch, enumerable, startEarnerIndex, endEarnerIndex
            );
        }
    }

    // parse circuit output, check and add new reward to total
    // epoch, totalFee0, totalFee1, [usr,amt1,amt2..]
    function _addDirectRewards(
        uint8 appId,
        uint32 epoch,
        bytes calldata appOutputWithoutAppIdEpoch,
        bool enumerable,
        uint256 startEarnerIndex,
        uint256 endEarnerIndex
    ) internal returns (bool allEarnersProcessed) {
        uint128 t0fee = uint128(bytes16(appOutputWithoutAppIdEpoch[0:16]));
        uint128 t1fee = uint128(bytes16(appOutputWithoutAppIdEpoch[16:32]));
        Fee memory fee = totalFees[epoch];
        require(fee.token0Amt == t0fee, "token0 fee mismatch");
        require(fee.token1Amt == t1fee, "token1 fee mismatch");

        uint256 numTokens = tokens.length;
        uint256[] memory newTokenRewards = new uint256[](numTokens);
        uint256 headerSize = _getHeaderSize(appId);
        address lastEarner = _lastDirectEarnerOfLastSegment[appId][epoch];

        for (uint256 earnerIndex = startEarnerIndex; earnerIndex <= endEarnerIndex; earnerIndex++) {
            uint256 offset = headerSize + _getSizePerEarner() * earnerIndex;
            address earner = address(bytes20(appOutputWithoutAppIdEpoch[offset:(offset + 20)]));
            // skip empty address placeholders for the rest of array
            if (earner == address(0)) {
                allEarnersProcessed = true;
                break;
            }
            require(lastEarner < earner, "earner addresses not sorted");
            lastEarner = earner;
            uint256[] memory newRewards = new uint256[](numTokens);
            for (uint256 i = 0; i < numTokens; i += 1) {
                uint256 amtPos = offset + 20 + 16 * i;
                uint256 amount = uint128(bytes16(appOutputWithoutAppIdEpoch[amtPos:(amtPos + 16)]));
                _rewards.add(earner, tokens[i], amount, enumerable);
                newTokenRewards[i] += amount;
                newRewards[i] = amount;
            }
            emit RewardsAdded(appId, epoch, earner, newRewards);
        }
        _lastDirectEarnerOfLastSegment[appId][epoch] = lastEarner;

        for (uint256 i = 0; i < numTokens; i += 1) {
            tokenCumulativeRewards[tokens[i]] += newTokenRewards[i];
        }
        return allEarnersProcessed;
    }

    // appOutputWithoutAppIdEpoch is epoch, indirect contract, [usr,amt1,amt2..]
    function _addIndirectRewards(
        uint8 appId,
        uint32 epoch,
        bytes calldata appOutputWithoutAppIdEpoch,
        bool enumerable,
        uint256 startEarnerIndex,
        uint256 endEarnerIndex
    ) internal returns (bool allEarnersProcessed) {
        address indirect = address(bytes20(appOutputWithoutAppIdEpoch[0:20]));
        uint256 numTokens = tokens.length;
        uint256[] memory newTokenRewards = new uint256[](numTokens);
        uint256 headerSize = _getHeaderSize(appId);
        address lastEarner = _lastIndirectEarnerOfLastSegment[indirect][epoch];

        for (uint256 earnerIndex = startEarnerIndex; earnerIndex <= endEarnerIndex; earnerIndex++) {
            uint256 offset = headerSize + _getSizePerEarner() * earnerIndex;
            address earner = address(bytes20(appOutputWithoutAppIdEpoch[offset:(offset + 20)]));
            // skip empty address placeholders for the rest of array
            if (earner == address(0)) {
                allEarnersProcessed = true;
                break;
            }
            require(lastEarner < earner, "earner addresses not sorted");
            lastEarner = earner;
            uint256[] memory newRewards = new uint256[](numTokens);
            for (uint256 i = 0; i < numTokens; i += 1) {
                uint256 amtPos = offset + 20 + 16 * i;
                uint256 amount = uint128(bytes16(appOutputWithoutAppIdEpoch[amtPos:(amtPos + 16)]));
                _rewards.add(earner, tokens[i], amount, enumerable);
                newTokenRewards[i] += amount;
                newRewards[i] = amount;
            }
            emit RewardsAdded(appId, epoch, earner, newRewards);
        }
        _lastIndirectEarnerOfLastSegment[indirect][epoch] = lastEarner;

        for (uint256 i = 0; i < numTokens; i += 1) {
            tokenCumulativeRewards[tokens[i]] += newTokenRewards[i];
        }
        return allEarnersProcessed;
    }
}
