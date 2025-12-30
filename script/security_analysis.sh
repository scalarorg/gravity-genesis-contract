#!/bin/bash
set -e

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Script configuration
REPO_ROOT=$(pwd)
SRC_DIR="$REPO_ROOT/src"
AUDIT_DIR="$REPO_ROOT/audit"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Tool selection from command line argument
TOOL="${1:-all}"

# Print usage
print_usage() {
    echo "Usage: $0 [tool]"
    echo "Tools: slither, aderyn, all"
    echo "Default: all (runs all tools)"
}

# Check if src directory exists
check_src_dir() {
    if [ ! -d "$SRC_DIR" ]; then
        echo -e "${RED}Error: src/ directory not found!${NC}"
        echo "Please make sure you're running this script from the project root directory."
        exit 1
    fi
}

# Create audit directory if it doesn't exist
create_audit_dir() {
    mkdir -p "$AUDIT_DIR"
}

# Common header for all reports
generate_report_header() {
    local tool_name=$1
    local report_file=$2
    
    cat > "$report_file" << EOF
# $tool_name Security Analysis Report

Generated on: $(date)
Repository: $(basename "$REPO_ROOT")

---

EOF
}

# Run Slither analysis
run_slither() {
    echo -e "${BLUE}Running Slither security analysis...${NC}"
    
    # Check if Slither is installed
    if ! command -v slither &> /dev/null; then
        echo -e "${YELLOW}Slither not found. Attempting to install...${NC}"
        if command -v pip3 &> /dev/null; then
            pip3 install slither-analyzer
        elif command -v pip &> /dev/null; then
            pip install slither-analyzer
        else
            echo -e "${RED}Error: pip not found. Please install Slither manually.${NC}"
            exit 1
        fi
    fi
    
    local REPORT_FILE="$AUDIT_DIR/slither_report_$TIMESTAMP.md"
    local JSON_FILE="$AUDIT_DIR/slither_report_$TIMESTAMP.json"
    
    generate_report_header "Slither" "$REPORT_FILE"
    
    # Check for config file
    local CONFIG_ARGS=""
    if [ -f "$REPO_ROOT/slither.config.json" ]; then
        CONFIG_ARGS="--config-file slither.config.json"
    fi
    
    # Run analysis (exclude test folder)
    echo -e "${YELLOW}Analyzing contracts (excluding test files)...${NC}"
    set +e
    slither . $CONFIG_ARGS --filter-paths "test/" --json "$JSON_FILE" 2>&1 | tee -a "$REPORT_FILE"
    local SLITHER_EXIT_CODE=$?
    set -e
    
    # Parse results
    if [ -f "$JSON_FILE" ]; then
        local HIGH_COUNT=$(jq '[.results.detectors[] | select(.impact == "High")] | length' "$JSON_FILE" 2>/dev/null || echo "0")
        local MEDIUM_COUNT=$(jq '[.results.detectors[] | select(.impact == "Medium")] | length' "$JSON_FILE" 2>/dev/null || echo "0")
        local LOW_COUNT=$(jq '[.results.detectors[] | select(.impact == "Low")] | length' "$JSON_FILE" 2>/dev/null || echo "0")
        local INFO_COUNT=$(jq '[.results.detectors[] | select(.impact == "Informational")] | length' "$JSON_FILE" 2>/dev/null || echo "0")
        
        echo -e "\n${GREEN}Slither Analysis Complete!${NC}"
        echo -e "Report saved to: ${BLUE}$REPORT_FILE${NC}"
        echo -e "JSON report saved to: ${BLUE}$JSON_FILE${NC}"
        echo -e "\n${YELLOW}Summary:${NC}"
        echo -e "  High Impact: ${RED}$HIGH_COUNT${NC}"
        echo -e "  Medium Impact: ${YELLOW}$MEDIUM_COUNT${NC}"
        echo -e "  Low Impact: ${BLUE}$LOW_COUNT${NC}"
        echo -e "  Informational: $INFO_COUNT"
    fi
}


# Run Aderyn analysis
run_aderyn() {
    echo -e "${BLUE}Running Aderyn static analysis...${NC}"
    
    # Check if Aderyn is installed
    if ! command -v aderyn &> /dev/null; then
        echo -e "${YELLOW}Aderyn not found. Attempting to install...${NC}"
        
        if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]]; then
            curl -L https://raw.githubusercontent.com/Cyfrin/aderyn/dev/cyfrinup/install | bash
            export PATH="$HOME/.cyfrin/bin:$PATH"
        elif command -v npm &> /dev/null; then
            npm install -g aderyn
        elif command -v brew &> /dev/null; then
            brew install aderyn
        else
            echo -e "${RED}Error: Could not install Aderyn. Please install manually.${NC}"
            exit 1
        fi
    fi
    
    local REPORT_FILE="$AUDIT_DIR/aderyn_report_$TIMESTAMP.md"
    local SUMMARY_FILE="$AUDIT_DIR/aderyn_summary_$TIMESTAMP.md"
    
    # Run analysis (exclude test folder)
    echo -e "${YELLOW}Analyzing contracts (excluding test files)...${NC}"
    set +e
    aderyn . --path-excludes "test/**/*.sol" --output "$REPORT_FILE" 2>&1 | tee "$SUMMARY_FILE"
    local ADERYN_EXIT_CODE=$?
    set -e
    
    # Parse results
    local HIGH_COUNT=$(grep -c "High:" "$SUMMARY_FILE" 2>/dev/null || echo "0")
    local MEDIUM_COUNT=$(grep -c "Medium:" "$SUMMARY_FILE" 2>/dev/null || echo "0")
    local LOW_COUNT=$(grep -c "Low:" "$SUMMARY_FILE" 2>/dev/null || echo "0")
    local INFO_COUNT=$(grep -c "Informational:" "$SUMMARY_FILE" 2>/dev/null || echo "0")
    
    echo -e "\n${GREEN}Aderyn Analysis Complete!${NC}"
    echo -e "Report saved to: ${BLUE}$REPORT_FILE${NC}"
    echo -e "Summary saved to: ${BLUE}$SUMMARY_FILE${NC}"
    echo -e "\n${YELLOW}Summary:${NC}"
    echo -e "  High Severity: ${RED}$HIGH_COUNT${NC}"
    echo -e "  Medium Severity: ${YELLOW}$MEDIUM_COUNT${NC}"
    echo -e "  Low Severity: ${BLUE}$LOW_COUNT${NC}"
    echo -e "  Informational: $INFO_COUNT"
}

# Main execution
main() {
    check_src_dir
    create_audit_dir
    
    case "$TOOL" in
        slither)
            run_slither
            ;;
        aderyn)
            run_aderyn
            ;;
        all)
            echo -e "${BLUE}Running comprehensive security audit...${NC}\n"
            run_slither
            echo ""
            run_aderyn
            echo -e "\n${GREEN}Comprehensive security audit complete!${NC}"
            echo -e "All reports saved in: ${BLUE}$AUDIT_DIR${NC}"
            ;;
        *)
            echo -e "${RED}Error: Unknown tool '$TOOL'${NC}"
            print_usage
            exit 1
            ;;
    esac
    
    echo -e "\n${YELLOW}Recommendations:${NC}"
    echo "1. Review all findings carefully, especially High and Medium severity issues"
    echo "2. Cross-reference findings between different tools"
    echo "3. Consider the context and business logic when evaluating issues"
    echo "4. Run tests after implementing fixes"
    echo -e "\n${BLUE}Happy auditing! 🛡️${NC}"
}

# Run main function
main