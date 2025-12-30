#!/bin/bash

# Color codes for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

log_debug() {
    echo -e "${CYAN}[DEBUG]${NC} $1"
}

# Error handling
set -e  # Exit on any error
trap 'log_error "Script failed at line $LINENO"; restore_epoch_manager; exit 1' ERR

# Function to detect operating system
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "linux"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 is not installed or not in PATH"
        exit 1
    fi
}

# Function to check if directory exists
check_directory() {
    if [ ! -d "$1" ]; then
        log_error "Directory $1 does not exist"
        exit 1
    fi
}

# Function to check if file exists
check_file() {
    if [ ! -f "$1" ]; then
        log_error "File $1 does not exist"
        exit 1
    fi
}

# Function to create directory if it doesn't exist
create_directory() {
    if [ ! -d "$1" ]; then
        log_info "Creating directory: $1"
        mkdir -p "$1"
    fi
}

# Function to check command execution result
check_result() {
    if [ $? -eq 0 ]; then
        log_success "$1"
    else
        log_error "$1 failed"
        exit 1
    fi
}

# Default values
DEFAULT_EPOCH_INTERVAL_HOURS=2
EPOCH_INTERVAL_HOURS=$DEFAULT_EPOCH_INTERVAL_HOURS

# Function to show help
show_help() {
    echo "Gravity Genesis Generation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -i, --interval HOURS    Set epoch interval in hours (default: $DEFAULT_EPOCH_INTERVAL_HOURS)"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Description:"
    echo "  This script generates a complete genesis configuration for the Gravity blockchain."
    echo "  It compiles smart contracts, extracts bytecode, and creates genesis files with"
    echo "  configurable epoch intervals for the EpochManager contract."
    echo ""
    echo "  Note: Fractional hours (e.g., 0.5, 1.5) are supported and will be converted"
    echo "  to precise microsecond values for Solidity uint256 compatibility."
    echo ""
    echo "Examples:"
    echo "  $0                      # Use default 2-hour epoch interval"
    echo "  $0 -i 4                # Use 4-hour epoch interval"
    echo "  $0 --interval 1.5      # Use 1.5-hour epoch interval"
    echo "  $0 -i 0.1              # Use 0.1-hour (6-minute) epoch interval"
    echo ""
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interval)
                EPOCH_INTERVAL_HOURS="$2"
                if ! [[ "$EPOCH_INTERVAL_HOURS" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$EPOCH_INTERVAL_HOURS <= 0" | bc -l) )); then
                    log_error "Invalid epoch interval: $EPOCH_INTERVAL_HOURS. Must be a positive number."
                    exit 1
                fi
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Function to modify EpochManager.sol with the specified epoch interval
modify_epoch_manager() {
    local interval_hours=$1
    
    # Use Python script to convert hours to microseconds (ensures proper integer conversion)
    local interval_microsecs=$(python3 generate/convert_hours_to_microsecs.py "$interval_hours")
    
    log_info "Configuring EpochManager with ${interval_hours} hour epoch interval (${interval_microsecs} microseconds)..."
    log_info "Note: Fractional hours are converted to precise microsecond values for Solidity compatibility."
    
    # Create a backup of the original file
    cp src/epoch/EpochManager.sol src/epoch/EpochManager.sol.backup
    
    # Detect OS and use appropriate sed command
    local os=$(detect_os)
    case $os in
        "macos")
            # macOS sed requires empty string after -i for in-place editing
            sed -i "" "s/epochIntervalMicrosecs = 2 hours \* 1_000_000;/epochIntervalMicrosecs = ${interval_microsecs};/" src/epoch/EpochManager.sol
            ;;
        "linux")
            # Linux sed uses -i without empty string
            sed -i "s/epochIntervalMicrosecs = 2 hours \* 1_000_000;/epochIntervalMicrosecs = ${interval_microsecs};/" src/epoch/EpochManager.sol
            ;;
        *)
            log_error "Unsupported operating system: $os"
            exit 1
            ;;
    esac
    
    log_success "EpochManager.sol updated with ${interval_hours} hour interval"
}

# Function to restore original EpochManager.sol
restore_epoch_manager() {
    if [ -f "src/epoch/EpochManager.sol.backup" ]; then
        log_info "Restoring original EpochManager.sol..."
        mv src/epoch/EpochManager.sol.backup src/epoch/EpochManager.sol
        log_success "EpochManager.sol restored"
    fi
}

# Main script
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Detect and log operating system
    local os=$(detect_os)
    log_info "Detected operating system: $os"
    
    log_step "Starting Gravity Genesis generation process..."
    log_info "Epoch interval: ${EPOCH_INTERVAL_HOURS} hours"
    
    # Check required commands
    log_info "Checking required commands..."
    check_command "forge"
    check_command "python3"
    check_command "cargo"
    check_command "bc"  # For floating point arithmetic
    log_success "All required commands are available"
    
    # Check if we're in the right directory (should have src/ directory)
    log_info "Checking current directory..."
    check_directory "src"
    log_success "Current directory is valid"
    
    # Step 0: Modify EpochManager.sol with specified interval
    log_step "Step 0: Configuring EpochManager with specified interval..."
    modify_epoch_manager "$EPOCH_INTERVAL_HOURS"
    
    # Step 1: Foundry build
    log_step "Step 1: Building contracts with Foundry..."
    # Remove out directory to avoid solc compilation cache issues
    if [ -d "out" ]; then
        log_info "Removing out directory to avoid solc compilation cache issues..."
        rm -rf out
    fi
    log_info "Running forge build..."
    forge build
    check_result "forge build"
    
    # Verify out directory contents
    log_info "Verifying build output..."
    check_directory "out"
    if [ -z "$(ls -A out 2>/dev/null)" ]; then
        log_error "out directory is empty after build"
        exit 1
    fi
    log_success "Build output verified"
    
    # Step 2: Extract bytecode
    log_step "Step 2: Extracting bytecode from compiled contracts..."
    check_file "generate/extract_bytecode.py"
    log_info "Running bytecode extraction..."
    python3 generate/extract_bytecode.py
    check_result "bytecode extraction"
    
    # Verify bytecode files were created
    log_info "Verifying bytecode files..."
    expected_contracts=("System" "SystemReward" "StakeConfig" "ValidatorManager" "ValidatorPerformanceTracker" "EpochManager" "GovToken" "Timelock" "GravityGovernor" "JWKManager" "KeylessAccount" "Block" "Timestamp" "Genesis" "StakeCredit" "Delegation" "GovHub")
    
    for contract in "${expected_contracts[@]}"; do
        if [ ! -f "out/${contract}.hex" ]; then
            log_error "Missing bytecode file: out/${contract}.hex"
            exit 1
        fi
    done
    log_success "All bytecode files verified"
    
    # Step 3: Generate genesis with Rust binary
    log_step "Step 3: Generating genesis accounts and contracts..."
    check_file "generate/genesis_config.json"
    create_directory "output"
    
    log_info "Running gravity-genesis binary..."
    cargo run --release --bin gravity-genesis -- --byte-code-dir out --config-file generate/genesis_config.json --output output --log-file output/genesis_generation.log
    check_result "genesis generation"
    
    # Verify output files
    log_info "Verifying genesis output files..."
    check_file "output/genesis_accounts.json"
    check_file "output/genesis_contracts.json"
    check_file "output/bundle_state.json"
    log_success "Genesis files generated successfully"
    
    # Step 4: Combine account allocation
    log_step "Step 4: Combining account allocation..."
    check_file "generate/combine_account_alloc.py"
    log_info "Running account allocation combination..."
    python3 generate/combine_account_alloc.py output/genesis_contracts.json output/genesis_accounts.json
    check_result "account allocation combination"
    
    # Verify combined file
    log_info "Verifying combined allocation file..."
    check_file "account_alloc.json"
    log_success "Combined allocation file created"
    
    # Step 4.5: Fix hex string lengths
    log_step "Step 4.5: Fixing hex string lengths..."
    check_file "generate/fix_hex_length.py"
    
    log_info "Fixing hex string lengths in account_alloc.json..."
    python3 generate/fix_hex_length.py "account_alloc.json"
    check_result "hex string length fixing"
    
    log_success "Hex string lengths fixed successfully"
    
    # Step 5: Generate final genesis.json
    log_step "Step 5: Generating final genesis.json..."
    check_file "generate/genesis_generate.py"
    check_file "generate/genesis_template.json"
    check_file "account_alloc.json"
    log_info "Running final genesis generation..."
    python3 generate/genesis_generate.py
    check_result "final genesis generation"
    
    # Verify final genesis file
    log_info "Verifying final genesis file..."
    check_file "genesis.json"
    log_success "Final genesis.json created"
    
    # Final summary
    log_step "Genesis generation completed successfully!"
    log_info "Generated files:"
    log_info "  - genesis.json (main genesis file)"
    log_info "  - account_alloc.json (combined account allocation)"
    log_info "  - output/genesis_accounts.json (account states)"
    log_info "  - output/genesis_contracts.json (contract bytecodes)"
    log_info "  - output/bundle_state.json (bundle state)"
    log_info "  - output/genesis_generation.log (generation logs)"
    
    # Cleanup: Restore original EpochManager.sol
    log_info "Cleaning up temporary files..."
    restore_epoch_manager
    
    log_success "All steps completed successfully!"
}

# Run main function
main "$@"
