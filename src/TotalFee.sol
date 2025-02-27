// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract TotalFee {
    address public poolAddr; // pool address, set in init, check w/ circuit out

    uint64 public latestBlk; // most recent attested endblock, new output must have greater startBlk
    struct Fee {
        uint128 token0Amt;
        uint128 token1Amt;
    }
    mapping(uint64 => Fee) public totalFees; // endblk to fee
    event TotalFeePosted(uint64 startBlk, uint64 endBlk, uint128 token0Amt, uint128 token1Amt);

    function initTotalFee(address _pool) external {
        poolAddr = _pool;
    }
    // only called by inherited contract, raw is app circuit output
    function updateFee(bytes calldata raw) internal {
        require(raw.length == 60, "incorrect data length");
        uint64 startBlk = uint32(bytes4(raw[0:4]));
        uint64 endBlk = uint32(bytes4(raw[4:8]));
        address pool = address(bytes20(raw[8:28]));
        uint128 t0fee = uint128(bytes16(raw[28:44]));
        uint128 t1fee = uint128(bytes16(raw[44:60]));

        require(startBlk > latestBlk, "startBlk too small");
        require(endBlk > startBlk, "endBlk too small");
        require(pool == poolAddr, "wrong pool addr");

        latestBlk = endBlk;
        totalFees[endBlk] = Fee(t0fee, t1fee);
        emit TotalFeePosted(startBlk, endBlk, t0fee, t1fee);
    }
}