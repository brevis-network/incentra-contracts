// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// generaic interface for incentra backend to interact with the campaign contract
// each campaign contract may only implement a subset of the functions
interface ICampaign {
    function updateRewards(bytes calldata proof, bytes calldata appOutput, uint32 batchIndex) external;

    function updateTotalFee(bytes calldata proof, bytes calldata appOutput) external;

    function tokenCumulativeRewards(address token) external view returns (uint256);

    // --------- cross-chain related ---------

    function startEpoch(uint64 epoch) external;

    function startSubRootGen(uint64 epoch) external;

    function genSubRoot(uint64 epoch, uint256 nLeaves) external;

    function genTopRoot(uint64 epoch) external;

    function state() external view returns (uint8);

    function currEpoch() external view returns (uint64);

    function getNumLeavesLeft() external view returns (uint64);
}
