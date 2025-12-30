# Generate Directory - Genesis Generation Tools

This directory contains all the tools and scripts needed to generate the genesis state for the Gravity blockchain. The tools follow a modular approach, separating contract compilation, bytecode extraction, state generation, and final genesis assembly.

## Design Philosophy

The genesis generation process is designed to be:
- **Modular**: Each step is independent and can be run separately
- **Reproducible**: Same inputs always produce the same outputs
- **Configurable**: JSON-based configuration for easy customization
- **BSC-Compatible**: Follows BSC's approach of deploying runtime bytecode directly to genesis state
- **Initializable**: Unlike BSC, we also execute initialization functions to capture the complete chain state

## File Overview

### Core Generation Scripts

#### `extract_bytecode.py`
**Purpose**: Extracts runtime bytecode from Foundry compiled artifacts and saves them as `.hex` files.

**Design**: 
- Reads all contract artifacts from Foundry's `out` directory
- Extracts runtime bytecode (not constructor bytecode) for BSC-style deployment
- Handles both regular contracts and test contracts
- Generates standardized `.hex` files for the Rust genesis generator

**Usage**:
```bash
# After running forge build
python3 generate/extract_bytecode.py
```

**Output**: Creates `.hex` files in the `out` directory for each contract.

#### `combine_account_alloc.py`
**Purpose**: Combines genesis accounts and contracts into a unified account allocation format.

**Design**:
- Merges `genesis_accounts.json` (account states) with `genesis_contracts.json` (contract bytecodes)
- Creates a single allocation file with balance, nonce, code, and storage for each account
- Handles the complex structure of account data vs simple address-to-bytecode mapping

**Usage**:
```bash
python3 generate/combine_account_alloc.py output/genesis_contracts.json output/genesis_accounts.json
```

**Output**: Creates `account_alloc.json` with unified account allocation data.

#### `genesis_generate.py`
**Purpose**: Creates the final `genesis.json` file by combining template configuration with account allocation data.

**Design**:
- Reads `genesis_template.json` as the base configuration
- Merges `account_alloc.json` data into the `alloc` field
- Preserves existing template configuration while adding generated accounts
- Outputs a complete genesis file ready for blockchain initialization

**Usage**:
```bash
python3 generate/genesis_generate.py
```

**Output**: Creates `genesis.json` - the final genesis file for the blockchain.

#### `fix_hex_length.py`
**Purpose**: Fixes hex string lengths in JSON files to ensure proper formatting for blockchain clients.

**Design**:
- Processes JSON files to ensure all hex values have proper length (even number of characters)
- Handles both input and output files
- Maintains JSON structure while fixing hex formatting
- Essential for compatibility with various blockchain clients

**Usage**:
```bash
python3 generate/fix_hex_length.py input.json [output.json]
```

### Configuration Files

#### `genesis_config.json`
**Purpose**: Configuration file for genesis initialization parameters.

**Structure**:
```json
{
  "validatorAddresses": ["0x..."],
  "consensusPublicKeys": ["0x..."],
  "votingPowers": ["1"],
  "validatorNetworkAddresses": ["0x..."],
  "fullnodeNetworkAddresses": [""]
}
```

**Design**: 
- JSON-based configuration for easy modification
- Supports multiple validators with different parameters
- Used by the Rust genesis generator for contract initialization

#### `genesis_template.json`
**Purpose**: Base template for the final genesis file.

**Design**:
- Contains blockchain configuration (chain ID, fork blocks, etc.)
- Includes initial account allocations
- Serves as the foundation for the final genesis file
- Can be customized for different network configurations

### Documentation

#### `CONTRACT_INITIALIZATION_ORDER.md`
**Purpose**: Documents the order and dependencies of contract initialization.

**Content**:
- Contract deployment order
- Initialization dependencies
- System caller requirements
- Error handling considerations

## Complete Workflow

1. **Contract Compilation**: `forge build` (in project root)
2. **Bytecode Extraction**: `python3 generate/extract_bytecode.py`
3. **Genesis Generation**: `cargo run --bin gravity-genesis` (in gravity-genesis directory)
4. **Account Combination**: `python3 generate/combine_account_alloc.py`
5. **Hex Length Fixing**: `python3 generate/fix_hex_length.py`
6. **Final Assembly**: `python3 generate/genesis_generate.py`

## Key Differences from BSC

While following BSC's pattern of deploying runtime bytecode directly to genesis state, our implementation adds:

1. **Initialization Execution**: We execute contract initialization functions to capture the complete chain state
2. **System Caller Integration**: Proper handling of system caller contracts for complex initialization
3. **State Capture**: Full state dump including storage, nonces, and balances
4. **Configurable Parameters**: JSON-based configuration for validator setup

## Error Handling

All scripts include comprehensive error handling:
- File existence checks
- JSON validation
- Bytecode verification
- Detailed error messages with context

## Output Files

The generation process produces:
- `out/*.hex` - Contract bytecode files
- `output/genesis_accounts.json` - Account states
- `output/genesis_contracts.json` - Contract bytecodes
- `account_alloc.json` - Combined allocation data
- `genesis.json` - Final genesis file

## Prerequisites

- Foundry (for contract compilation)
- Python 3.7+ (for generation scripts)
- Rust (for gravity-genesis binary)
- Proper contract compilation with `forge build` 