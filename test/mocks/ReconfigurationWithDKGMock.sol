// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import "@src/interfaces/IReconfigurationWithDKG.sol";

contract ReconfigurationWithDKGMock is IReconfigurationWithDKG {
    // State variables
    bool private _initialized;
    bool private _reconfigurationInProgress;

    // Mock control variables
    bool public shouldFailTryStart;
    bool public shouldFailFinish;
    bool public shouldFailFinishWithDkgResult;

    function initialize() external override {
        _initialized = true;
    }

    function tryStart() external override {
        require(!shouldFailTryStart, "ReconfigurationWithDKGMock: tryStart failed");
        _reconfigurationInProgress = true;
    }

    function finish() external override {
        require(!shouldFailFinish, "ReconfigurationWithDKGMock: finish failed");
        _reconfigurationInProgress = false;
    }

    function finishWithDkgResult(
        bytes calldata dkgResult
    ) external override {
        require(!shouldFailFinishWithDkgResult, "ReconfigurationWithDKGMock: finishWithDkgResult failed");
        _reconfigurationInProgress = false;
    }

    function isReconfigurationInProgress() external view override returns (bool) {
        return _reconfigurationInProgress;
    }

    // Mock control functions
    function setShouldFailTryStart(
        bool _shouldFail
    ) external {
        shouldFailTryStart = _shouldFail;
    }

    function setShouldFailFinish(
        bool _shouldFail
    ) external {
        shouldFailFinish = _shouldFail;
    }

    function setShouldFailFinishWithDkgResult(
        bool _shouldFail
    ) external {
        shouldFailFinishWithDkgResult = _shouldFail;
    }

    function setReconfigurationInProgress(
        bool _inProgress
    ) external {
        _reconfigurationInProgress = _inProgress;
    }
}
