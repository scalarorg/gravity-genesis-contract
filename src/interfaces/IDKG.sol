// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/interfaces/IRandomnessConfig.sol";

/**
 * @title IDKG
 * @dev Interface for DKG (Distributed Key Generation) operations
 */
interface IDKG {
    // Struct for fixed point 64 representation
    struct FixedPoint64 {
        uint128 value;
    }

    // Struct for randomness config variant indicating the feature is enabled with fast path
    struct Config {
        FixedPoint64 secrecyThreshold;
        FixedPoint64 reconstructionThreshold;
        FixedPoint64 fastPathSecrecyThreshold;
    }

    // Use RandomnessConfig from IRandomnessConfig interface
    // This provides a more complete configuration structure with variants
    // For compatibility, we also keep the legacy Config struct

    // Struct for validator consensus information
    struct ValidatorConsensusInfo {
        bytes aptosAddress;
        bytes pkBytes;
        uint64 votingPower;
    }

    // DKG session metadata - can be considered as the public input of DKG
    struct DKGSessionMetadata {
        uint64 dealerEpoch;
        IRandomnessConfig.RandomnessConfigData randomnessConfig;
        ValidatorConsensusInfo[] dealerValidatorSet;
        ValidatorConsensusInfo[] targetValidatorSet;
    }

    // The input and output of a DKG session
    struct DKGSessionState {
        DKGSessionMetadata metadata;
        uint64 startTimeUs;
        bytes transcript;
    }

    // DKG contract state
    struct DKGState {
        DKGSessionState lastCompleted;
        bool hasLastCompleted;
        DKGSessionState inProgress;
        bool hasInProgress;
    }

    // Events
    event DKGStartEvent(DKGSessionMetadata sessionMetadata, uint64 startTimeUs);

    // Errors
    error DKGInProgress();
    error DKGNotInProgress();
    error DKGNotInitialized();
    error NotAuthorized(address caller);

    /**
     * @dev Initialize the DKG contract
     */
    function initialize() external;

    /**
     * @dev Start a DKG session
     * @param dealerEpoch The epoch of the dealer
     * @param randomnessConfig The randomness configuration
     * @param dealerValidatorSet The validator set for the dealer epoch
     * @param targetValidatorSet The target validator set for the next epoch
     */
    function start(
        uint64 dealerEpoch,
        IRandomnessConfig.RandomnessConfigData memory randomnessConfig,
        ValidatorConsensusInfo[] memory dealerValidatorSet,
        ValidatorConsensusInfo[] memory targetValidatorSet
    ) external;

    /**
     * @dev Finish a DKG session with transcript
     * @param transcript The DKG transcript
     */
    function finish(
        bytes memory transcript
    ) external;

    /**
     * @dev Clear incomplete DKG session if it exists
     */
    function tryClearIncompleteSession() external;

    /**
     * @dev Get incomplete DKG session
     * @return hasSession Whether there is an incomplete session
     * @return session The incomplete session state
     */
    function incompleteSession() external view returns (bool hasSession, DKGSessionState memory session);

    /**
     * @dev Check if DKG is in progress
     * @return True if DKG is in progress
     */
    function isDKGInProgress() external view returns (bool);

    /**
     * @dev Get last completed session
     * @return hasSession Whether there is a last completed session
     * @return session The last completed session
     */
    function lastCompletedSession() external view returns (bool hasSession, DKGSessionState memory session);

    /**
     * @dev Get dealer epoch from session state
     * @param session The DKG session state
     * @return The dealer epoch
     */
    function sessionDealerEpoch(
        DKGSessionState memory session
    ) external pure returns (uint64);
}
