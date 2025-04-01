// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// generaic interface for incentra backend to interact with the campaign contract
// each campaign contract may only implement a subset of the functions
interface ICampaign {
    function updateRewards(bytes calldata _proof, bytes calldata _appOutput, uint32 batchIndex) external;
    function updateTotalFee(bytes calldata _proof, bytes calldata _appOutput) external;

    // cross-chain related
    function startEpoch(uint64 epoch) external;
    function startSubRootGen(uint64 epoch) external;
    function genSubRoot(uint64 epoch, uint256 nLeaves) external;
    function genTopRoot(uint64 epoch) external;
}
