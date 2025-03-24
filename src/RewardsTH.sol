// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract RewardsTH {
    address[] public tokens; // addr list of reward tokens
    // user->token cumulative rewards
    mapping(address => mapping(address => uint256)) public rewards;
    // user->token already claimed amount
    mapping(address => mapping(address => uint256)) public claimed;
    // user-> last attested epoch
    mapping(address => uint32) public lastEpoch;

    function initTokens(address[] memory _tokens) internal {
        for (uint256 i=0;i<_tokens.length;i+=1) {
            tokens.push(_tokens[i]);
        }
    }

    // parse circuit output, check and add new reward to total
    // epoch, totalFee0, totalFee1, [usr,amt1,amt2..]
    function addRewards(bytes calldata raw) internal {
        uint32 epoch = uint32(bytes4(raw[0:4]));
        uint256 numTokens = tokens.length;
        for (uint256 idx = 4; idx < raw.length; idx += 20+16*numTokens) { 
            address earner = address(bytes20(raw[idx:idx+20]));
            // skip empty address placeholders for the rest of array
            if (earner == address(0)) {
                break;
            }
            require(epoch > lastEpoch[earner], "invalid epoch");
            lastEpoch[earner] = epoch;
            for (uint256 i=0; i < numTokens; i+=1) {
                uint256 amount = uint128(bytes16(raw[idx+20+16*i:idx+20+16*i+16]));
                rewards[earner][tokens[i]] += amount;
            }
        }
    }

    function _claim(address earner, address to) internal {
        for (uint256 i=0;i<tokens.length;i++) {
            address erc20 = tokens[i];
            uint256 tosend = rewards[earner][erc20] - claimed[earner][erc20];
            claimed[earner][erc20] = rewards[earner][erc20];
            // send token
            if (tosend>0) {
                IERC20(erc20).transfer(to, tosend);
            }
        }
    }
}