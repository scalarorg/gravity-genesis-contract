# Gravity Genesis - BSC-Style Genesis Generation

This directory contains the Rust implementation for generating genesis state for the Gravity blockchain, following the BSC (Binance Smart Chain) approach while extending it with initialization execution.

## Overview

The `gravity-genesis` tool implements a BSC-style genesis generation system that:
1. **Deploys contracts** to predefined addresses in genesis state (like BSC)
2. **Executes initialization** functions to capture complete chain state (unlike BSC)
3. **Generates state files** for blockchain initialization
4. **Supports configurable** validator setup via JSON configuration

## BSC Implementation Reference

### BSC Approach
BSC deploys contracts to genesis state by:
- Placing runtime bytecode directly at predefined addresses
- No initialization execution - contracts start in their default state
- Simple deployment without complex state setup

### Our Extension
We extend BSC's approach by:
- **Deploying runtime bytecode** to predefined addresses (like BSC)
- **Executing initialization functions** to set up complete chain state
- **Capturing the resulting state** including storage, balances, and nonces
- **Supporting complex initialization** with system caller contracts

## Key Differences from BSC

| Aspect | BSC | Gravity Genesis |
|--------|-----|-----------------|
| **Deployment** | Runtime bytecode only | Runtime bytecode + initialization |
| **State Capture** | Default contract state | Post-initialization state |
| **Initialization** | None | Full contract initialization |
| **System Integration** | Not required | System caller integration |
| **Complex Setup** | Manual post-deployment | Automated during genesis |

## Architecture

### Core Components

#### `execute.rs` - Main Genesis Logic
**Purpose**: Handles contract deployment, initialization, and state generation.

**Key Functions**:
- `deploy_bsc_style()`: Deploys runtime bytecode to predefined addresses
- `call_genesis_initialize()`: Executes Genesis contract initialization
- `genesis_generate()`: Orchestrates the complete generation process

**BSC-Style Deployment**:
```rust
// Deploy runtime bytecode directly to genesis state
db.insert_account_info(
    target_address,
    AccountInfo {
        code: Some(Bytecode::new_raw(Bytes::from(runtime_bytecode))),
        ..AccountInfo::default()
    },
);
```

**Initialization Execution**:
```rust
// Execute Genesis.initialize() to set up complete chain state
let call_data = Genesis::initializeCall {
    validatorAddresses: validator_addresses,
    consensusAddresses: consensus_addresses,
    feeAddresses: fee_addresses,
    votingPowers: voting_powers,
    voteAddresses: vote_addresses,
}.abi_encode();
```

#### `main.rs` - CLI Interface
**Purpose**: Command-line interface for genesis generation.

**Features**:
- JSON configuration file support
- Command-line argument parsing
- Logging and error handling
- Output file management

#### `utils.rs` - EVM Utilities
**Purpose**: EVM-related utilities and constants.

**Components**:
- Contract address definitions
- Transaction creation utilities
- Hex file reading functions
- EVM execution helpers

## Contract Deployment Strategy

### Runtime vs Constructor Bytecode

**Critical Distinction**: We use **runtime bytecode** for BSC-style deployment, not constructor bytecode.

- **Constructor Bytecode**: Includes deployment logic, creates contract instance
- **Runtime Bytecode**: Pure contract logic, what remains after deployment

**Implementation**:
```rust
// Extract runtime bytecode from constructor bytecode
let runtime_bytecode = extract_runtime_bytecode(&constructor_bytecode);

// Deploy runtime bytecode directly (BSC style)
db.insert_account_info(target_address, AccountInfo {
    code: Some(Bytecode::new_raw(Bytes::from(runtime_bytecode))),
    ..AccountInfo::default()
});
```

### Contract Addresses
All contracts are deployed to predefined addresses:
```
System:                     0x00000000000000000000000000000000000000ff
SystemReward:              0x0000000000000000000000000000000000001002
StakeConfig:               0x0000000000000000000000000000000000002008
ValidatorManager:          0x0000000000000000000000000000000000002010
ValidatorPerformanceTracker: 0x000000000000000000000000000000000000200b
EpochManager:              0x00000000000000000000000000000000000000f3
GovToken:                  0x0000000000000000000000000000000000002005
Timelock:                  0x0000000000000000000000000000000000002007
GravityGovernor:           0x0000000000000000000000000000000000002006
JWKManager:                0x0000000000000000000000000000000000002002
KeylessAccount:            0x000000000000000000000000000000000000200a
Block:                     0x0000000000000000000000000000000000002001
Timestamp:                 0x0000000000000000000000000000000000002004
Genesis:                   0x0000000000000000000000000000000000001008
StakeCredit:               0x0000000000000000000000000000000000002003
Delegation:                0x0000000000000000000000000000000000002009
GovHub:                    0x0000000000000000000000000000000000001007
RandomnessConfig:          0x0000000000000000000000000000000000002020
DKG:                       0x0000000000000000000000000000000000002021
ReconfigurationWithDKG:    0x0000000000000000000000000000000000002022
HashOracle:                0x0000000000000000000000000000000000002023
```

## Genesis Initialization Process

### 1. Contract Deployment
All 22 contracts are deployed to their predefined addresses using runtime bytecode.

### 2. Genesis Contract Initialization
The `Genesis.initialize()` function is called with validator configuration:

```solidity
function initialize(
    address[] calldata validatorAddresses,
    bytes[] calldata consensusPublicKeys,
    uint256[] calldata votingPowers,
    bytes[] calldata validatorNetworkAddresses,
    bytes[] calldata fullnodeNetworkAddresses
) external;
```

### 3. Subsystem Initialization
The Genesis contract initializes all subsystems:
- **Staking Module**: StakeConfig, ValidatorManager, ValidatorPerformanceTracker
- **Epoch Module**: EpochManager
- **Governance Module**: GovToken, Timelock, GravityGovernor
- **JWK Module**: JWKManager, KeylessAccount
- **Block Module**: Block contract

### 4. State Capture
After initialization, the complete chain state is captured including:
- Account balances and nonces
- Contract storage
- Contract bytecode
- All state changes from initialization

## Configuration

### JSON Configuration Format
```json
{
  "validatorAddresses": [
    "0x6e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f"
  ],
  "consensusPublicKeys": [
    "851d41932d866f5fabed6673898e15473e6a0adcf5033d2c93816c6b115c85ad3451e0bac61d570d5ed9f23e1e7f77c4"
  ],
  "votingPowers": [
    "1"
  ],
  "validatorNetworkAddresses": [
    "/ip4/127.0.0.1/tcp/2024/noise-ik/2d86b40a1d692c0749a0a0426e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f/handshake/0"
  ],
  "fullnodeNetworkAddresses": [
    "/ip4/127.0.0.1/tcp/2024/noise-ik/2d86b40a1d692c0749a0a0426e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f/handshake/0"
  ],
  "aptosAddresses": [
    "2d86b40a1d692c0749a0a0426e2021ee24e2430da0f5bb9c2ae6c586bf3e0a0f"
  ]
}
```

## Usage

### Basic Usage
```bash
# Using default configuration
cargo run --release --bin gravity-genesis -- --byte-code-dir ../out --config-file ../generate/genesis_config.json --output ../output

# With custom configuration
cargo run --release --bin gravity-genesis -- --byte-code-dir ../out --config-file ./my_config.json --output ../output

# With debug logging
cargo run --release --bin gravity-genesis -- --byte-code-dir ../out --config-file ../generate/genesis_config.json --output ../output --log-file ../output/genesis_generation.log
```

### Prerequisites
1. **Contract Compilation**: `forge build` (in project root)
2. **Bytecode Extraction**: `python3 ../generate/extract_bytecode.py`
3. **Configuration**: Valid `genesis_config.json` file

## Output Files

The tool generates:
- `genesis_accounts.json`: Account states with balances, nonces, and storage
- `genesis_contracts.json`: Contract bytecodes for all deployed contracts
- `bundle_state.json`: Complete state bundle for verification

## Why This Approach?

### Alternative Approaches Considered

1. **Foundry Test + Unit Tests**
   - **Problem**: Foundry uses `eth_call` which doesn't persist state changes
   - **Issue**: Cannot dump state after test execution
   - **Result**: Not suitable for genesis generation

2. **Foundry Script + Solidity Driver**
   - **Problem**: Complex system caller integration required
   - **Issue**: Key management and system caller contracts are complex
   - **Result**: Abandoned due to complexity

### Why Gravity-Genesis?

1. **Full State Control**: Direct control over EVM state and execution
2. **BSC Compatibility**: Follows proven BSC pattern
3. **Initialization Support**: Can execute complex initialization logic
4. **System Integration**: Proper handling of system caller contracts
5. **State Capture**: Complete state dump after initialization

## Technical Implementation

### EVM Integration
- Uses `revm` for EVM execution
- Direct database manipulation for state control
- Transaction simulation for initialization
- Bundle state capture for complete state dump

### Error Handling
- Comprehensive error handling with detailed logging
- Transaction failure detection and reporting
- Configuration validation
- File I/O error handling

### Performance
- Optimized for large contract deployments
- Efficient state management
- Minimal memory usage during generation
- Fast execution for development iteration

## Success Metrics

- ✅ **22 contracts deployed** to correct addresses
- ✅ **Genesis initialization successful** (39,510 gas used)
- ✅ **Complete state capture** (22 accounts, 273KB bytecode)
- ✅ **BSC-compatible format** for blockchain initialization
- ✅ **Configurable validator setup** via JSON
- ✅ **System caller integration** working correctly

This implementation successfully extends BSC's genesis generation approach while adding the initialization capabilities needed for the Gravity blockchain's complex contract architecture. 