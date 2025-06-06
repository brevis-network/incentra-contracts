// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// generic interface for incentra backend to interact with the campaign contract
// each campaign contract may only implement a subset of the functions
interface ICampaign {
    function updateRewards(bytes calldata proof, bytes calldata appOutput, uint32 batchIndex, uint256 maxNumToProcess)
        external;

    function updateTotalFee(bytes calldata proof, bytes calldata appOutput) external;

    function tokenCumulativeRewards(address token) external view returns (uint256);

    // --------- cross-chain related ---------

    // --- rewards submission contract ---

    function startEpoch(uint64 epoch) external;

    function startSubRootGen(uint64 epoch) external;

    function genSubRoot(uint64 epoch, uint256 nLeaves) external;

    function genTopRoot(uint64 epoch) external;

    function sendTopRoot(address _receiver, uint64 _dstChainId) external payable;

    function genAndSendTopRoot(address _receiver, uint64 _dstChainId) external payable;

    function state() external view returns (uint8);

    function currEpoch() external view returns (uint64);

    function topRoot() external view returns (bytes32);

    // --- rewards claim contract ---

    function updateRoot(uint64 _epoch, bytes32 _topRoot) external;
}
