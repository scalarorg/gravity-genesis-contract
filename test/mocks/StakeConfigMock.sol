// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract StakeConfigMock {
    bool public initialized;
    uint256 public votingPowerIncreaseLimit;
    uint256 public MAX_COMMISSION_RATE;

    function initialize() external {
        initialized = true;
    }

    function setVotingPowerIncreaseLimit(
        uint256 _limit
    ) external {
        votingPowerIncreaseLimit = _limit;
    }

    function setMAX_COMMISSION_RATE(
        uint256 _rate
    ) external {
        MAX_COMMISSION_RATE = _rate;
    }
}
