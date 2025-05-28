// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../RewardsStorage.sol";
import "../../lib/EnumerableMap.sol";

// claim campaign rewards on chain X
abstract contract RewardsClaim is RewardsStorage {
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    // user -> token -> claimed amount
    mapping(address => mapping(address => uint256)) public claimed;
    // token -> total claimed amount
    mapping(address => uint256) public tokenClaimedRewards;

    // seconds after campaign end, after which all remaining balance can be refunded to creator
    uint64 public gracePeriod = 3600 * 24 * 180; // default 180 days

    // If set, only this address can call claim; rewards are not transferred directly, external address handles payout.
    address public externalPayoutAddress;

    event RewardsClaimed(address indexed earner, uint256[] claimedRewards);
    event GracePeriodUpdated(uint64 gracePeriod);

    // ----- external functions -----

    // claim reward, send erc20 to earner
    function claim(address earner) external returns (address[] memory, uint256[] memory) {
        return _claim(earner, earner);
    }

    // msg.sender is the earner
    function claimWithRecipient(address to) external returns (address[] memory, uint256[] memory) {
        return _claim(msg.sender, to);
    }

    function viewUnclaimedRewards(address earner) external view returns (AddrAmt[] memory) {
        AddrAmt[] memory ret = new AddrAmt[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 tosend = _rewards.get(earner, token) - claimed[earner][token];
            ret[i] = AddrAmt({token: token, amount: tosend});
        }
        return ret;
    }

    function setGracePeriod(uint64 _gracePeriod) external onlyOwner {
        gracePeriod = _gracePeriod;
        emit GracePeriodUpdated(_gracePeriod);
    }

    // ----- internal functions -----

    function _setExternalPayoutAddress(address _externalPayoutAddress) internal {
        externalPayoutAddress = _externalPayoutAddress;
    }

    function _claim(address earner, address to) internal returns (address[] memory, uint256[] memory) {
        uint256[] memory claimedRewards = new uint256[](tokens.length);
        bool hasUnclaimed = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 cumulativeAmount = _rewards.get(earner, token);
            uint256 tosend = cumulativeAmount - claimed[earner][token];
            claimed[earner][token] = cumulativeAmount;
            // send token
            if (tosend > 0) {
                if (externalPayoutAddress == address(0)) {
                    IERC20(token).safeTransfer(to, tosend);
                } else {
                    require(msg.sender == externalPayoutAddress, "unauthorized caller");
                }
                tokenClaimedRewards[token] += tosend;
                hasUnclaimed = true;
            }
            claimedRewards[i] = tosend;
        }
        require(hasUnclaimed, "no unclaimed rewards");
        emit RewardsClaimed(earner, claimedRewards);
        return (tokens, claimedRewards);
    }
}
