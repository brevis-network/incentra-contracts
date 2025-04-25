// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

import "../../lib/EnumerableMap.sol";
import "../RewardsStorage.sol";
import "./message/MessageSenderApp.sol";

// generate campaign rewards merkle root and proof on one chain, which will be claimed on another chain
abstract contract RewardsMerkle is RewardsStorage, MessageSenderApp {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    enum State {
        Idle,
        RewardsSubmission,
        SubRootsGeneration,
        TopRootGeneration
    }

    State public state;
    uint64 public currEpoch;

    // Storage for merkle roots generation
    EnumerableSet.Bytes32Set subRoots;
    uint256[] subRootUserIndexStart;
    bytes32 public topRoot;

    event SubRootLeafProcessed(
        uint64 indexed epoch,
        uint256 indexed subRootIndex,
        uint256 indexed leafIndex,
        address user,
        uint256[] cumulativeRewards,
        bytes32 leafHash
    );
    event SubRootGenerated(uint64 indexed epoch, uint256 indexed subRootIndex, bytes32 subRoot);
    event AllSubRootsGenerated(uint64 indexed epoch);
    event TopRootGenerated(uint64 indexed epoch, bytes32 topRoot);
    event TopRootSent(uint64 indexed epoch, bytes32 topRoot, address receiver, uint64 dstChainId);
    event MessageBusSet(address messageBus);

    // ----------- state transition -----------
    function startEpoch(uint64 epoch) external onlyRole(REWARD_UPDATER_ROLE) {
        require(state == State.Idle, "invalid state");
        require(epoch > currEpoch, "invalid epoch");
        currEpoch = epoch;
        state = State.RewardsSubmission;
        subRoots.clear();
    }

    function startSubRootGen(uint64 epoch) external onlyRole(REWARD_UPDATER_ROLE) {
        require(state == State.RewardsSubmission, "invalid state");
        require(currEpoch == epoch, "invalid epoch");
        state = State.SubRootsGeneration;
    }

    // ----------- Merkle Roots Generation -----------

    // ----------- External Functions -----------

    /**
     * @notice Generates and records a Merkle root for a subset of users up to `nLeaves`.
     *         Should be called repeatedly until every user is covered in a subtree.
     * @param epoch The epoch.
     * @param nLeaves The maximal number of users to include in the current subtree.
     */
    function genSubRoot(uint64 epoch, uint256 nLeaves) external {
        require(state == State.SubRootsGeneration, "invalid state");
        require(epoch == currEpoch, "invalid epoch");
        require(nLeaves <= 2 ** 32, "too many leaves");

        uint256 subRootIndex = subRoots.length();
        uint256 indexStart = 0;
        if (subRootIndex == 0) {
            delete subRootUserIndexStart;
        } else {
            indexStart = subRootUserIndexStart[subRootIndex - 1];
        }

        uint256 maxNLeaves = _rewards.length() - indexStart;
        if (nLeaves > maxNLeaves) {
            nLeaves = maxNLeaves;
        }
        bytes32[] memory hashes = new bytes32[](nLeaves);
        address[] memory rewardTokens = getTokens();
        for (uint256 i = 0; i < nLeaves; i++) {
            (address user, uint256[] memory rewardAmounts) = _rewards.getUserAmountsAt(indexStart + i, rewardTokens);
            bytes32 leafHash = keccak256(abi.encodePacked(user, rewardTokens, rewardAmounts));
            hashes[i] = leafHash;
            emit SubRootLeafProcessed(epoch, subRootIndex, i, user, rewardAmounts, leafHash);
        }
        bytes32 subRoot = genMerkleRoot(hashes);
        subRoots.add(subRoot);
        emit SubRootGenerated(epoch, subRootIndex, subRoot);

        if (nLeaves == maxNLeaves) {
            state = State.TopRootGeneration;
            emit AllSubRootsGenerated(epoch);
        } else {
            subRootUserIndexStart.push(indexStart + nLeaves);
        }
    }

    /**
     * @notice Generates and records the top Merkle tree root, using the subtree roots as leaves.
     * @param epoch The epoch.
     */
    function genTopRoot(uint64 epoch) public {
        require(state == State.TopRootGeneration, "invalid state");
        require(epoch == currEpoch, "invalid epoch");
        topRoot = genMerkleRoot(subRoots.values());
        state = State.Idle;
        emit TopRootGenerated(currEpoch, topRoot);
    }

    /**
     * @notice Send the top Merkle root to the destination chain.
     * @param _receiver The CampaignRewardsClaim contract in the destination chain.
     * @param _dstChainId The destination chain ID.
     */
    function sendTopRoot(address _receiver, uint64 _dstChainId) public payable {
        require(messageBus != address(0), "message bus not set");
        require(state == State.Idle, "invalid state");
        require(topRoot != bytes32(0), "top root not generated");
        bytes memory message = abi.encode(currEpoch, topRoot);
        sendMessage(_receiver, _dstChainId, message, msg.value);
        emit TopRootSent(currEpoch, topRoot, _receiver, _dstChainId);
    }

    function genAndSendTopRoot(address _receiver, uint64 _dstChainId) external payable {
        genTopRoot(currEpoch);
        sendTopRoot(_receiver, _dstChainId);
    }

    function getMerkleProof(uint64 epoch, address user)
        external
        view
        returns (uint256[] memory rewardAmounts, bytes32[] memory proof)
    {
        require(state == State.Idle, "invalid state");
        require(epoch == currEpoch, "invalid epoch");

        address[] memory rewardTokens = getTokens();
        rewardAmounts = _rewards.getAmounts(user, rewardTokens);

        uint256 userIndex = _rewards._keys._inner._positions[bytes32(uint256(uint160(user)))] - 1;
        uint256 subRootIndex;
        while (subRootIndex < subRoots.length() - 1 && userIndex >= subRootUserIndexStart[subRootIndex]) {
            ++subRootIndex;
        }

        uint256 indexStart = subRootIndex == 0 ? 0 : subRootUserIndexStart[subRootIndex - 1];
        uint256 nLeaves = _rewards.length() - indexStart;
        if (subRootIndex < subRoots.length() - 1) {
            nLeaves -= _rewards.length() - subRootUserIndexStart[subRootIndex];
        }

        bytes32[] memory hashes = new bytes32[](nLeaves);
        for (uint256 i = 0; i < hashes.length; i++) {
            (address _user, uint256[] memory _rewardAmounts) = _rewards.getUserAmountsAt(indexStart + i, rewardTokens);
            hashes[i] = keccak256(abi.encodePacked(_user, rewardTokens, _rewardAmounts));
        }
        bytes32[] memory subProof = genMerkleProof(hashes, userIndex - indexStart);
        bytes32[] memory topProof = genMerkleProof(subRoots.values(), subRootIndex);

        proof = new bytes32[](subProof.length + topProof.length);
        for (uint256 i = 0; i < subProof.length; i++) {
            proof[i] = subProof[i];
        }
        for (uint256 i = 0; i < topProof.length; i++) {
            proof[subProof.length + i] = topProof[i];
        }
    }

    // ----- admin functions -----

    function setMessageBus(address _messageBus) external onlyOwner {
        require(_messageBus != address(0), "invalid message bus");
        messageBus = _messageBus;
        emit MessageBusSet(_messageBus);
    }

    // ----------- Private Functions -----------

    function genMerkleRoot(bytes32[] memory hashes) private pure returns (bytes32) {
        if (hashes.length == 0) {
            return bytes32(0);
        }
        while (hashes.length > 1) {
            bytes32[] memory nextHashes = new bytes32[]((hashes.length + 1) / 2);
            uint256 i;
            for (; i < hashes.length - 1; i += 2) {
                nextHashes[i / 2] = Hashes.commutativeKeccak256(hashes[i], hashes[i + 1]);
            }
            if (i == hashes.length - 1) {
                nextHashes[i / 2] = hashes[i];
            }
            hashes = nextHashes;
        }
        return hashes[0];
    }

    function genMerkleProof(bytes32[] memory hashes, uint256 path) private pure returns (bytes32[] memory proof) {
        proof = new bytes32[](32);

        uint256 length = 0;
        while (hashes.length > 1) {
            if (hashes.length % 2 == 0 || path < hashes.length - 1) {
                proof[length] = hashes[path ^ 1];
                ++length;
            }
            path >>= 1;

            bytes32[] memory nextHashes = new bytes32[]((hashes.length + 1) / 2);
            uint256 i;
            for (; i < hashes.length - 1; i += 2) {
                nextHashes[i / 2] = Hashes.commutativeKeccak256(hashes[i], hashes[i + 1]);
            }
            if (i == hashes.length - 1) {
                nextHashes[i / 2] = hashes[i];
            }
            hashes = nextHashes;
        }

        assembly ("memory-safe") {
            mstore(proof, length)
        }
    }
}
