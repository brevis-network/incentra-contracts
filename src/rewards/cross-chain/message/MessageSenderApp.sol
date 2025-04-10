// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract MessageSenderApp {
    address public messageBus;

    function sendMessage(address _receiver, uint64 _dstChainId, bytes memory _message, uint256 _fee) internal {
        IMessageBus(messageBus).sendMessage{value: _fee}(_receiver, _dstChainId, _message);
    }
}

interface IMessageBus {
    /**
     * @notice Send a message to a contract on another chain.
     * @param _receiver The address of the destination app contract.
     * @param _dstChainId The destination chain ID.
     * @param _message Arbitrary message bytes to be decoded by the destination app contract.
     */
    function sendMessage(address _receiver, uint256 _dstChainId, bytes calldata _message) external payable;
}
