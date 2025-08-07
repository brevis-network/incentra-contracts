// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IBrevisProof.sol";

contract SimpleBrevisProof is IBrevisProof {
    mapping(bytes32 => bytes32) public proofs; // proofId => keccak256(abi.encodePacked(appCommitHash, appVkHash));

    function submitProof(uint64, bytes calldata _proof)
        external
        override
        returns (bytes32 proofId, bytes32 appCommitHash, bytes32 appVkHash)
    {
        proofId = keccak256(_proof);
        (appCommitHash, appVkHash) = abi.decode(_proof, (bytes32, bytes32));
        proofs[proofId] = appCommitHash;
    }

    function validateProofAppData(bytes32 _proofId, bytes32 _appCommitHash, bytes32 _appVkHash)
        external
        view
        returns (bool)
    {
        require(proofs[_proofId] == keccak256(abi.encodePacked(_appCommitHash, _appVkHash)), "invalid data");
        return true;
    }

    function submitAggProof(uint64 _chainId, bytes32[] calldata _proofIds, bytes calldata _proofWithPubInputs)
        external
        override
    {}

    function validateAggProofData(uint64 _chainId, ProofData[] calldata _proofDataArray) external view override {}
}
