// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/Hashes.sol";

import "../AddRewards.sol";
import "../Whitelist.sol";
import "../BrevisProofApp.sol";
import "../lib/EnumerableMap.sol";

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

// submit campaign rewards on chain Y
contract RewardsSubmission is AddRewards, Whitelist, BrevisProofApp {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableMap for EnumerableMap.UserTokenAmountMap;

    uint64 public constant GRACE_PERIOD = 3600 * 24 * 10; // seconds after campaign end

    enum State {
        EpochInit,
        RewardsSubmission,
        SubRootsGeneration,
        TopRootGeneration
    }

    State public state;
    uint64 public currEpoch;

    Config public config;
    mapping(uint8 => bytes32) public vkMap; // from circuit id to its vkhash

    // Storage for merkle roots generation
    EnumerableSet.Bytes32Set subRoots;
    uint256[] subRootUserIndexStart;
    bytes32 public topRoot;

    event SubRootLeafProcessed(
        uint64 indexed epoch,
        uint256 indexed subRootIndex,
        uint256 indexed leafIndex,
        address user,
        uint256[] cumulativeRewards,
        bytes32 leafHash
    );
    event SubRootGenerated(uint64 indexed epoch, uint256 indexed subRootIndex, bytes32 subRoot);
    event AllSubRootsGenerated(uint64 indexed epoch);
    event TopRootGenerated(uint64 indexed epoch, bytes32 topRoot);

    // called by proxy to properly set storage of proxy contract, owner is contract owner (hw or multisig)
    function init(Config calldata cfg, IBrevisProof _brv, address owner, bytes32[] calldata vks) external {
        initOwner(owner);
        address[] memory _tokens = new address[](cfg.rewards.length);
        for (uint256 i = 0; i < cfg.rewards.length; i++) {
            _tokens[i] = cfg.rewards[i].token;
        }
        _initTokens(_tokens);
        config = cfg;
        brevisProof = _brv;
        // 1: TotalFee 2: Rewards 3+: Others
        for (uint8 i = 0; i < vks.length; i++) {
            vkMap[i + 1] = vks[i];
        }
    }

    // ----------- state transition -----------
    function startEpoch(uint64 epoch) external onlyWhitelisted {
        require(state == State.EpochInit, "invalid state");
        currEpoch = epoch;
        state = State.RewardsSubmission;

        subRoots.clear();
    }

    function startSubRootGen(uint64 epoch) external onlyWhitelisted {
        require(state == State.RewardsSubmission, "invalid state");
        currEpoch = epoch;
        state = State.SubRootsGeneration;
    }

    // ----------- Rewards Submission -----------
    // _appOutput is 1(totalfee app id), pooladdr, epoch, t0, t1
    function updateTotalFee(bytes calldata _proof, bytes calldata _appOutput) external onlyWhitelisted {
        require(state == State.RewardsSubmission, "invalid state");
        _checkProof(_proof, _appOutput);
        address pooladdr = address(bytes20(_appOutput[1:21]));
        require(pooladdr == config.pooladdr, "mismatch pool addr");
        _updateFee(_appOutput[21:]);
    }

    // update rewards map w/ zk proof, _appOutput is 2(reward app id), t0, t1, [earner:amt u128:amt u128]
    function updateRewards(bytes calldata _proof, bytes calldata _appOutput) external onlyWhitelisted {
        require(state == State.RewardsSubmission, "invalid state");
        _checkProof(_proof, _appOutput);
        _addRewards(_appOutput[1:], true);
    }

    // update rewards map w/ zk proof, _appOutput is x(indirect reward app id), indirect addr, [earner:amt u128:amt u128]
    function updateIndirectRewards(bytes calldata _proof, bytes calldata _appOutput) external onlyWhitelisted {
        require(state == State.RewardsSubmission, "invalid state");
        _checkProof(_proof, _appOutput);
        _addIndirectRewards(_appOutput[1:], true);
    }

    function _checkProof(bytes calldata _proof, bytes calldata _appOutput) internal {
        uint8 appid = uint8(_appOutput[0]);
        _checkBrevisProof(uint64(block.chainid), _proof, _appOutput, vkMap[appid]);
    }

    function setVk(uint8 appid, bytes32 _vk) external onlyOwner {
        vkMap[appid] = _vk;
    }

    // ----------- Merkle Roots Generation -----------

    /**
     * @notice Generates and records a Merkle root for a subset of users up to `nLeaves`.
     *         Should be called repeatedly until every user is covered in a subtree.
     * @param epoch The epoch.
     * @param nLeaves The maximal number of users to include in the current subtree.
     */
    function genSubRoot(uint64 epoch, uint256 nLeaves) external {
        require(state == State.SubRootsGeneration, "invalid state");
        require(epoch == currEpoch, "invalid epoch");

        require(nLeaves <= 2 ** 32, "too many leaves");

        uint256 subRootIndex = subRoots.length();
        uint256 indexStart = 0;
        if (subRootIndex == 0) {
            delete subRootUserIndexStart;
        } else {
            indexStart = subRootUserIndexStart[subRootIndex - 1];
        }

        uint256 maxNLeaves = rewards.length() - indexStart;
        if (nLeaves > maxNLeaves) {
            nLeaves = maxNLeaves;
        }
        bytes32[] memory hashes = new bytes32[](nLeaves);
        uint256 numTokens = tokens.length;
        for (uint256 i = 0; i < nLeaves; i++) {
            (address user, address[] memory rewardTokens, uint256[] memory rewardAmounts) =
                getRewardUserTokenAmountsAt(indexStart + i, numTokens);
            bytes32 leafHash = keccak256(abi.encodePacked(user, rewardTokens, rewardAmounts));
            hashes[i] = leafHash;
            emit SubRootLeafProcessed(epoch, subRootIndex, i, user, rewardAmounts, leafHash);
        }
        bytes32 subRoot = genMerkleRoot(hashes);
        subRoots.add(subRoot);
        emit SubRootGenerated(epoch, subRootIndex, subRoot);

        if (nLeaves == maxNLeaves) {
            state = State.TopRootGeneration;
            emit AllSubRootsGenerated(epoch);
        } else {
            subRootUserIndexStart.push(indexStart + nLeaves);
        }
    }

    /**
     * @notice Generates and records the top Merkle tree root, using the subtree roots as leaves.
     * @param epoch The epoch.
     */
    function genTopRoot(uint64 epoch) external {
        require(state == State.SubRootsGeneration, "invalid state");
        require(epoch == currEpoch, "invalid epoch");

        topRoot = genMerkleRoot(subRoots.values());

        currEpoch++;
        state = State.EpochInit;
    }

    function genMerkleRoot(bytes32[] memory hashes) internal pure returns (bytes32) {
        if (hashes.length == 0) {
            return bytes32(0);
        }
        while (hashes.length > 1) {
            bytes32[] memory nextHashes = new bytes32[]((hashes.length + 1) / 2);
            uint256 i;
            for (; i < hashes.length - 1; i += 2) {
                nextHashes[i / 2] = Hashes.commutativeKeccak256(hashes[i], hashes[i + 1]);
            }
            if (i == hashes.length - 1) {
                nextHashes[i / 2] = hashes[i];
            }
            hashes = nextHashes;
        }
        return hashes[0];
    }

    function getRewardUserTokenAmountsAt(uint256 index, uint256 numTokens)
        internal
        view
        returns (address, address[] memory, uint256[] memory)
    {
        (address user, mapping(address => uint256) storage tokenAmountMap) = rewards.at(index);
        address[] memory rewardTokens = new address[](numTokens);
        uint256[] memory rewardAmounts = new uint256[](numTokens);
        for (uint256 j = 0; j < numTokens; j++) {
            rewardTokens[j] = tokens[j];
            rewardAmounts[j] = tokenAmountMap[rewardTokens[j]];
        }
        return (user, rewardTokens, rewardAmounts);
    }
}
