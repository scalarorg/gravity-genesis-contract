// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/System.sol";
import "@src/access/Protectable.sol";
import "@src/interfaces/IDKG.sol";
import "@src/interfaces/ITimestamp.sol";

/**
 * @title DKG
 * @dev DKG on-chain states and helper functions
 * @notice This contract manages DKG sessions for validator set transitions
 */
contract DKG is System, Protectable, IDKG {
    // Error codes
    uint64 constant EDKG_IN_PROGRESS = 1;
    uint64 constant EDKG_NOT_IN_PROGRESS = 2;

    // State variables
    IDKG.DKGState private _state;
    bool private _initialized;

    // Modifiers
    modifier onlyAuthorizedCallers() {
        if (
            msg.sender != SYSTEM_CALLER && msg.sender != BLOCK_ADDR && msg.sender != GENESIS_ADDR
                && msg.sender != RECONFIGURATION_WITH_DKG_ADDR
        ) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    modifier whenDKGNotInProgress() {
        if (_state.hasInProgress) revert DKGInProgress();
        _;
    }

    modifier whenDKGInProgress() {
        if (!_state.hasInProgress) revert DKGNotInProgress();
        _;
    }

    modifier onlyInitialized() {
        if (!_initialized) revert DKGNotInitialized();
        _;
    }

    /// @inheritdoc IDKG
    function initialize() external onlyGenesis {
        if (_initialized) revert DKGNotInitialized();
        _initialized = true;
        _state.hasLastCompleted = false;
        _state.hasInProgress = false;
    }

    /// @inheritdoc IDKG
    function start(
        uint64 dealerEpoch,
        IRandomnessConfig.RandomnessConfigData memory randomnessConfig,
        ValidatorConsensusInfo[] memory dealerValidatorSet,
        ValidatorConsensusInfo[] memory targetValidatorSet
    ) external onlyAuthorizedCallers whenNotPaused whenDKGNotInProgress onlyInitialized {
        DKGSessionMetadata memory newSessionMetadata = DKGSessionMetadata({
            dealerEpoch: dealerEpoch,
            randomnessConfig: randomnessConfig,
            dealerValidatorSet: dealerValidatorSet,
            targetValidatorSet: targetValidatorSet
        });

        uint64 startTimeUs = uint64(ITimestamp(TIMESTAMP_ADDR).nowMicroseconds());

        _state.inProgress = DKGSessionState({ metadata: newSessionMetadata, startTimeUs: startTimeUs, transcript: "" });
        _state.hasInProgress = true;

        emit DKGStartEvent(newSessionMetadata, startTimeUs);
    }

    /// @inheritdoc IDKG
    function finish(
        bytes memory transcript
    ) external onlyAuthorizedCallers whenNotPaused whenDKGInProgress onlyInitialized {
        // Move in-progress session to completed
        _state.lastCompleted = _state.inProgress;
        _state.lastCompleted.transcript = transcript;
        _state.hasLastCompleted = true;

        // Clear in-progress session
        _state.hasInProgress = false;
    }

    /// @inheritdoc IDKG
    function tryClearIncompleteSession() external onlyAuthorizedCallers whenNotPaused onlyInitialized {
        if (_state.hasInProgress) {
            _state.hasInProgress = false;
        }
    }

    /// @inheritdoc IDKG
    function incompleteSession()
        external
        view
        onlyInitialized
        returns (bool hasSession, DKGSessionState memory session)
    {
        hasSession = _state.hasInProgress;
        if (hasSession) {
            session = _state.inProgress;
        }
    }

    /// @inheritdoc IDKG
    function sessionDealerEpoch(
        DKGSessionState memory session
    ) external pure returns (uint64) {
        return session.metadata.dealerEpoch;
    }

    /// @inheritdoc IDKG
    function isDKGInProgress() external view onlyInitialized returns (bool) {
        return _state.hasInProgress;
    }

    /// @inheritdoc IDKG
    function lastCompletedSession()
        external
        view
        onlyInitialized
        returns (bool hasSession, DKGSessionState memory session)
    {
        hasSession = _state.hasLastCompleted;
        if (hasSession) {
            session = _state.lastCompleted;
        }
    }

    /**
     * @dev Get current DKG state for debugging
     * @return state The current DKG state
     */
    function getDKGState() external view returns (IDKG.DKGState memory state) {
        return _state;
    }
}
