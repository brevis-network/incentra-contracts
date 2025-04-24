// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../brevis/BrevisProofApp.sol";
import "../lib/EnumerableMap.sol";
import "../rewards/same-chain/RewardsClaim.sol";
import "./RewardsUpdateCL.sol";

// submit and claim campaign rewards on a same chain
contract CampaignCL is BrevisProofApp, RewardsUpdateCL, RewardsClaim {
    using SafeERC20 for IERC20;

    uint64 public constant GRACE_PERIOD = 3600 * 24 * 10; // seconds after campaign end

    // called by proxy to properly set storage of proxy contract, owner is contract owner (hw or multisig)
    function init(
        ConfigCL calldata cfg,
        IBrevisProof brv,
        address owner,
        bytes32[] calldata vks,
        uint64 dataChainId,
        address rewardUpdater
    ) external {
        initOwner(owner);
        _initConfig(cfg, brv, vks, dataChainId);
        grantRole(REWARD_UPDATER_ROLE, rewardUpdater);
    }

    // ----- external functions -----

    // after grace period, refund all remaining balance to creator
    function refund() external {
        ConfigCL memory cfg = config;
        require(block.timestamp > cfg.startTime + cfg.duration + GRACE_PERIOD, "too soon");
        for (uint256 i = 0; i < cfg.rewards.length; i++) {
            address erc20 = cfg.rewards[i].token;
            IERC20(erc20).safeTransfer(cfg.creator, IERC20(erc20).balanceOf(address(this)));
        }
    }

    // ----- internal functions -----

    function _useEnumerableMap() internal pure override returns (bool) {
        return false;
    }
}
