// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/EnumerableMap.sol";
import "../rewards/RewardsStorage.sol";

struct ConfigTH {
    address creator;
    uint64 startTime;
    uint32 duration; // how many seconds this campaign is active, end after startTime+duration
    AddrAmt[] rewards; // list of [reward token and total amount]
    address erc20; // which erc20 is used for token holding
}

abstract contract RewardsUpdateTH is RewardsStorage {
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    ConfigTH public config;
    uint64 public dataChainId; // chain id of the data source

    // ----- internal functions -----

    function _initConfig(ConfigTH calldata cfg, IBrevisProof _brevisProof, bytes32[] calldata vks, uint64 _dataChainId)
        internal
    {
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

    function _getHeaderSize(uint8) internal pure override returns (uint256) {
        return 0;
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
        uint256 numEarnersInProof,
        uint256 startEarnerIndex,
        uint256 endEarnerIndex
    ) internal override {
        _addRewards(
            appId, epoch, appOutputWithoutAppIdEpoch, enumerable, numEarnersInProof, startEarnerIndex, endEarnerIndex
        );
    }

    // parse circuit output, check and add new reward to total
    // epoch, [usr,amt1,amt2..]
    function _addRewards(
        uint8 appId,
        uint32 epoch,
        bytes calldata appOutputWithoutAppIdEpoch,
        bool enumerable,
        uint256 numEarnersInProof,
        uint256 startEarnerIndex,
        uint256 endEarnerIndex
    ) internal {
        uint256 numTokens = tokens.length;
        uint256[] memory newTokenRewards = new uint256[](numTokens);
        uint256 sizePerEarner = _getSizePerEarner();
        address lastEarnerOfLastProof = _lastEarnerOfLastProof[appId][epoch];

        for (uint256 earnerIndex = startEarnerIndex; earnerIndex <= endEarnerIndex; earnerIndex++) {
            uint256 offset = _getSizePerEarner() * earnerIndex;
            address earner = address(bytes20(appOutputWithoutAppIdEpoch[offset:offset + 20]));
            // skip empty address placeholders for the rest of array
            if (earner == address(0)) {
                if (earnerIndex > 0) {
                    _lastEarnerOfLastProof[appId][epoch] =
                        address(bytes20(appOutputWithoutAppIdEpoch[offset - sizePerEarner:offset - sizePerEarner + 20]));
                }
                break;
            }
            if (earnerIndex == 0) {
                require(lastEarnerOfLastProof < earner, "earner addresses not sorted");
            }
            uint256[] memory newRewards = new uint256[](numTokens);
            for (uint256 i = 0; i < numTokens; i++) {
                uint256 amount =
                    uint128(bytes16(appOutputWithoutAppIdEpoch[offset + 20 + 16 * i:offset + 20 + 16 * i + 16]));
                _rewards.add(earner, tokens[i], amount, enumerable);
                newTokenRewards[i] += amount;
                newRewards[i] = amount;
            }
            if (earnerIndex == numEarnersInProof - 1) {
                _lastEarnerOfLastProof[appId][epoch] = earner;
            }
            emit RewardsAdded(appId, epoch, earner, newRewards);
        }
        for (uint256 i = 0; i < numTokens; i += 1) {
            tokenCumulativeRewards[tokens[i]] += newTokenRewards[i];
        }
    }
}
