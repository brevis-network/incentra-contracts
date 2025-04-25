// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IBrevisProof.sol";

// App that directly interact with the BrevisProof contract interface.
abstract contract BrevisProofApp {
    IBrevisProof public brevisProof;

    uint32 constant PUBLIC_BYTES_START_IDX = 11 * 32; // the first 10 32bytes are groth16 proof (A/B/C/Commitment), the 11th 32bytes is cPub

    function _checkBrevisProof(uint64 _chainId, bytes calldata _proof, bytes calldata _appOutput, bytes32 _appVkHash)
        internal
        returns (bytes32 proofId)
    {
        // BrevisProof will skip verification if already verified.
        bytes32 appCommitHash;
        bytes32 appVkHash;
        (proofId, appCommitHash, appVkHash) = brevisProof.submitProof(_chainId, _proof);
        require(appVkHash == _appVkHash, "vkHash mismatch");
        require(appCommitHash == keccak256(_appOutput), "invalid circuit output");
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
}
