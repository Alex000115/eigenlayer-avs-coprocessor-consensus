// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CoprocessorConsensusRegistry
 * @dev Reconciles multi-operator consensus states for verified off-chain co-processing execution logs.
 */
contract CoprocessorConsensusRegistry is Ownable {

    struct StateCommitment {
        bytes32 dataRootHash;
        uint32 supportingWeight;
        bool structuralSettlementAchieved;
    }

    mapping(uint256 => StateCommitment) public batchCommitments;
    mapping(address => uint32) public operatorStakeWeights;
    
    uint32 public totalRestakedNetworkWeight;
    uint32 public constant BYZANTINE_THRESHOLD_PCT = 66; // Standard 2/3rds supermajority target

    event ConsensusReached(uint256 indexed batchId, bytes32 dataRootHash);
    event VoteLogged(uint256 indexed batchId, address indexed operator, uint32 weight);

    constructor() Ownable(msg.sender) {}

    function setOperatorWeight(address operator, uint32 weight) external onlyOwner {
        totalRestakedNetworkWeight -= operatorStakeWeights[operator];
        operatorStakeWeights[operator] = weight;
        totalRestakedNetworkWeight += weight;
    }

    /**
     * @notice Casts an operator vote for a specific computation state root outcome.
     */
    function submitConsensusVote(uint256 batchId, bytes32 computedRoot) external {
        uint32 weight = operatorStakeWeights[msg.sender];
        require(weight > 0, "ConsensusError: Unregistered or empty weight operator");
        
        StateCommitment storage allocation = batchCommitments[batchId];
        require(!allocation.structuralSettlementAchieved, "ConsensusError: Batch already finalized");

        if (allocation.dataRootHash == bytes32(0)) {
            allocation.dataRootHash = computedRoot;
        } else {
            require(allocation.dataRootHash == computedRoot, "ConsensusError: Byzantine state split detected");
        }

        allocation.supportingWeight += weight;
        emit VoteLogged(batchId, msg.sender, weight);

        // Evaluate supermajority parameters
        uint32 achievedPct = (allocation.supportingWeight * 100) / totalRestakedNetworkWeight;
        if (achievedPct >= BYZANTINE_THRESHOLD_PCT) {
            allocation.structuralSettlementAchieved = true;
            emit ConsensusReached(batchId, computedRoot);
        }
    }
}
