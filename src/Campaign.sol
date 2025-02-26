// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./IBrevisProof.sol";
import "./Ownable.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

struct AddrAmt {
    address token;
    uint256 amount;
}

struct Config {
    address creator;
    uint64 startTime;
    uint32 duration; // how many seconds this campaign is active, end after startTime+duration
    AddrAmt[] rewards; // list of [reward token and total amount]
}

contract Campaign is Ownable {
    uint64 public constant GRACE_PERIOD = 3600*24*10; // seconds after campaign end
    Config public config;
    IBrevisProof public brvProof;
    bytes32 public vkHash;

    // user->token cumulative rewards
    mapping(address => mapping(address => uint256)) public rewards;
    // user->token already claimed amount
    mapping(address => mapping(address => uint256)) public claimed;

    // called by proxy to properly set storage of proxy contract, owner is contract owner (hw or multisig)
    function init(Config calldata cfg, address owner, IBrevisProof _brv, bytes32 _vkHash) external {
        initOwner(owner);
        config = cfg;
        brvProof = _brv;
        vkHash = _vkHash;
    }

    // after grace period, refund all remaining balance to creator
    function refund() external {
        Config memory cfg = config;
        require(block.timestamp>cfg.startTime+cfg.duration+GRACE_PERIOD, "too soon");
        for (uint256 i=0;i<cfg.rewards.length;i++) {
            address erc20 = cfg.rewards[i].token;
            IERC20(erc20).transfer(cfg.creator, IERC20(erc20).balanceOf(address(this)));
        }
    }

    // claim reward, send erc20 to earner
    function claim(address earner) external {
        _claim(earner, earner);
    }

    // msg.sender is the earner
    function claimWithRecipient(address to) external {
        _claim(msg.sender, to);
    }

    function _claim(address earner, address to) internal {
        Config memory cfg = config;
        for (uint256 i=0;i<cfg.rewards.length;i++) {
            address erc20 = cfg.rewards[i].token;
            uint256 tosend = rewards[earner][erc20] - claimed[earner][erc20];
            claimed[earner][erc20] = rewards[earner][erc20];
            // send token
            IERC20(erc20).transfer(to, tosend);
        }
    }

    // update rewards map w/ zk proof, _appOutput is in the form of [earner:amt u128:amt u128]
    function updateRewards(bytes calldata _proof, bytes calldata _appOutput) external {
        (, bytes32 appCommitHash, bytes32 appVkHash) = brvProof.submitProof(uint64(block.chainid), _proof);
        require(appVkHash == vkHash, "mismatch vkhash");
        require(appCommitHash == keccak256(_appOutput), "invalid circuit output");
        Config memory cfg = config;
        uint256 numTokens = cfg.rewards.length;
        for (uint256 idx = 0; idx < _appOutput.length; idx += 20+16*numTokens) {
            address earner = address(bytes20(_appOutput[idx:idx+20]));
            for (uint256 i=0; i < numTokens; i+=1) {
                uint256 amount = uint128(bytes16(_appOutput[idx+20+16*i:idx+20+16*i+16]));
                rewards[earner][cfg.rewards[i].token] = amount;
            }
        }
    }

    function setvk(bytes32 _vk) external onlyOwner {
        vkHash = _vk;
    }
}
