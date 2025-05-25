// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

import "../../access/AccessControl.sol";
import "./message/MessageReceiverApp.sol";

struct AddrAmt {
    address token;
    uint256 amount;
}

struct Config {
    address creator;
    uint64 startTime;
    uint32 duration; // how many seconds this campaign is active, end after startTime+duration
    AddrAmt[] rewards; // list of [reward token and total amount]
    // If set, only this address can call claim; rewards are not transferred directly, external address handles payout.
    address externalPayoutAddress;
}

// claim campaign rewards on chain one chain, which was submitted on another chain
contract CampaignRewardsClaim is AccessControl, MessageReceiverApp {
    using SafeERC20 for IERC20;

    // e844ed9e40aeb388cb97d2ef796e81de635718f440751efb46753791698f6bde
    bytes32 public constant ROOT_UPDATER_ROLE = keccak256("root_updater");

    // seconds after campaign end, after which all remaining balance can be refunded to creator
    uint64 public gracePeriod = 3600 * 24 * 180; // default 180 days
    Config public config;

    // user -> token -> claimed amount
    mapping(address => mapping(address => uint256)) public claimed;
    // token -> total claimed amount
    mapping(address => uint256) public tokenClaimedRewards;

    uint64 public epoch;
    bytes32 public topRoot;

    uint64 public submissionChainId;
    address public submissionAddress;

    event TopRootUpdated(uint64 indexed epoch, bytes32 topRoot);
    event RewardsClaimed(address indexed earner, uint256[] newAmount, uint256[] cumulativeAmounts);
    event GracePeriodUpdated(uint64 gracePeriod);
    event MessageBusUpdated(address messageBus);
    event SubmissionContractUpdated(uint64 submissionChainId, address submissionAddress);

    function init(
        Config calldata cfg,
        address owner,
        address root_updater,
        address _messageBus,
        uint64 _submissionChainId,
        address _submissionAddress
    ) external {
        initOwner(owner);
        grantRole(ROOT_UPDATER_ROLE, root_updater);
        config = cfg;
        messageBus = _messageBus;
        submissionChainId = _submissionChainId;
        submissionAddress = _submissionAddress;
    }

    // after grace period, refund all remaining balance to creator
    function refund() external {
        Config memory cfg = config;
        require(block.timestamp > cfg.startTime + cfg.duration + gracePeriod, "too soon");
        for (uint256 i = 0; i < cfg.rewards.length; i++) {
            address token = cfg.rewards[i].token;
            IERC20(token).safeTransfer(cfg.creator, IERC20(token).balanceOf(address(this)));
        }
    }

    function canRefund() external view returns (bool) {
        return block.timestamp > config.startTime + config.duration + gracePeriod;
    }

    // claim reward, send erc20 to earner
    function claim(address earner, uint256[] calldata cumulativeAmounts, uint64 _epoch, bytes32[] calldata proof)
        external
        returns (address[] memory, uint256[] memory)
    {
        return _claim(earner, earner, cumulativeAmounts, _epoch, proof);
    }

    // msg.sender is the earner
    function claimWithRecipient(
        address to,
        uint256[] calldata cumulativeAmounts,
        uint64 _epoch,
        bytes32[] calldata proof
    ) external returns (address[] memory, uint256[] memory) {
        return _claim(msg.sender, to, cumulativeAmounts, _epoch, proof);
    }

    /**
     * @notice Updates the epoch and top Merkle root info
     * @param _epoch The epoch number.
     * @param _topRoot The Merkle root for the top tree.
     */
    function updateRoot(uint64 _epoch, bytes32 _topRoot) external onlyRole(ROOT_UPDATER_ROLE) {
        _updateRoot(_epoch, _topRoot);
    }

    // called by MessageBus contract to receive cross-chain message from the rewards submission contract
    function _executeMessage(address _srcContract, uint64 _srcChainId, bytes calldata _message) internal override {
        require(_srcChainId == submissionChainId, "invalid source chain");
        require(_srcContract == submissionAddress, "invalid source contract");
        (uint64 _epoch, bytes32 _topRoot) = abi.decode((_message), (uint64, bytes32));
        require(_epoch > epoch, "invalid epoch");
        _updateRoot(_epoch, _topRoot);
    }

    function getTokens() public view returns (address[] memory) {
        address[] memory tokens = new address[](config.rewards.length);
        for (uint256 i = 0; i < config.rewards.length; i++) {
            tokens[i] = config.rewards[i].token;
        }
        return tokens;
    }

    function viewClaimedRewards(address earner) external view returns (AddrAmt[] memory) {
        address[] memory tokens = getTokens();
        AddrAmt[] memory ret = new AddrAmt[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            ret[i] = AddrAmt({token: tokens[i], amount: claimed[earner][tokens[i]]});
        }
        return ret;
    }

    // ----- admin functions -----
    function setSubmissionContract(uint64 _submissionChainId, address _submissionAddress) external onlyOwner {
        submissionChainId = _submissionChainId;
        submissionAddress = _submissionAddress;
        emit SubmissionContractUpdated(_submissionChainId, _submissionAddress);
    }

    function setMessageBus(address _messageBus) external onlyOwner {
        messageBus = _messageBus;
        emit MessageBusUpdated(_messageBus);
    }

    function setGracePeriod(uint64 _gracePeriod) external onlyOwner {
        gracePeriod = _gracePeriod;
        emit GracePeriodUpdated(_gracePeriod);
    }

    // ------------------------------------------
    // -----------  private functions -----------
    /**
     * @notice Claims rewards for a user using a combined sub tree + top tree Merkle proof.
     * @param earner The earner address.
     * @param to Reward recipient address.
     * @param cumulativeAmounts The cumulative reward amount.
     * @param _epoch The epoch of the proof
     * @param proof The Merkle proof from the sub tree leaf node to the top tree root.
     */
    function _claim(
        address earner,
        address to,
        uint256[] memory cumulativeAmounts,
        uint64 _epoch,
        bytes32[] memory proof
    ) private returns (address[] memory, uint256[] memory) {
        require(_epoch == epoch, "invalid epoch");
        address[] memory tokens = getTokens();
        bytes32 leafHash = keccak256(abi.encodePacked(earner, tokens, cumulativeAmounts));
        require(verifyMerkleProof(proof, topRoot, leafHash), "verification failed");

        uint256[] memory newAmount = new uint256[](tokens.length);
        bool hasUnclaimed = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            address erc20 = tokens[i];
            uint256 tosend = cumulativeAmounts[i] - claimed[earner][erc20];
            claimed[earner][erc20] = cumulativeAmounts[i];
            // send token
            if (tosend > 0) {
                if (config.externalPayoutAddress == address(0)) {
                    IERC20(erc20).safeTransfer(to, tosend);
                } else {
                    require(msg.sender == config.externalPayoutAddress, "unauthorized caller");
                }
                tokenClaimedRewards[erc20] += tosend;
                hasUnclaimed = true;
            }
            newAmount[i] = tosend;
        }
        require(hasUnclaimed, "no unclaimed rewards");
        emit RewardsClaimed(earner, newAmount, cumulativeAmounts);
        return (tokens, newAmount);
    }

    function _updateRoot(uint64 _epoch, bytes32 _topRoot) private {
        epoch = _epoch;
        topRoot = _topRoot;
        emit TopRootUpdated(epoch, topRoot);
    }

    function verifyMerkleProof(bytes32[] memory proof, bytes32 root, bytes32 leafHash) private pure returns (bool) {
        bytes32 hash = leafHash;
        for (uint256 i = 0; i < proof.length; i++) {
            hash = Hashes.commutativeKeccak256(hash, proof[i]);
        }
        return hash == root;
    }
}
