// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./IBrevisProof.sol";
import "./Ownable.sol";
import "./Rewards.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";

struct Config {
    address creator;
    uint64 startTime;
    uint32 duration; // how many seconds this campaign is active, end after startTime+duration
    address pooladdr; // which pool this campaign is for
    address[] tokens; // reward token addr
    uint256[] amounts; // corresponding amount of reward token
}

contract Campaign is Ownable, Rewards {
    uint64 public constant GRACE_PERIOD = 3600*24*10; // seconds after campaign end
    Config public config;
    IBrevisProof public brvProof;
    mapping(uint8 => bytes32) public vkMap; // from circuit id to its vkhash

    // called by proxy to properly set storage of proxy contract, owner is contract owner (hw or multisig)
    function init(Config calldata cfg, IBrevisProof _brv) external {
        initOwner();
        initTokens(cfg.tokens);
        config = cfg;
        brvProof = _brv;
    }

    // after grace period, refund all remaining balance to creator
    function refund() external {
        Config memory cfg = config;
        require(block.timestamp>cfg.startTime+cfg.duration+GRACE_PERIOD, "too soon");
        for (uint256 i=0;i<cfg.tokens.length;i++) {
            address erc20 = cfg.tokens[i];
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

    // _appOutput is 1(totalfee app id), pooladdr, epoch, t0, t1
    function updateTotalFee(bytes calldata _proof, bytes calldata _appOutput) external {
        _checkProof(_proof, _appOutput);
        address pooladdr = address(bytes20(_appOutput[1:21]));
        require(pooladdr == config.pooladdr, "mismatch pool addr");
        updateFee(_appOutput[21:]);
    }

    // update rewards map w/ zk proof, _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    function updateRewards(bytes calldata _proof, bytes calldata _appOutput) external {
        _checkProof(_proof, _appOutput);
        addRewards( _appOutput[1:]);
    }

    // update rewards map w/ zk proof, _appOutput is x(indirect reward app id), indirect addr, [earner:amt u128:amt u128]
    function updateIndirectRewards(bytes calldata _proof, bytes calldata _appOutput) external {
        _checkProof(_proof, _appOutput);
        addIndirectRewards( _appOutput[1:]);
    }

    function _checkProof(bytes calldata _proof, bytes calldata _appOutput) internal {
        (, bytes32 appCommitHash, bytes32 appVkHash) = brvProof.submitProof(uint64(block.chainid), _proof);
        uint8 appid = uint8(_appOutput[0]);
        require(appVkHash == vkMap[appid], "mismatch vkhash");
        require(appCommitHash == keccak256(_appOutput), "invalid circuit output");
    }

    function setVk(uint8 appid, bytes32 _vk) external onlyOwner {
        vkMap[appid] = _vk;
    }
}
