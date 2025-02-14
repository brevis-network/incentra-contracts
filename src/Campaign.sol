// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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
    bytes32 public root; // merkle tree root

    // user->token already claimed amount
    mapping(address => mapping(address => uint256)) public claimed;

    // called by proxy to properly set storage of proxy contract
    function init(Config calldata cfg) external {
        initOwner();
        config = cfg;        
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

    // claim reward
    function claim(address earner, AddrAmt[] memory totalRewards, bytes32[] memory proof) external {
        _claim(earner, earner, totalRewards, proof);
    }

    // msg.sender is the earner
    function claimWithRecipient(address to, AddrAmt[] memory totalRewards, bytes32[] memory proof) external {
        _claim(msg.sender, to, totalRewards, proof);
    }

    function _claim(address earner, address to, AddrAmt[] memory totalRewards, bytes32[] memory proof) internal {
        bytes memory tohash = abi.encodePacked(earner);
        for (uint256 i = 0; i < totalRewards.length; i++) {
            tohash = abi.encodePacked(tohash, totalRewards[i].token, totalRewards[i].amount);
        }
        bytes32 leaf = keccak256(tohash);
        require(_verifyProof(leaf, proof), "invalid proof");
        for (uint256 i = 0; i < totalRewards.length; i++) {
            address erc20 = totalRewards[i].token;
            uint256 tosend = totalRewards[i].amount - claimed[earner][erc20];
            if (tosend>0) {
                claimed[earner][erc20] = totalRewards[i].amount;
                IERC20(erc20).transfer(to, tosend);
            }
        }
    }

    function _verifyProof(bytes32 leaf, bytes32[] memory proof) internal view returns (bool) {
        bytes32 hash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            if (hash < proof[i]) {
                hash = keccak256(abi.encodePacked(hash, proof[i]));
            } else {
                hash = keccak256(abi.encodePacked(proof[i], hash));
            }
        }

        return hash == root;
    }
}
