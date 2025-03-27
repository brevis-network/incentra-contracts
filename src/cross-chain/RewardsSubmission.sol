// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../AddRewards.sol";

// submit campaign rewards on chain Y
contract RewardsSubmission is AddRewards {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    enum State {
        EpochInit,
        RewardsSubmission,
        SubRootsGeneration,
        TopRootGeneration
    }

    // Storage for merkle roots generation
    EnumerableSet.Bytes32Set subRoots;
    uint256[] subRootUserIndexStart;
    bytes32 public topRoot;

    // ----------- Merkle Roots Generation -----------

    /**
     * @notice Generates and records a Merkle root for a subset of users up to `nLeaves`.
     *         Should be called repeatedly until every user is covered in a subtree.
     * @param epoch The epoch.
     * @param nLeaves The maximal number of users to include in the current subtree.
     */
    function genSubRoot(uint64 epoch, uint256 nLeaves) external {}

    /**
     * @notice Generates and records the top Merkle tree root, using the subtree roots as leaves.
     * @param epoch The epoch.
     */
    function genTopRoot(uint64 epoch) external {}
}
