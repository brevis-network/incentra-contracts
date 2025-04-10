// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract MessageReceiverApp {
    enum ExecutionStatus {
        Fail,
        Success,
        Retry
    }

    address public messageBus;

    modifier onlyMessageBus() {
        require(msg.sender == messageBus, "caller is not message bus");
        _;
    }

    /**
     * @notice Called by MessageBus to execute a message
     * @param _sender The address of the source app contract
     * @param _srcChainId The source chain ID where the transfer is originated from
     * @param _message Arbitrary message bytes originated from and encoded by the source app contract
     */
    function executeMessage(
        address _sender,
        uint64 _srcChainId,
        bytes calldata _message,
        address // _executor: address who called the MessageBus execution function
    ) external onlyMessageBus returns (ExecutionStatus) {
        _executeMessage(_sender, _srcChainId, _message);
        return ExecutionStatus.Success;
    }

    function _executeMessage(address _sender, uint64 _srcChainId, bytes calldata _message) internal virtual {}
}
