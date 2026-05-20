// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BatchExecutor} from "../../src/lib/BatchExecutor.sol";

contract MockERC20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract RevertingTarget {
    error Boom(uint256 x);
    function ok() external {}
    function boom() external pure { revert Boom(42); }
}

contract Reenterer {
    address public immutable eoa;
    BatchExecutor.Call[] private nested;
    constructor(address _eoa, BatchExecutor.Call[] memory calls) {
        eoa = _eoa;
        for (uint256 i; i < calls.length; ++i) nested.push(calls[i]);
    }
    function reenter() external {
        BatchExecutor(payable(eoa)).execute(nested);
    }
}

contract BatchExecutorTest is Test {
    BatchExecutor internal impl;
    address payable internal eoa;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;

    address internal claim1 = address(0xC1A1);
    address internal claim2 = address(0xC1A2);
    address internal claim3 = address(0xC1A3);

    function setUp() public {
        impl = new BatchExecutor();
        eoa = payable(makeAddr("operator"));

        // Simulate EIP-7702 delegation: install BatchExecutor runtime code at the EOA.
        vm.etch(eoa, address(impl).code);

        tokenA = new MockERC20("TokenA", "A");
        tokenB = new MockERC20("TokenB", "B");
        tokenC = new MockERC20("TokenC", "C");

        tokenA.mint(eoa, 1_000 ether);
        tokenB.mint(eoa, 2_000 ether);
        tokenC.mint(eoa, 3_000 ether);
    }

    function _callTransfer(address token, address to, uint256 amount)
        internal
        pure
        returns (BatchExecutor.Call memory)
    {
        return BatchExecutor.Call({
            target: token,
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        });
    }

    /// @notice Core use case: fund three different campaign contracts with three
    ///         different reward tokens in one self-sponsored tx.
    function test_BatchFundsMultipleCampaignsWithDifferentTokens() public {
        BatchExecutor.Call[] memory calls = new BatchExecutor.Call[](3);
        calls[0] = _callTransfer(address(tokenA), claim1, 100 ether);
        calls[1] = _callTransfer(address(tokenB), claim2, 250 ether);
        calls[2] = _callTransfer(address(tokenC), claim3, 500 ether);

        vm.prank(eoa);
        BatchExecutor(eoa).execute(calls);

        assertEq(tokenA.balanceOf(claim1), 100 ether);
        assertEq(tokenB.balanceOf(claim2), 250 ether);
        assertEq(tokenC.balanceOf(claim3), 500 ether);

        assertEq(tokenA.balanceOf(eoa), 900 ether);
        assertEq(tokenB.balanceOf(eoa), 1_750 ether);
        assertEq(tokenC.balanceOf(eoa), 2_500 ether);
    }

    /// @notice Same token can be split across multiple recipients in one batch.
    function test_BatchSplitsSameTokenAcrossRecipients() public {
        BatchExecutor.Call[] memory calls = new BatchExecutor.Call[](3);
        calls[0] = _callTransfer(address(tokenA), claim1, 10 ether);
        calls[1] = _callTransfer(address(tokenA), claim2, 20 ether);
        calls[2] = _callTransfer(address(tokenA), claim3, 30 ether);

        vm.prank(eoa);
        BatchExecutor(eoa).execute(calls);

        assertEq(tokenA.balanceOf(claim1), 10 ether);
        assertEq(tokenA.balanceOf(claim2), 20 ether);
        assertEq(tokenA.balanceOf(claim3), 30 ether);
        assertEq(tokenA.balanceOf(eoa), 940 ether);
    }

    function test_EmptyBatchIsNoop() public {
        BatchExecutor.Call[] memory calls = new BatchExecutor.Call[](0);
        vm.prank(eoa);
        BatchExecutor(eoa).execute(calls);
    }

    function test_RevertsWhenCallerIsNotSelf() public {
        BatchExecutor.Call[] memory calls = new BatchExecutor.Call[](1);
        calls[0] = _callTransfer(address(tokenA), claim1, 1 ether);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(BatchExecutor.Unauthorized.selector);
        BatchExecutor(eoa).execute(calls);
    }

    /// @notice Calling the implementation contract directly (not via delegation) must revert.
    function test_RevertsWhenCallingImplementationDirectly() public {
        BatchExecutor.Call[] memory calls = new BatchExecutor.Call[](0);
        vm.prank(address(impl));
        // msg.sender == impl, address(this) == impl: passes self check actually...
        // But typical caller is some external EOA — verify that path reverts.
        impl.execute(calls); // self-call from impl as sender; this is allowed by the check.

        vm.prank(makeAddr("rando"));
        vm.expectRevert(BatchExecutor.Unauthorized.selector);
        impl.execute(calls);
    }

    function test_AtomicRevertBubblesFailingIndexAndData() public {
        RevertingTarget t = new RevertingTarget();

        BatchExecutor.Call[] memory calls = new BatchExecutor.Call[](3);
        calls[0] = _callTransfer(address(tokenA), claim1, 50 ether);
        calls[1] = BatchExecutor.Call({
            target: address(t),
            value: 0,
            data: abi.encodeWithSelector(RevertingTarget.boom.selector)
        });
        calls[2] = _callTransfer(address(tokenB), claim2, 50 ether);

        bytes memory expectedInner = abi.encodeWithSelector(RevertingTarget.Boom.selector, uint256(42));
        vm.prank(eoa);
        vm.expectRevert(abi.encodeWithSelector(BatchExecutor.CallFailed.selector, uint256(1), expectedInner));
        BatchExecutor(eoa).execute(calls);

        // Whole batch rolled back.
        assertEq(tokenA.balanceOf(claim1), 0);
        assertEq(tokenB.balanceOf(claim2), 0);
        assertEq(tokenA.balanceOf(eoa), 1_000 ether);
        assertEq(tokenB.balanceOf(eoa), 2_000 ether);
    }

    function test_InsufficientTokenBalanceRevertsWholeBatch() public {
        BatchExecutor.Call[] memory calls = new BatchExecutor.Call[](2);
        calls[0] = _callTransfer(address(tokenA), claim1, 100 ether);
        calls[1] = _callTransfer(address(tokenA), claim2, 10_000 ether); // > balance

        vm.prank(eoa);
        vm.expectRevert(); // CallFailed(1, <ERC20InsufficientBalance ...>)
        BatchExecutor(eoa).execute(calls);

        assertEq(tokenA.balanceOf(claim1), 0);
        assertEq(tokenA.balanceOf(eoa), 1_000 ether);
    }

    function test_ForwardsEthValue() public {
        vm.deal(eoa, 5 ether);
        address payable sink = payable(makeAddr("sink"));

        BatchExecutor.Call[] memory calls = new BatchExecutor.Call[](2);
        calls[0] = BatchExecutor.Call({target: sink, value: 1 ether, data: ""});
        calls[1] = BatchExecutor.Call({target: sink, value: 2 ether, data: ""});

        vm.prank(eoa);
        BatchExecutor(eoa).execute{value: 3 ether}(calls);

        assertEq(sink.balance, 3 ether);
        assertEq(eoa.balance, 5 ether - 3 ether);
    }

    function test_InsufficientEthForInnerCallRevertsBatch() public {
        vm.deal(eoa, 1 ether);
        address payable sink = payable(makeAddr("sink"));

        BatchExecutor.Call[] memory calls = new BatchExecutor.Call[](2);
        calls[0] = BatchExecutor.Call({target: sink, value: 1 ether, data: ""});
        calls[1] = BatchExecutor.Call({target: sink, value: 1 ether, data: ""}); // EOA only has 1 ETH total

        vm.prank(eoa);
        vm.expectRevert(); // CallFailed at index 1
        BatchExecutor(eoa).execute(calls);

        assertEq(sink.balance, 0);
        assertEq(eoa.balance, 1 ether);
    }

    /// @notice Nested `execute` from the EOA itself (target = eoa) must hit the guard.
    ///         External-caller reentrancy is already blocked by the Unauthorized check.
    function test_ReentrancyIntoExecuteReverts() public {
        BatchExecutor.Call[] memory inner = new BatchExecutor.Call[](1);
        inner[0] = _callTransfer(address(tokenA), claim1, 1 ether);

        BatchExecutor.Call[] memory outer = new BatchExecutor.Call[](1);
        outer[0] = BatchExecutor.Call({
            target: eoa,
            value: 0,
            data: abi.encodeWithSelector(BatchExecutor.execute.selector, inner)
        });

        vm.prank(eoa);
        vm.expectRevert(
            abi.encodeWithSelector(
                BatchExecutor.CallFailed.selector,
                uint256(0),
                abi.encodeWithSelector(BatchExecutor.Reentrant.selector)
            )
        );
        BatchExecutor(eoa).execute(outer);

        assertEq(tokenA.balanceOf(claim1), 0);
    }

    /// @notice An external caller attempting reentrancy hits Unauthorized, not Reentrant —
    ///         the self-call check fences off cross-contract reentry before the guard.
    function test_ExternalCallerReentrancyHitsUnauthorized() public {
        BatchExecutor.Call[] memory inner = new BatchExecutor.Call[](0);
        Reenterer r = new Reenterer(eoa, inner);

        BatchExecutor.Call[] memory outer = new BatchExecutor.Call[](1);
        outer[0] = BatchExecutor.Call({
            target: address(r),
            value: 0,
            data: abi.encodeWithSelector(Reenterer.reenter.selector)
        });

        vm.prank(eoa);
        vm.expectRevert(
            abi.encodeWithSelector(
                BatchExecutor.CallFailed.selector,
                uint256(0),
                abi.encodeWithSelector(BatchExecutor.Unauthorized.selector)
            )
        );
        BatchExecutor(eoa).execute(outer);
    }

    /// @notice Guard slot must be cleared so a second batch in a later tx works.
    function test_GuardClearedBetweenBatches() public {
        BatchExecutor.Call[] memory first = new BatchExecutor.Call[](1);
        first[0] = _callTransfer(address(tokenA), claim1, 10 ether);

        vm.prank(eoa);
        BatchExecutor(eoa).execute(first);

        BatchExecutor.Call[] memory second = new BatchExecutor.Call[](1);
        second[0] = _callTransfer(address(tokenB), claim2, 20 ether);

        vm.prank(eoa);
        BatchExecutor(eoa).execute(second);

        assertEq(tokenA.balanceOf(claim1), 10 ether);
        assertEq(tokenB.balanceOf(claim2), 20 ether);
    }

    /// @notice Unknown selectors must revert — there is no fallback().
    function test_UnknownSelectorReverts() public {
        (bool ok,) = eoa.call(abi.encodeWithSignature("nonexistent()"));
        assertFalse(ok);
    }

    /// @notice Plain ETH transfer to the delegated EOA must still succeed (receive()).
    function test_ReceivePlainEth() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = eoa.call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(eoa.balance, 1 ether);
    }
}
