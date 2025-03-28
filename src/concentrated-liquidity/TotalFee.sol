// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract TotalFee {
    struct Fee {
        uint128 token0Amt;
        uint128 token1Amt;
    }

    mapping(uint32 => Fee) public totalFees; // epochNum to totalfee in this epoch

    event TotalFeePosted(uint32 epoch, uint128 token0Amt, uint128 token1Amt);

    // only called by inherited contract, raw is app circuit output[:20], caller should first check [0:20] is expected pool addr
    // epoch, t0fee, t1fee
    function _updateFee(bytes calldata raw) internal {
        require(raw.length == 36, "incorrect data length");
        uint32 epoch = uint32(bytes4(raw[0:4]));
        uint128 t0fee = uint128(bytes16(raw[4:20]));
        uint128 t1fee = uint128(bytes16(raw[20:36]));

        totalFees[epoch] = Fee(t0fee, t1fee);
        emit TotalFeePosted(epoch, t0fee, t1fee);
    }
}
