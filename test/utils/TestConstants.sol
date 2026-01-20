// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title TestConstants
 * @dev Centralized constants for testing, extracted from System.sol and custom test values
 */
contract TestConstants {
    // ======== System Contract Addresses (from System.sol) ========
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public constant GENESIS_ADDR = 0x0000000000000000000000000000000000002008;
    address public constant SYSTEM_CALLER = 0x0000000000000000000000000000000000002000;
    address public constant PERFORMANCE_TRACKER_ADDR = 0x000000000000000000000000000000000000200f;
    address public constant EPOCH_MANAGER_ADDR = 0x0000000000000000000000000000000000002010;
    address public constant STAKE_CONFIG_ADDR = 0x0000000000000000000000000000000000002011;
    address public constant DELEGATION_ADDR = 0x0000000000000000000000000000000000002012;
    address public constant VALIDATOR_MANAGER_ADDR = 0x0000000000000000000000000000000000002013;
    address public constant VALIDATOR_MANAGER_UTILS_ADDR = 0x0000000000000000000000000000000000002014;
    address public constant VALIDATOR_PERFORMANCE_TRACKER_ADDR = 0x0000000000000000000000000000000000002015;
    address public constant BLOCK_ADDR = 0x0000000000000000000000000000000000002016;
    address public constant TIMESTAMP_ADDR = 0x0000000000000000000000000000000000002017;
    address public constant JWK_MANAGER_ADDR = 0x0000000000000000000000000000000000002018;
    address public constant KEYLESS_ACCOUNT_ADDR = 0x0000000000000000000000000000000000002019;
    address public constant SYSTEM_REWARD_ADDR = 0x000000000000000000000000000000000000201A;
    address public constant GOV_HUB_ADDR = 0x000000000000000000000000000000000000201b;
    address public constant STAKE_CREDIT_ADDR = 0x000000000000000000000000000000000000201c;
    address public constant GOV_TOKEN_ADDR = 0x000000000000000000000000000000000000201D;
    address public constant GOVERNOR_ADDR = 0x000000000000000000000000000000000000201E;
    address public constant TIMELOCK_ADDR = 0x000000000000000000000000000000000000201F;
    address public constant RANDOMNESS_CONFIG_ADDR = 0x0000000000000000000000000000000000002020;
    address public constant DKG_ADDR = 0x0000000000000000000000000000000000002021;
    address public constant RECONFIGURATION_WITH_DKG_ADDR = 0x0000000000000000000000000000000000002022;

    // ======== Test-Specific Constants ========
    address public constant VALID_PROPOSER = address(0x123);
    address public constant INVALID_PROPOSER = address(0x456);
    address public constant TEST_VALIDATOR_1 = address(0x111111);
    address public constant TEST_VALIDATOR_2 = address(0x222222);
    address public constant TEST_DELEGATOR_1 = address(0x333333);
    address public constant TEST_DELEGATOR_2 = address(0x444444);
    address public constant NOT_SYSTEM_CALLER = address(0x888);
    address public constant NOT_GENESIS = address(0x999);

    // ======== Test Values ========
    uint256 public constant DEFAULT_STAKE_AMOUNT = 1 ether;
    uint256 public constant MIN_STAKE_AMOUNT = 0.1 ether;
    uint256 public constant MAX_STAKE_AMOUNT = 100 ether;
    uint64 public constant DEFAULT_COMMISSION_RATE = 1000; // 10%
    uint64 public constant MAX_COMMISSION_RATE = 5000; // 50%
    uint64 public constant DEFAULT_VALIDATOR_INDEX = 1;
    uint64 public constant DEFAULT_TIMESTAMP_MICROS = 1000000;

    // ======== Gas Values for Testing ========
    uint256 public constant DEFAULT_GAS_LIMIT = 300000;
    uint256 public constant HIGH_GAS_LIMIT = 1000000;
}
