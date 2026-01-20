// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/interfaces/IValidatorPerformanceTracker.sol";
import "@src/interfaces/IValidatorManager.sol";
import "@src/interfaces/IEpochManager.sol";
import "@src/interfaces/ITimestamp.sol";
import "@src/interfaces/IBlock.sol";
import "@src/interfaces/IReconfigurationWithDKG.sol";
import "@openzeppelin-upgrades/proxy/utils/Initializable.sol";

contract Block is System, IBlock, Initializable {
    /// @inheritdoc IBlock
    function initialize() external initializer onlyGenesis {
        _emitGenesisBlockEvent();
    }

    /// @inheritdoc IBlock
    function blockPrologue(
        bytes calldata proposer,
        uint64[] calldata failedProposerIndices,
        uint64 timestampMicros
    ) external onlySystemCaller {
        // Check if proposer is VM reserved address (32 bytes of zeros)
        bytes32 vmReservedProposer = bytes32(0);
        bool isVmReserved =
            proposer.length == 32 && keccak256(proposer) == keccak256(abi.encodePacked(vmReservedProposer));

        address validatorAddress;
        uint64 proposerIndex;

        if (isVmReserved) {
            // VM reserved address
            validatorAddress = SYSTEM_CALLER;
            proposerIndex = type(uint64).max;
        } else {
            // Get validator address and index (will revert if proposer is invalid)
            (validatorAddress, proposerIndex) =
                IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorByProposer(proposer);
        }

        // Update global timestamp
        ITimestamp(TIMESTAMP_ADDR).updateGlobalTime(validatorAddress, uint64(timestampMicros));

        // Update validator performance statistics
        IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR)
            .updatePerformanceStatistics(proposerIndex, failedProposerIndices);

        // Check if epoch transition is needed
        if (IEpochManager(EPOCH_MANAGER_ADDR).canTriggerEpochTransition()) {
            IEpochManager(EPOCH_MANAGER_ADDR).triggerEpochTransition();
        }
    }

    /// @inheritdoc IBlock
    function blockPrologueExt(
        bytes calldata proposer,
        uint64[] calldata failedProposerIndices,
        uint64 timestampMicros
    ) external onlySystemCaller {
        // Check if proposer is VM reserved address (32 bytes of zeros)
        bytes32 vmReservedProposer = bytes32(0);
        bool isVmReserved =
            proposer.length == 32 && keccak256(proposer) == keccak256(abi.encodePacked(vmReservedProposer));

        address validatorAddress;
        uint64 proposerIndex;

        if (isVmReserved) {
            // VM reserved address
            validatorAddress = SYSTEM_CALLER;
            proposerIndex = type(uint64).max;
        } else {
            // Get validator address and index (will revert if proposer is invalid)
            (validatorAddress, proposerIndex) =
                IValidatorManager(VALIDATOR_MANAGER_ADDR).getValidatorByProposer(proposer);
        }

        // Update global timestamp
        ITimestamp(TIMESTAMP_ADDR).updateGlobalTime(validatorAddress, uint64(timestampMicros));

        // Update validator performance statistics
        IValidatorPerformanceTracker(VALIDATOR_PERFORMANCE_TRACKER_ADDR)
            .updatePerformanceStatistics(proposerIndex, failedProposerIndices);

        // 5. Check if epoch transition is needed and trigger DKG if necessary
        if (IEpochManager(EPOCH_MANAGER_ADDR).canTriggerEpochTransition()) {
            // Try to start DKG reconfiguration process
            IReconfigurationWithDKG(RECONFIGURATION_WITH_DKG_ADDR).tryStart();
        }
    }

    /**
     * @dev Emit genesis block event. This function will be called directly during genesis
     * to generate the first reconfiguration event.
     */
    function _emitGenesisBlockEvent() private {
        address genesisId = address(0);
        uint64[] memory emptyFailedProposerIndices = new uint64[](0);

        emit NewBlockEvent(
            genesisId, // hash: genesis_id
            0, // epoch: 0
            0, // round: 0
            0, // height: 0
            bytes(""), // previous_block_votes_bitvec: empty
            SYSTEM_CALLER, // proposer: @vm_reserved
            emptyFailedProposerIndices, // failed_proposer_indices: empty
            0 // time_microseconds: 0
        );

        // Initialize global timestamp to 0
        ITimestamp(TIMESTAMP_ADDR).updateGlobalTime(SYSTEM_CALLER, 0);
    }
}
