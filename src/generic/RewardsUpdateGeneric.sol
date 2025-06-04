// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import "../lib/EnumerableMap.sol";
import "../rewards/RewardsStorage.sol";

struct ConfigGeneric {
    address creator;
    uint64 startTime;
    uint32 duration; // how many seconds this campaign is active, end after startTime+duration
    AddrAmt[] rewards; // list of [reward token and total amount]
    bytes32[] extraData; // list of extra circuit output data to check in the contract
}

abstract contract RewardsUpdateGeneric is RewardsStorage {
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    ConfigGeneric public config;
    uint64 public dataChainId; // chain id of the data source

    // For each app ID and each epoch, tracks the last earner from the last proof segment.
    mapping(uint8 => mapping(uint32 => address)) internal _lastEarnerOfLastSegment;

    function getCampaignRewardConfig() public view returns (AddrAmt[] memory) {
        return config.rewards;
    }

    // ----- internal functions -----

    function _initConfig(
        ConfigGeneric calldata cfg,
        IBrevisProof _brevisProof,
        bytes32[] calldata vks,
        uint64 _dataChainId
    ) internal {
        brevisProof = _brevisProof;
        config = cfg;
        address[] memory _tokens = new address[](cfg.rewards.length);
        for (uint256 i = 0; i < cfg.rewards.length; i++) {
            _tokens[i] = cfg.rewards[i].token;
        }
        _initTokens(_tokens);
        for (uint8 i = 0; i < vks.length; i++) {
            vkMap[i + 1] = vks[i];
        }
        dataChainId = _dataChainId;
    }

    function _getDataChainId() internal view override returns (uint64) {
        return dataChainId;
    }

    function _getHeaderSize(uint8) internal view override returns (uint256) {
        return 8 * config.extraData.length;
    }

    function _getSizePerEarner() internal view override returns (uint256) {
        return 20 + 16 * tokens.length; // address + uint128 * numTokens
    }

    // update rewards map w/ zk proof, _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    function _updateRewards(
        uint8 appId,
        uint32 epoch,
        bytes calldata appOutputWithoutAppIdEpoch,
        bool enumerable,
        uint256 startEarnerIndex,
        uint256 endEarnerIndex
    ) internal override returns (bool allEarnersProcessed) {
        return _addRewards(appId, epoch, appOutputWithoutAppIdEpoch, enumerable, startEarnerIndex, endEarnerIndex);
    }

    // parse circuit output, check and add new reward to total
    // epoch, [usr,amt1,amt2..]
    function _addRewards(
        uint8 appId,
        uint32 epoch,
        bytes calldata appOutputWithoutAppIdEpoch,
        bool enumerable,
        uint256 startEarnerIndex,
        uint256 endEarnerIndex
    ) internal returns (bool allEarnersProcessed) {
        checkExtraData(appOutputWithoutAppIdEpoch);
        uint256 numTokens = tokens.length;
        uint256[] memory newTokenRewards = new uint256[](numTokens);
        uint256 headerSize = _getHeaderSize(appId);
        address lastEarner = _lastEarnerOfLastSegment[appId][epoch];

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
            for (uint256 i = 0; i < numTokens; i++) {
                uint256 amtPos = offset + 20 + 16 * i;
                uint256 amount = uint128(bytes16(appOutputWithoutAppIdEpoch[amtPos:(amtPos + 16)]));
                _rewards.add(earner, tokens[i], amount, enumerable);
                newTokenRewards[i] += amount;
                newRewards[i] = amount;
            }
            emit RewardsAdded(appId, epoch, earner, newRewards);
        }
        _lastEarnerOfLastSegment[appId][epoch] = lastEarner;

        for (uint256 i = 0; i < numTokens; i += 1) {
            tokenCumulativeRewards[tokens[i]] += newTokenRewards[i];
        }
        return allEarnersProcessed;
    }

    function checkExtraData(bytes calldata appOutputWithoutAppIdEpoch) private view {
        bytes32[] memory extraData = config.extraData;
        for (uint256 i = 0; i < extraData.length; i++) {
            require(
                extraData[i] == bytes32(appOutputWithoutAppIdEpoch[(0 + i * 32):(0 + i * 32 + 32)]),
                string.concat(
                    string.concat(
                        string.concat("invalid extra data, want ", Strings.toHexString(uint256(extraData[i]))), ", got "
                    ),
                    Strings.toHexString(uint256(bytes32(appOutputWithoutAppIdEpoch[(0 + i * 32):(0 + i * 32 + 32)])))
                )
            );
        }
    }
}
