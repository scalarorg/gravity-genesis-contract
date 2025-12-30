// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

contract System {
    bool public alreadyInit;

    uint8 internal constant CODE_OK = 0;
    /*----------------- constants -----------------*/
    address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public constant GENESIS_ADDR = 0x0000000000000000000000000000000000002008;
    address public constant SYSTEM_CALLER = 0x0000000000000000000000000000000000002000;
    address internal constant PERFORMANCE_TRACKER_ADDR = 0x000000000000000000000000000000000000200f;
    address internal constant EPOCH_MANAGER_ADDR = 0x0000000000000000000000000000000000002010;
    address internal constant STAKE_CONFIG_ADDR = 0x0000000000000000000000000000000000002011;
    address internal constant DELEGATION_ADDR = 0x0000000000000000000000000000000000002012;
    address internal constant VALIDATOR_MANAGER_ADDR = 0x0000000000000000000000000000000000002013;
    address internal constant VALIDATOR_MANAGER_UTILS_ADDR = 0x0000000000000000000000000000000000002014;
    address internal constant VALIDATOR_PERFORMANCE_TRACKER_ADDR = 0x0000000000000000000000000000000000002015;
    address internal constant BLOCK_ADDR = 0x0000000000000000000000000000000000002016;
    address internal constant TIMESTAMP_ADDR = 0x0000000000000000000000000000000000002017;
    address internal constant JWK_MANAGER_ADDR = 0x0000000000000000000000000000000000002018;
    address internal constant KEYLESS_ACCOUNT_ADDR = 0x0000000000000000000000000000000000002019;
    address internal constant SYSTEM_REWARD_ADDR = 0x000000000000000000000000000000000000201A;
    address internal constant GOV_HUB_ADDR = 0x000000000000000000000000000000000000201b;
    address internal constant STAKE_CREDIT_ADDR = 0x000000000000000000000000000000000000201c;
    address internal constant GOV_TOKEN_ADDR = 0x000000000000000000000000000000000000201D;
    address internal constant GOVERNOR_ADDR = 0x000000000000000000000000000000000000201E;
    address internal constant TIMELOCK_ADDR = 0x000000000000000000000000000000000000201F;
    address internal constant RANDOMNESS_CONFIG_ADDR = 0x0000000000000000000000000000000000002020;
    address internal constant DKG_ADDR = 0x0000000000000000000000000000000000002021;
    address internal constant RECONFIGURATION_WITH_DKG_ADDR = 0x0000000000000000000000000000000000002022;
    address internal constant HASH_ORACLE_ADDR = 0x0000000000000000000000000000000000002023;
    address internal constant SYSTEM_CONTRACT_ADDR = 0x00000000000000000000000000000000000020FF;

    /*----------------- errors -----------------*/
    error OnlySystemCaller(address errorAddress);
    // @notice signature: 0x97b88354
    error UnknownParam(string key, bytes value);
    // @notice signature: 0x0a5a6041
    error InvalidValue(string key, bytes value);
    // @notice signature: 0x116c64a8
    error OnlyCoinbase();
    // @notice signature: 0x83f1b1d3
    error OnlyZeroGasPrice();
    // @notice signature: 0xf22c4390
    error OnlySystemContract(address systemContract);

    /*----------------- events -----------------*/
    event ParamChange(string key, bytes value);

    /*----------------- modifiers -----------------*/
    modifier onlySystemCaller() {
        if (msg.sender != SYSTEM_CALLER) revert OnlySystemCaller(msg.sender);
        _;
    }

    modifier onlyJWKManager() {
        if (msg.sender != JWK_MANAGER_ADDR) revert OnlySystemContract(JWK_MANAGER_ADDR);
        _;
    }

    modifier onlyValidatorManager() {
        if (msg.sender != VALIDATOR_MANAGER_ADDR) revert OnlySystemContract(VALIDATOR_MANAGER_ADDR);
        _;
    }

    modifier onlyEpochManager() {
        if (msg.sender != EPOCH_MANAGER_ADDR) revert OnlySystemContract(EPOCH_MANAGER_ADDR);
        _;
    }

    modifier onlyBlock() {
        if (msg.sender != BLOCK_ADDR) revert OnlySystemContract(BLOCK_ADDR);
        _;
    }

    modifier onlyDelegation() {
        if (msg.sender != DELEGATION_ADDR) revert OnlySystemContract(DELEGATION_ADDR);
        _;
    }

    modifier onlyDelegationOrValidatorManager() {
        if (msg.sender != DELEGATION_ADDR && msg.sender != VALIDATOR_MANAGER_ADDR) {
            revert OnlySystemContract(msg.sender == DELEGATION_ADDR ? DELEGATION_ADDR : VALIDATOR_MANAGER_ADDR);
        }
        _;
    }

    modifier onlyGenesis() {
        if (msg.sender != GENESIS_ADDR) revert OnlySystemContract(GENESIS_ADDR);
        _;
    }

    modifier onlyNotInit() {
        require(!alreadyInit, "the contract already init");
        _;
    }

    modifier onlyInit() {
        require(alreadyInit, "the contract not init yet");
        _;
    }

    modifier onlyGov() {
        if (msg.sender != GOV_HUB_ADDR && msg.sender != SYSTEM_CALLER) revert OnlySystemContract(GOV_HUB_ADDR);
        _;
    }

    modifier onlyGovernorTimelock() {
        require(msg.sender == TIMELOCK_ADDR, "the msg sender must be governor timelock contract");
        _;
    }

    modifier onlySystemJWKCaller() {
        if (
            msg.sender != address(this) // ValidatorManager itself
                && msg.sender != JWK_MANAGER_ADDR // JWKManager
                && msg.sender != SYSTEM_CALLER
        ) {
            revert OnlySystemContract(msg.sender);
        }
        _;
    }
}
