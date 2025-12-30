// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract EpochManagerMock {
    bool public canTriggerEpochTransitionFlag;
    uint256 public triggerEpochTransitionCallCount;
    bool public initialized;
    uint256 public _currentEpoch;

    function initialize() external {
        initialized = true;
        canTriggerEpochTransitionFlag = true; // Default to true for testing
        _currentEpoch = 0;
    }

    function setCanTriggerEpochTransition(
        bool canTrigger
    ) external {
        canTriggerEpochTransitionFlag = canTrigger;
    }

    function canTriggerEpochTransition() external view returns (bool) {
        return canTriggerEpochTransitionFlag;
    }

    function triggerEpochTransition() external {
        triggerEpochTransitionCallCount++;
        _currentEpoch++;
    }

    function reset() external {
        canTriggerEpochTransitionFlag = false;
        triggerEpochTransitionCallCount = 0;
    }

    function currentEpoch() external view returns (uint256) {
        return _currentEpoch;
    }
}
