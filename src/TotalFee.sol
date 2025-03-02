// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract TotalFee {
    address public poolAddr; // pool address, set in init, check w/ circuit out
    struct Fee {
        uint128 token0Amt;
        uint128 token1Amt;
    }
    mapping(uint32 => Fee) public totalFees; // epochNum to totalfee in this epoch
    event TotalFeePosted(uint32 epoch, uint128 token0Amt, uint128 token1Amt);

    function initTotalFee(address _pool) external {
        poolAddr = _pool;
    }
    // only called by inherited contract, raw is app circuit output
    // epoch, pooladdr, t0fee, t1fee
    function updateFee(bytes calldata raw) internal {
        require(raw.length == 56, "incorrect data length");
        uint32 epoch = uint32(bytes4(raw[0:4]));
        address pool = address(bytes20(raw[4:24]));
        uint128 t0fee = uint128(bytes16(raw[24:40]));
        uint128 t1fee = uint128(bytes16(raw[40:56]));
        require(pool == poolAddr, "wrong pool addr");

        totalFees[epoch] = Fee(t0fee, t1fee);
        emit TotalFeePosted(epoch, t0fee, t1fee);
    }
}