// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IBrevisProof.sol";
import "../access/AccessControl.sol";

contract BrevisProofRelay is AccessControl {
    IBrevisProof public brevisProof;

    // 589d473ba17c0f47d494622893831497bad25919b9afb8e33e9521b8963fccde
    bytes32 public constant ADMIN_ROLE = keccak256("admin_role");
    // c446372802fc3419d51d169d27b034f2f22c2f5650596653a4ac875e6ce55873
    bytes32 public constant CAMPAIGN_ROLE = keccak256("campaign_role");

    event BrevisProofUpdated(address from, address to);

    constructor(IBrevisProof _brevisProof) {
        brevisProof = _brevisProof;
    }

    function submitProof(uint64 _chainId, bytes calldata _proofWithPubInputs)
        external
        onlyRole(CAMPAIGN_ROLE)
        returns (bytes32 requestId, bytes32 appCommitHash, bytes32 appVkHash)
    {
        return brevisProof.submitProof(_chainId, _proofWithPubInputs);
    }

    function validateProofAppData(bytes32 _requestId, bytes32 _appCommitHash, bytes32 _appVkHash)
        external
        view
        returns (bool)
    {
        return brevisProof.validateProofAppData(_requestId, _appCommitHash, _appVkHash);
    }

    function submitAggProof(uint64 _chainId, bytes32[] calldata _requestIds, bytes calldata _proofWithPubInputs)
        external
        onlyRole(CAMPAIGN_ROLE)
    {
        return brevisProof.submitAggProof(_chainId, _requestIds, _proofWithPubInputs);
    }

    function validateAggProofData(uint64 _chainId, IBrevisProof.ProofData[] calldata _proofDataArray) external view {
        return brevisProof.validateAggProofData(_chainId, _proofDataArray);
    }

    function addCampaigns(address[] memory _campaigns) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _campaigns.length; i++) {
            _grantRole(CAMPAIGN_ROLE, _campaigns[i]);
        }
    }

    function removeCampaigns(address[] memory _campaigns) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _campaigns.length; i++) {
            _revokeRole(CAMPAIGN_ROLE, _campaigns[i]);
        }
    }

    function addAdmin(address _admin) external onlyOwner {
        _grantRole(ADMIN_ROLE, _admin);
    }

    function removeAdmin(address _admin) external onlyOwner {
        _revokeRole(ADMIN_ROLE, _admin);
    }

    function setBrevisProof(address _brevisProof) external onlyOwner {
        address oldAddr = address(brevisProof);
        brevisProof = IBrevisProof(_brevisProof);
        emit BrevisProofUpdated(oldAddr, _brevisProof);
    }
}
