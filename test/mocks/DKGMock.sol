// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/interfaces/IDKG.sol";

contract DKGMock is IDKG {
    // State variables
    IDKG.DKGState private _state;
    bool private _initialized;

    // Mock control variables
    bool public shouldFailStart;
    bool public shouldFailFinish;

    function initialize() external override {
        _initialized = true;
        _state.hasLastCompleted = false;
        _state.hasInProgress = false;
    }

    function start(
        uint64 dealerEpoch,
        IRandomnessConfig.RandomnessConfigData memory randomnessConfig,
        ValidatorConsensusInfo[] memory dealerValidatorSet,
        ValidatorConsensusInfo[] memory targetValidatorSet
    ) external override {
        require(!shouldFailStart, "DKGMock: Start failed");
        require(!_state.hasInProgress, "DKG already in progress");

        DKGSessionMetadata memory metadata = DKGSessionMetadata({
            dealerEpoch: dealerEpoch,
            randomnessConfig: randomnessConfig,
            dealerValidatorSet: dealerValidatorSet,
            targetValidatorSet: targetValidatorSet
        });

        _state.inProgress =
            DKGSessionState({ metadata: metadata, startTimeUs: uint64(block.timestamp * 1000000), transcript: "" });
        _state.hasInProgress = true;

        emit DKGStartEvent(metadata, uint64(block.timestamp * 1000000));
    }

    function finish(
        bytes memory transcript
    ) external override {
        require(!shouldFailFinish, "DKGMock: Finish failed");
        require(_state.hasInProgress, "DKG not in progress");

        _state.lastCompleted = _state.inProgress;
        _state.lastCompleted.transcript = transcript;
        _state.hasLastCompleted = true;

        _state.hasInProgress = false;
    }

    function tryClearIncompleteSession() external override {
        if (_state.hasInProgress) {
            _state.hasInProgress = false;
        }
    }

    function incompleteSession() external view override returns (bool hasSession, DKGSessionState memory session) {
        hasSession = _state.hasInProgress;
        if (hasSession) {
            session = _state.inProgress;
        }
    }

    function sessionDealerEpoch(
        DKGSessionState memory session
    ) external pure override returns (uint64) {
        return session.metadata.dealerEpoch;
    }

    function isDKGInProgress() external view override returns (bool) {
        return _state.hasInProgress;
    }

    function lastCompletedSession() external view override returns (bool hasSession, DKGSessionState memory session) {
        hasSession = _state.hasLastCompleted;
        if (hasSession) {
            session = _state.lastCompleted;
        }
    }

    // Mock control functions
    function setShouldFailStart(
        bool _shouldFail
    ) external {
        shouldFailStart = _shouldFail;
    }

    function setShouldFailFinish(
        bool _shouldFail
    ) external {
        shouldFailFinish = _shouldFail;
    }

    function setInProgressSession(
        DKGSessionState memory session
    ) external {
        _state.inProgress = session;
        _state.hasInProgress = true;
    }

    function setLastCompletedSession(
        DKGSessionState memory session
    ) external {
        _state.lastCompleted = session;
        _state.hasLastCompleted = true;
    }

    function clearSessions() external {
        _state.hasInProgress = false;
        _state.hasLastCompleted = false;
    }
}
