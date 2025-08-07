// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IBrevisProof {
    struct ProofData {
        bytes32 commitHash;
        bytes32 appCommitHash;
        bytes32 appVkHash;
        bytes32 smtRoot;
        bytes32 dummyInputCommitment;
    }

    function proofs(bytes32 _proofId) external view returns (bytes32);

    function submitProof(uint64 _chainId, bytes calldata _proofWithPubInputs)
        external
        returns (bytes32 proofId, bytes32 appCommitHash, bytes32 appVkHash);

    function validateProofAppData(bytes32 _proofId, bytes32 _appCommitHash, bytes32 _appVkHash)
        external
        view
        returns (bool);

    function submitAggProof(uint64 _chainId, bytes32[] calldata _proofIds, bytes calldata _proofWithPubInputs)
        external;

    function validateAggProofData(uint64 _chainId, ProofData[] calldata _proofDataArray) external view;
}
