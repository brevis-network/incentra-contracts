// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title BatchExecutor
/// @notice Minimal EIP-7702 batch executor. Intended to be set as the delegated
///         code of an EOA via a type-4 authorization so that a single transaction
///         can perform an arbitrary sequence of plain CALLs from the EOA atomically.
///
///         Use case in this repo: an operator EOA holding reward tokens funds
///         multiple campaign contracts in one tx by batching N `token.transfer`
///         calls. The executor never custodies tokens or ETH on behalf of the EOA.
///
///         Security properties (enforced or by construction):
///         - No token / no ETH custody logic. Only `receive()` is defined, with an
///           empty body, so the delegated EOA can still receive plain ETH transfers.
///         - No fallback() — calls with unknown selectors revert.
///         - No storage other than a namespaced reentrancy guard slot.
///         - No admin, no owner, no upgrade path, no selfdestruct, no delegatecall,
///           no CREATE/CREATE2 from within the executor.
///         - Only the delegating EOA itself can invoke `execute` (must be the tx
///           sender). Sponsor / relayer flows are out of scope — supporting them
///           safely requires a signature + nonce scheme which this contract
///           deliberately omits.
///         - Reentrancy-guarded with a hashed, namespaced storage slot to avoid
///           collisions with other modules that may share the EOA's storage in the
///           future. Any nested call back into `execute` reverts.
///         - Atomic: any inner call failure reverts the whole batch and bubbles
///           up the index + raw revert data.
///         - Per-call `value` is forwarded from `msg.value`; if the cumulative
///           value exceeds the EOA's balance, the offending call reverts and the
///           batch is rolled back.
///
///         The contract is stateless across transactions (the guard slot is
///         always cleared before `execute` returns), making per-tx EIP-7702
///         delegation the recommended deployment mode.
contract BatchExecutor {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    /// @dev Namespaced reentrancy-guard slot. Hashed to avoid collision with
    ///      other modules that may be delegated to the same EOA's storage.
    bytes32 private constant _GUARD_SLOT =
        keccak256("brevis.incentra.BatchExecutor.reentrancyGuard.v1");

    error Unauthorized();
    error Reentrant();
    error CallFailed(uint256 index, bytes returndata);

    /// @notice Execute `calls` in order, atomically. Reverts the whole batch on
    ///         the first inner call failure, surfacing the failing index and the
    ///         raw revert data.
    /// @dev Only callable when `msg.sender == address(this)`. Under EIP-7702
    ///      this requires the delegating EOA to be the transaction sender
    ///      (self-sponsored). Calls from any other address revert with
    ///      `Unauthorized`.
    function execute(Call[] calldata calls) external payable {
        if (msg.sender != address(this)) revert Unauthorized();

        bytes32 slot = _GUARD_SLOT;
        uint256 guard;
        assembly {
            guard := sload(slot)
        }
        if (guard != 0) revert Reentrant();
        assembly {
            sstore(slot, 1)
        }

        uint256 len = calls.length;
        for (uint256 i; i < len; ++i) {
            Call calldata c = calls[i];
            (bool ok, bytes memory ret) = c.target.call{value: c.value}(c.data);
            if (!ok) revert CallFailed(i, ret);
        }

        assembly {
            sstore(slot, 0)
        }
    }

    /// @notice Accept plain ETH transfers so the delegated EOA remains able to
    ///         receive value while delegation is active. The executor does not
    ///         hold or forward this ETH — it sits in the EOA's balance as usual.
    receive() external payable {}
}
