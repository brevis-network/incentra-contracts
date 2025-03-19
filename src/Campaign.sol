// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./BrevisProofApp.sol";
import "./Whitelist.sol";
import "./Rewards.sol";

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
    address pooladdr; // which pool this campaign is for
}

contract Campaign is BrevisProofApp, Whitelist, Rewards {
    uint64 public constant GRACE_PERIOD = 3600 * 24 * 10; // seconds after campaign end
    Config public config;
    mapping(uint8 => bytes32) public vkMap; // from circuit id to its vkhash

    // called by proxy to properly set storage of proxy contract, owner is contract owner (hw or multisig)
    function init(Config calldata cfg, IBrevisProof _brv, address owner, bytes32[] calldata vks) external {
        initOwner(owner);
        address[] memory _tokens = new address[](cfg.rewards.length);
        for (uint256 i = 0; i < cfg.rewards.length; i++) {
            _tokens[i] = cfg.rewards[i].token;
        }
        initTokens(_tokens);
        config = cfg;
        brevisProof = _brv;
        // 1: TotalFee 2: Rewards 3+: Others
        for (uint8 i = 0; i < vks.length; i++) {
            vkMap[i+1] = vks[i];
        } 
    }

    // after grace period, refund all remaining balance to creator
    function refund() external {
        Config memory cfg = config;
        require(block.timestamp > cfg.startTime + cfg.duration + GRACE_PERIOD, "too soon");
        for (uint256 i = 0; i < cfg.rewards.length; i++) {
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

    // _appOutput is 1(totalfee app id), pooladdr, epoch, t0, t1
    function updateTotalFee(bytes calldata _proof, bytes calldata _appOutput) external onlyWhitelisted {
        _checkProof(_proof, _appOutput);
        address pooladdr = address(bytes20(_appOutput[1:21]));
        require(pooladdr == config.pooladdr, "mismatch pool addr");
        updateFee(_appOutput[21:]);
    }

    // update rewards map w/ zk proof, _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    function updateRewards(bytes calldata _proof, bytes calldata _appOutput) external onlyWhitelisted {
        _checkProof(_proof, _appOutput);
        addRewards(_appOutput[1:]);
    }

    // update rewards map w/ zk proof, _appOutput is x(indirect reward app id), indirect addr, [earner:amt u128:amt u128]
    function updateIndirectRewards(bytes calldata _proof, bytes calldata _appOutput) external onlyWhitelisted {
        _checkProof(_proof, _appOutput);
        addIndirectRewards(_appOutput[1:]);
    }

    function _checkProof(bytes calldata _proof, bytes calldata _appOutput) internal {
        uint8 appid = uint8(_appOutput[0]);
        _checkBrevisProof(uint64(block.chainid), _proof, _appOutput, vkMap[appid]);
    }

    function setVk(uint8 appid, bytes32 _vk) external onlyOwner {
        vkMap[appid] = _vk;
    }

    // ===== view =====
    function viewTotalRewards(address earner) external view returns (AddrAmt[] memory) {
        Config memory cfg = config;
        AddrAmt[] memory ret = new AddrAmt[](cfg.rewards.length);
        for (uint256 i = 0; i < cfg.rewards.length; i++) {
            ret[i] = AddrAmt({token: cfg.rewards[i].token, amount: rewards[earner][cfg.rewards[i].token]});
        }
        return ret;
    }

    function viewUnclaimedRewards(address earner) external view returns (AddrAmt[] memory) {
        Config memory cfg = config;
        AddrAmt[] memory ret = new AddrAmt[](cfg.rewards.length);
        for (uint256 i = 0; i < cfg.rewards.length; i++) {
            address erc20 = cfg.rewards[i].token;
            uint256 tosend = rewards[earner][erc20] - claimed[earner][erc20];
            ret[i] = AddrAmt({token: erc20, amount: tosend});
        }
        return ret;
    }
}
