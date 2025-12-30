# Gravity Genesis Contract Initialization Order

This document describes the correct initialization order and dependencies for all contracts in the Gravity Genesis project.

## Contract Architecture Overview

The Gravity Genesis project contains the following main modules:

### 1. Core System Contracts
- **System.sol** - Core system contract, defines constant addresses and modifiers
- **SystemReward.sol** - System reward contract

### 2. Staking Module (Stake)
- **StakeConfig.sol** - Staking configuration contract
- **ValidatorManager.sol** - Validator management contract
- **ValidatorPerformanceTracker.sol** - Validator performance tracking contract
- **StakeCredit.sol** - Staking credit contract
- **Delegation.sol** - Delegation contract

### 3. Governance Module (Governance)
- **GovToken.sol** - Governance token contract
- **Timelock.sol** - Timelock contract
- **GravityGovernor.sol** - Governance contract
- **GovHub.sol** - Governance hub contract

### 4. Block and Consensus Module
- **Block.sol** - Block processing contract
- **EpochManager.sol** - Epoch management contract
- **Timestamp.sol** - Timestamp contract

### 5. JWK Module
- **JWKManager.sol** - JWK management contract
- **JWKUtils.sol** - JWK utility contract
- **KeylessAccount.sol** - Keyless account contract
- **Groth16Verifier.sol** - Groth16 verifier contract

### 6. Infrastructure
- **Genesis.sol** - Genesis initialization contract
- **Protectable.sol** - Protectable contract
- **Bytes.sol** - Byte utility contract

## Correct Initialization Order

### Phase 1: Core System Contracts
1. **System.sol** - Core system contract
2. **SystemReward.sol** - System reward contract

### Phase 2: Staking Module
3. **StakeConfig.sol** - Staking configuration contract
4. **ValidatorManager.sol** - Validator management contract
5. **ValidatorPerformanceTracker.sol** - Validator performance tracking contract
6. **StakeCredit.sol** - Staking credit contract
7. **Delegation.sol** - Delegation contract

### Phase 3: Governance Module
8. **GovToken.sol** - Governance token contract
9. **Timelock.sol** - Timelock contract
10. **GravityGovernor.sol** - Governance contract
11. **GovHub.sol** - Governance hub contract

### Phase 4: Block and Consensus Module
12. **Timestamp.sol** - Timestamp contract
13. **EpochManager.sol** - Epoch management contract
14. **Block.sol** - Block processing contract

### Phase 5: Oracle Module
15. **HashOracle.sol** - Hash oracle contract
16. **JWKUtils.sol** - JWK utility contract
17. **Groth16Verifier.sol** - Groth16 verifier contract
18. **JWKManager.sol** - JWK management contract
19. **KeylessAccount.sol** - Keyless account contract

### Phase 6: Infrastructure
20. **Protectable.sol** - Protectable contract
21. **Bytes.sol** - Byte utility contract
22. **Genesis.sol** - Genesis initialization contract

## Dependency Relationships

### Key Dependencies
- **ValidatorManager** depends on **StakeConfig**
- **ValidatorPerformanceTracker** depends on **ValidatorManager**
- **EpochManager** depends on **Timestamp** and **ValidatorManager**
- **Block** depends on **ValidatorManager**, **EpochManager**, **Timestamp**, **ValidatorPerformanceTracker**
- **GravityGovernor** depends on **GovToken** and **Timelock**
- **Genesis** depends on all other contracts

### Address Constants
All contract addresses are defined as constants in `System.sol`:
```solidity
address internal constant PERFORMANCE_TRACKER_ADDR = 0x00000000000000000000000000000000000000f1;
address internal constant EPOCH_MANAGER_ADDR = 0x00000000000000000000000000000000000000f3;
address internal constant STAKE_CONFIG_ADDR = 0x0000000000000000000000000000000000002008;
address internal constant DELEGATION_ADDR = 0x0000000000000000000000000000000000002009;
address internal constant VALIDATOR_MANAGER_ADDR = 0x0000000000000000000000000000000000002009;
address internal constant VALIDATOR_PERFORMANCE_TRACKER_ADDR = 0x000000000000000000000000000000000000200b;
address internal constant BLOCK_ADDR = 0x0000000000000000000000000000000000002003;
address internal constant TIMESTAMP_ADDR = 0x0000000000000000000000000000000000002004;
address internal constant JWK_MANAGER_ADDR = 0x0000000000000000000000000000000000002005;
address internal constant KEYLESS_ACCOUNT_ADDR = 0x000000000000000000000000000000000000200A;
address internal constant SYSTEM_REWARD_ADDR = 0x0000000000000000000000000000000000001002;
address internal constant GOV_HUB_ADDR = 0x0000000000000000000000000000000000001007;
address internal constant STAKE_CREDIT_ADDR = 0x0000000000000000000000000000000000002003;
address internal constant GOV_TOKEN_ADDR = 0x0000000000000000000000000000000000002005;
address internal constant GOVERNOR_ADDR = 0x0000000000000000000000000000000000002006;
address internal constant TIMELOCK_ADDR = 0x0000000000000000000000000000000000002007;
```

## Genesis Initialization Process

### 1. Contract Deployment
Deploy all contracts to predefined addresses according to the order above.

### 2. Contract Initialization
Unified initialization of all contracts through the `initialize` function of `Genesis.sol`:

```solidity
function initialize(
    address[] calldata validatorAddresses,
    address[] calldata consensusAddresses,
    address payable[] calldata feeAddresses,
    uint256[] calldata votingPowers,
    bytes[] calldata voteAddresses
) external onlySystemCaller {
    // 1. Initialize staking module
    _initializeStake(validatorAddresses, consensusAddresses, feeAddresses, votingPowers, voteAddresses);
    
    // 2. Initialize epoch module
    _initializeEpoch();
    
    // 3. Initialize governance module
    _initializeGovernance();
    
    // 4. Initialize JWK module
    _initializeJWK();
    
    // 5. Initialize Block contract
    IBlock(BLOCK_ADDR).initialize();
    
    // 6. Trigger first epoch
    IEpochManager(EPOCH_MANAGER_ADDR).triggerEpochTransition();
}
```

### 3. Initialization Sub-functions

#### _initializeStake
- Initialize StakeConfig
- Initialize ValidatorManager and set initial validators
- Initialize ValidatorPerformanceTracker

#### _initializeEpoch
- Initialize EpochManager

#### _initializeGovernance
- Initialize GovToken
- Initialize Timelock
- Initialize GravityGovernor

#### _initializeJWK
- Initialize JWKManager
- Initialize KeylessAccount

## Important Notes

1. **Address Conflicts**: Note that some contract addresses may be duplicated, need to confirm correct address allocation
2. **Initialization Order**: Must strictly follow dependency relationships for initialization
3. **Permission Control**: All initialization functions have `onlyGenesis` modifier
4. **Error Handling**: Ensure each initialization step executes successfully

## Current Implementation Status

In `execute.rs`, we have:
- ✅ Split deployment functions for all contracts
- ✅ Deploy contracts in correct order
- ✅ Output contract addresses
- ✅ Generate genesis_accounts.json and genesis_contracts.json

**To Complete**:
- 🔄 Fix compilation errors with Bytes creation method
- 🔄 Add contract initialization calls
- 🔄 Verify correctness of contract address allocation

## Usage Instructions

1. Ensure all contracts are compiled and .hex files are generated
2. Run the `genesis_generate` function
3. Check output contract addresses and JSON files
4. Verify all contract deployments and initializations are successful 