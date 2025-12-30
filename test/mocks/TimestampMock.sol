// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract TimestampMock {
    struct UpdateCall {
        address proposer;
        uint64 timestampMicros;
        uint256 callCount;
    }

    UpdateCall public lastCall;
    uint256 public totalCalls;
    uint64 public mockCurrentTime; // Mock current time in seconds
    bool public initialized;

    function initialize() external {
        // Allow GENESIS_ADDR, SYSTEM_CALLER, and any contract to call initialize
        // This is for testing purposes - in real deployment, only GENESIS_ADDR should be allowed
        initialized = true;
        mockCurrentTime = 1; // Set initial time
    }

    function updateGlobalTime(
        address proposer,
        uint64 timestampMicros
    ) external {
        lastCall.proposer = proposer;
        lastCall.timestampMicros = timestampMicros;
        lastCall.callCount++;
        totalCalls++;
    }

    function getLastUpdateCall() external view returns (address proposer, uint64 timestampMicros, uint256 callCount) {
        return (lastCall.proposer, lastCall.timestampMicros, lastCall.callCount);
    }

    function setCurrentTime(
        uint256 timeInSeconds
    ) external {
        mockCurrentTime = uint64(timeInSeconds);
    }

    function nowSeconds() external view returns (uint64) {
        return mockCurrentTime;
    }

    function setNowMicroseconds(
        uint64 timeInMicros
    ) external {
        mockCurrentTime = timeInMicros;
    }

    function nowMicroseconds() external view returns (uint64) {
        return mockCurrentTime;
    }

    function reset() external {
        delete lastCall;
        totalCalls = 0;
        mockCurrentTime = 0;
        mockCurrentTime = 0;
    }
}
