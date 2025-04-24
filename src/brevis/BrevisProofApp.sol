// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IBrevisProof.sol";

// App that directly interact with the BrevisProof contract interface.
abstract contract BrevisProofApp {
    struct ProofData {
        bytes32 commitHash;
        bytes32 appCommitHash; // zk-program computing circuit commit hash
        bytes32 appVkHash; // zk-program computing circuit Verify Key hash
        bytes32 smtRoot;
        bytes32 dummyInputCommitment; // zk-program computing circuit dummy input commitment
    }

    IBrevisProof public brevisProof;

    uint32 constant PUBLIC_BYTES_START_IDX = 11 * 32; // the first 10 32bytes are groth16 proof (A/B/C/Commitment), the 11th 32bytes is cPub

    function _checkBrevisProof(uint64 _chainId, bytes calldata _proof, bytes calldata _appOutput, bytes32 _appVkHash)
        internal
        returns (bytes32 proofId)
    {
        ProofData memory data = _unpackProofData(_proof);
        proofId = keccak256(abi.encodePacked(data.appVkHash, data.commitHash, data.appCommitHash));
        // Skip proof submission if already verified by BrevisProof
        if (brevisProof.proofs(proofId) == bytes32(0)) {
            (, bytes32 appCommitHash, bytes32 appVkHash) = brevisProof.submitProof(_chainId, _proof);
            require(appVkHash == _appVkHash, "mismatch vkhash");
            require(appCommitHash == keccak256(_appOutput), "invalid circuit output");
        }
        return proofId;
    }

    function _checkBrevisAggProof(
        uint64 _chainId,
        bytes32[] calldata _proofIds,
        bytes calldata _proofWithPubInputs,
        IBrevisProof.ProofData[] calldata _proofDataArray
    ) internal {
        brevisProof.submitAggProof(_chainId, _proofIds, _proofWithPubInputs);
        brevisProof.validateAggProofData(_chainId, _proofDataArray);
    }

    function _unpackProofData(bytes calldata _proofWithPubInputs) internal pure returns (ProofData memory data) {
        data.commitHash = bytes32(_proofWithPubInputs[PUBLIC_BYTES_START_IDX:PUBLIC_BYTES_START_IDX + 32]);
        data.smtRoot = bytes32(_proofWithPubInputs[PUBLIC_BYTES_START_IDX + 32:PUBLIC_BYTES_START_IDX + 2 * 32]);
        data.appCommitHash =
            bytes32(_proofWithPubInputs[PUBLIC_BYTES_START_IDX + 2 * 32:PUBLIC_BYTES_START_IDX + 3 * 32]);
        data.appVkHash = bytes32(_proofWithPubInputs[PUBLIC_BYTES_START_IDX + 3 * 32:PUBLIC_BYTES_START_IDX + 4 * 32]);
        data.dummyInputCommitment =
            bytes32(_proofWithPubInputs[PUBLIC_BYTES_START_IDX + 4 * 32:PUBLIC_BYTES_START_IDX + 5 * 32]);
    }
}
