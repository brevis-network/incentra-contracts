// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BrevisProofApp.sol";
import "../access/Whitelist.sol";
import "../lib/EnumerableMap.sol";
import "../rewards/RewardsStorage.sol";

struct Config {
    address creator;
    uint64 startTime;
    uint32 duration; // how many seconds this campaign is active, end after startTime+duration
    AddrAmt[] rewards; // list of [reward token and total amount]
    address erc20; // which erc20 is used for token holding
}

abstract contract RewardsUpdate is BrevisProofApp, RewardsStorage, Whitelist {
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    Config public config;
    mapping(uint8 => bytes32) public vkMap; // from circuit id to its vkhash

    function _initConfig(Config calldata cfg, IBrevisProof _breivisProof, bytes32[] calldata vks) internal {
        brevisProof = _breivisProof;
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

    function setVk(uint8 appid, bytes32 _vk) external onlyOwner {
        vkMap[appid] = _vk;
    }

    // ----- internal functions -----

    // update rewards map w/ zk proof, _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    function _updateRewards(bytes calldata _proof, bytes calldata _appOutput, bool enumerable) internal {
        _checkProof(_proof, _appOutput);
        _addRewards(_appOutput[1:], enumerable);
    }

    // parse circuit output, check and add new reward to total
    // epoch, [usr,amt1,amt2..]
    function _addRewards(bytes calldata raw, bool enumerable) internal {
        uint32 epoch = uint32(bytes4(raw[0:4]));
        uint256 numTokens = tokens.length;
        for (uint256 idx = 4; idx < raw.length; idx += 20 + 16 * numTokens) {
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
                newRewards[i] = amount;
            }
            emit RewardsAdded(earner, newRewards);
        }
    }

    function _checkProof(bytes calldata _proof, bytes calldata _appOutput) internal {
        uint8 appid = uint8(_appOutput[0]);
        _checkBrevisProof(uint64(block.chainid), _proof, _appOutput, vkMap[appid]);
    }
}
