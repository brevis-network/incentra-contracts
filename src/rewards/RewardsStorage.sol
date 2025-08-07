// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "../access/AccessControl.sol";
import "../brevis/BrevisProofApp.sol";
import "../lib/EnumerableMap.sol";

struct AddrAmt {
    address token;
    uint256 amount;
}

abstract contract RewardsStorage is BrevisProofApp, AccessControl {
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    event RewardsAdded(uint8 indexed appId, uint32 indexed epoch, address indexed user, uint256[] newRewards);
    event ProofSegmentProcessed(
        bytes32 indexed proofId,
        uint32 indexed epoch,
        uint32 indexed batchIndex,
        uint256 startEarnerIndex,
        uint256 endEarnerIndex
    );
    event ProofProcessed(bytes32 indexed proofId, uint32 indexed epoch, uint32 indexed batchIndex);
    event RewardsAdjusted(uint64 indexed adjustmentId, address indexed user, int256[] adjustment);
    event RewardsSet(address indexed user, uint256[] cumulativeRewards);
    event RewardsCleared(uint64 indexed adjustmentId, address indexed user);
    event VkUpdated(uint8 appId, bytes32 vk);

    // ----- external fields -----

    // 82531167a8e1b9df58acc5f105c04f72009b9ff406bf7d722b527a2f45d626ae
    bytes32 public constant REWARD_UPDATER_ROLE = keccak256("reward_updater");

    address[] public tokens; // addr list of reward tokens

    // token -> total rewards
    mapping(address => uint256) public tokenCumulativeRewards;

    mapping(uint8 => bytes32) public vkMap; // from app ID to vkHash

    mapping(uint64 => address) public lastAdjustedUser; // last user adjusted for an adjustment ID

    // ----- internal fields -----

    // user -> token -> cumulative rewards
    EnumerableMap.UserTokenAmountMap internal _rewards;

    // proof ID -> last processed count in proof
    mapping(bytes32 => uint256) internal _proofLastProcessedEarnerCount;

    // ----- external functions -----

    function setVk(uint8 appId, bytes32 _vk) external onlyOwner {
        vkMap[appId] = _vk;
        emit VkUpdated(appId, _vk);
    }

    function getTokens() public view returns (address[] memory) {
        return tokens;
    }

    function getRewardAmount(address user, address token) public view returns (uint256) {
        return _rewards.get(user, token);
    }

    function viewTotalRewards(address user) external view returns (AddrAmt[] memory) {
        AddrAmt[] memory ret = new AddrAmt[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            ret[i] = AddrAmt({token: tokens[i], amount: _rewards.get(user, tokens[i])});
        }
        return ret;
    }

    function getRewardsLength() external view returns (uint64) {
        return uint64(_rewards.length());
    }

    function updateRewards(bytes calldata proof, bytes calldata appOutput, uint32 batchIndex, uint256 maxNumToProcess)
        external
        onlyRole(REWARD_UPDATER_ROLE)
    {
        require(_updatable(), "rewards not updatable");
        (bytes32 proofId, uint8 appId) = _checkProofAndGetAppId(proof, appOutput);
        uint256 lastProcessedEarnerCount = _proofLastProcessedEarnerCount[proofId];
        uint32 epoch = uint32(bytes4(appOutput[1:5]));

        bytes calldata appOutputWithoutAppIdEpoch = appOutput[5:];
        uint256 numEarnersInProof = (appOutputWithoutAppIdEpoch.length - _getHeaderSize(appId)) / _getSizePerEarner();
        uint256 numToProcess = Math.min(numEarnersInProof - lastProcessedEarnerCount, maxNumToProcess);
        require(numToProcess > 0, "no earners to process");

        // Use inclusive start and end indices
        uint256 startEarnerIndex = lastProcessedEarnerCount;
        uint256 endEarnerIndex = lastProcessedEarnerCount + numToProcess - 1;
        bool allEarnersProcessed = _updateRewards(
            appId, epoch, appOutputWithoutAppIdEpoch, _useEnumerableMap(), startEarnerIndex, endEarnerIndex
        );

        if (allEarnersProcessed) endEarnerIndex = numEarnersInProof - 1;
        _proofLastProcessedEarnerCount[proofId] = endEarnerIndex + 1;
        emit ProofSegmentProcessed(proofId, epoch, batchIndex, startEarnerIndex, endEarnerIndex);
        if (endEarnerIndex == numEarnersInProof - 1) {
            emit ProofProcessed(proofId, epoch, batchIndex);
        }
    }

    function adjustRewards(uint64 adjustmentId, address[] calldata users, int256[][] calldata adjustments)
        external
        onlyRole(REWARD_UPDATER_ROLE)
    {
        require(_updatable(), "rewards not updatable");
        int256[] memory totalAdjustments = new int256[](tokens.length);

        address lastUser = lastAdjustedUser[adjustmentId];
        for (uint256 i = 0; i < users.length; i++) {
            require(lastUser < users[i], "users must be in ascending order");
            lastUser = users[i];

            // Adjust rewards for the current user
            require(adjustments[i].length == tokens.length, "adjustments length mismatch");
            for (uint256 j = 0; j < tokens.length; j++) {
                uint256 cumulativeRewards = _rewards.get(users[i], tokens[j]);
                if (adjustments[i][j] > 0) {
                    cumulativeRewards += uint256(adjustments[i][j]);
                } else {
                    cumulativeRewards -= uint256(-adjustments[i][j]);
                }
                _rewards.set(users[i], tokens[j], cumulativeRewards, _useEnumerableMap());
                totalAdjustments[j] += adjustments[i][j];
            }
            emit RewardsAdjusted(adjustmentId, users[i], adjustments[i]);
        }
        lastAdjustedUser[adjustmentId] = lastUser;

        // Update cumulative rewards for each token
        for (uint256 j = 0; j < tokens.length; j++) {
            if (totalAdjustments[j] > 0) {
                tokenCumulativeRewards[tokens[j]] += uint256(totalAdjustments[j]);
            } else {
                tokenCumulativeRewards[tokens[j]] -= uint256(-totalAdjustments[j]);
            }
        }
    }

    function setUserRewards(address[] calldata users, uint256[][] calldata cumulativeRewards)
        external
        onlyRole(REWARD_UPDATER_ROLE)
    {
        require(_updatable(), "rewards not updatable");
        require(users.length == cumulativeRewards.length, "users and rewards length mismatch");
        int256[] memory totalAdjustments = new int256[](tokens.length);
        for (uint256 i = 0; i < users.length; i++) {
            require(cumulativeRewards[i].length == tokens.length, "rewards length mismatch");
            for (uint256 j = 0; j < tokens.length; j++) {
                uint256 oldRewards = _rewards.get(users[i], tokens[j]);
                uint256 newRewards = cumulativeRewards[i][j];
                _rewards.set(users[i], tokens[j], newRewards, _useEnumerableMap());
                totalAdjustments[j] += int256(newRewards) - int256(oldRewards);
            }
            emit RewardsSet(users[i], cumulativeRewards[i]);
        }
        // Update cumulative rewards for each token
        for (uint256 j = 0; j < tokens.length; j++) {
            if (totalAdjustments[j] > 0) {
                tokenCumulativeRewards[tokens[j]] += uint256(totalAdjustments[j]);
            } else if (totalAdjustments[j] < 0) {
                tokenCumulativeRewards[tokens[j]] -= uint256(-totalAdjustments[j]);
            }
        }
    }

    function clearRewards(uint64 adjustmentId, address user) external onlyRole(REWARD_UPDATER_ROLE) {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 userRewards = _rewards.get(user, tokens[i]);
            if (userRewards > 0) {
                tokenCumulativeRewards[tokens[i]] -= userRewards;
            }
            _rewards.set(user, tokens[i], 0, _useEnumerableMap());
        }
        emit RewardsCleared(adjustmentId, user);
    }

    // ----- internal functions -----

    function _initTokens(address[] memory _tokens) internal {
        for (uint256 i = 0; i < _tokens.length; i += 1) {
            tokens.push(_tokens[i]);
        }
    }

    function _checkProofAndGetAppId(bytes calldata proof, bytes calldata appOutput)
        internal
        returns (bytes32 proofId, uint8 appId)
    {
        appId = uint8(appOutput[0]);
        proofId = _checkBrevisProof(_getDataChainId(), proof, appOutput, vkMap[appId]);
        return (proofId, appId);
    }

    function _useEnumerableMap() internal view virtual returns (bool);

    function _getDataChainId() internal view virtual returns (uint64);

    function _getHeaderSize(uint8 appId) internal view virtual returns (uint256);

    function _getSizePerEarner() internal view virtual returns (uint256);

    function _updateRewards(
        uint8 appId,
        uint32 epoch,
        bytes calldata appOutputWithoutAppIdEpoch,
        bool enumerable,
        uint256 startEarnerIndex,
        uint256 endEarnerIndex
    ) internal virtual returns (bool allEarnersProcessed);

    function _updatable() internal view virtual returns (bool);
}
