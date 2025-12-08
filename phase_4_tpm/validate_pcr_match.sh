#!/bin/bash

#############################################
# TPM PCR Validation and Mismatch Detection Script
#############################################
# Purpose: Validate TPM PCR values against registered selectors and provide
#          detailed error messages for mismatches
# Requirements: 2.4
#
# This script reads current TPM PCR values and compares them against
# registered workload selectors in SPIRE Server. It provides detailed
# diagnostic information when mismatches occur.
#
# Usage:
#   sudo ./validate_pcr_match.sh [OPTIONS]
#
# Options:
#   -s, --spiffe-id <id>   SPIFFE ID of workload to validate (required)
#   -v, --verbose          Enable verbose output
#   --help                 Display this help message
#
# Exit Codes:
#   0 - Success: All PCR values match registered selectors
#   1 - Failure: PCR mismatch detected
#   2 - Failure: Invalid arguments or configuration
#   3 - Failure: TPM device not accessible
#############################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Exit codes
EXIT_SUCCESS=0
EXIT_PCR_MISMATCH=1
EXIT_INVALID_ARGS=2
EXIT_TPM_NOT_ACCESSIBLE=3

# Configuration
SPIFFE_ID=""
VERBOSE=false
SPIRE_SERVER_BIN="/opt/spire/bin/spire-server"

# Function to print colored messages
print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

print_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}VERBOSE: $1${NC}"
    fi
}

# Function to print usage
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate TPM PCR values against registered SPIRE workload selectors.

Options:
  -s, --spiffe-id <id>   SPIFFE ID of workload to validate (required)
  -v, --verbose          Enable verbose output
  --help                 Display this help message

Examples:
  # Validate PCR values for a workload
  sudo $0 --spiffe-id spiffe://example.org/k8s-workload

  # Validate with verbose output
  sudo $0 --spiffe-id spiffe://example.org/k8s-workload --verbose

Exit Codes:
  0 - All PCR values match
  1 - PCR mismatch detected
  2 - Invalid arguments
  3 - TPM not accessible

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--spiffe-id)
            SPIFFE_ID="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            exit $EXIT_INVALID_ARGS
            ;;
    esac
done

echo "=========================================="
echo "   TPM PCR Validation"
echo "=========================================="
echo ""

# Validate required arguments
if [ -z "$SPIFFE_ID" ]; then
    print_error "SPIFFE ID is required"
    print_usage
    exit $EXIT_INVALID_ARGS
fi

print_info "Validating workload: $SPIFFE_ID"
echo ""

#############################################
# Step 1: Check TPM Device Accessibility
#############################################
print_info "Step 1: Checking TPM device accessibility..."

TPM_DEVICE=""
if [ -e /dev/tpmrm0 ]; then
    TPM_DEVICE="/dev/tpmrm0"
elif [ -e /dev/tpm0 ]; then
    TPM_DEVICE="/dev/tpm0"
else
    print_error "TPM device not found at /dev/tpmrm0 or /dev/tpm0"
    print_error "Cannot validate PCR values without TPM access"
    exit $EXIT_TPM_NOT_ACCESSIBLE
fi

print_verbose "TPM device: $TPM_DEVICE"

if [ ! -r "$TPM_DEVICE" ]; then
    print_error "TPM device $TPM_DEVICE is not readable"
    print_error "Run with sudo or ensure proper permissions"
    exit $EXIT_TPM_NOT_ACCESSIBLE
fi

print_success "TPM device is accessible"
echo ""

#############################################
# Step 2: Check for tpm2-tools
#############################################
print_info "Step 2: Checking for tpm2-tools..."

if ! command -v tpm2_pcrread &> /dev/null; then
    print_error "tpm2_pcrread not found"
    print_error "Install tpm2-tools: sudo apt-get install tpm2-tools"
    exit $EXIT_INVALID_ARGS
fi

print_success "tpm2-tools is installed"
echo ""

#############################################
# Step 3: Retrieve Workload Entry from SPIRE Server
#############################################
print_info "Step 3: Retrieving workload entry from SPIRE Server..."

if [ ! -f "$SPIRE_SERVER_BIN" ]; then
    print_error "SPIRE Server binary not found: $SPIRE_SERVER_BIN"
    exit $EXIT_INVALID_ARGS
fi

# Get workload entry
ENTRY_OUTPUT=$("$SPIRE_SERVER_BIN" entry show -spiffeID "$SPIFFE_ID" 2>&1)

if ! echo "$ENTRY_OUTPUT" | grep -q "Entry ID"; then
    print_error "Workload entry not found for SPIFFE ID: $SPIFFE_ID"
    print_error "Ensure the workload is registered with SPIRE Server"
    exit $EXIT_INVALID_ARGS
fi

print_success "Workload entry found"
print_verbose "Entry details:"
if [ "$VERBOSE" = true ]; then
    echo "$ENTRY_OUTPUT"
fi
echo ""

#############################################
# Step 4: Extract TPM PCR Selectors
#############################################
print_info "Step 4: Extracting TPM PCR selectors from entry..."

# Extract TPM PCR selectors (format: tpm:pcr:<index>:<hash>)
TPM_SELECTORS=$(echo "$ENTRY_OUTPUT" | grep "tpm:pcr:" || true)

if [ -z "$TPM_SELECTORS" ]; then
    print_warning "No TPM PCR selectors found for this workload"
    print_info "Workload may be using Docker or other attestation methods"
    print_info "No PCR validation needed"
    exit $EXIT_SUCCESS
fi

print_success "Found TPM PCR selectors:"
echo "$TPM_SELECTORS"
echo ""

#############################################
# Step 5: Read Current TPM PCR Values
#############################################
print_info "Step 5: Reading current TPM PCR values..."

# Read all PCR values (SHA256 bank)
PCR_OUTPUT=$(tpm2_pcrread sha256 2>&1)

if [ $? -ne 0 ]; then
    print_error "Failed to read TPM PCR values"
    print_error "Output: $PCR_OUTPUT"
    exit $EXIT_TPM_NOT_ACCESSIBLE
fi

print_success "Successfully read TPM PCR values"
print_verbose "PCR values:"
if [ "$VERBOSE" = true ]; then
    echo "$PCR_OUTPUT"
fi
echo ""

#############################################
# Step 6: Validate Each PCR Selector
#############################################
print_info "Step 6: Validating PCR values against selectors..."
echo ""

MISMATCH_FOUND=false
MISMATCH_DETAILS=""

# Parse each TPM selector
while IFS= read -r selector_line; do
    # Extract selector value (remove leading whitespace and "Selectors:" prefix)
    selector=$(echo "$selector_line" | sed 's/^[[:space:]]*Selectors:[[:space:]]*//' | sed 's/^[[:space:]]*//')
    
    # Parse selector format: tpm:pcr:<index>:<hash>
    if [[ $selector =~ tpm:pcr:([0-9]+):([0-9a-fA-F]+) ]]; then
        pcr_index="${BASH_REMATCH[1]}"
        expected_hash="${BASH_REMATCH[2]}"
        
        print_info "Validating PCR $pcr_index..."
        print_verbose "  Expected hash: $expected_hash"
        
        # Extract actual PCR value from tpm2_pcrread output
        actual_hash=$(echo "$PCR_OUTPUT" | grep "^[[:space:]]*${pcr_index}[[:space:]]*:" | awk '{print $3}' | tr -d '[:space:]')
        
        if [ -z "$actual_hash" ]; then
            print_error "  Could not read PCR $pcr_index value from TPM"
            MISMATCH_FOUND=true
            MISMATCH_DETAILS="${MISMATCH_DETAILS}\nPCR ${pcr_index}: Unable to read current value"
            continue
        fi
        
        print_verbose "  Actual hash:   $actual_hash"
        
        # Compare hashes (case-insensitive)
        expected_hash_lower=$(echo "$expected_hash" | tr '[:upper:]' '[:lower:]')
        actual_hash_lower=$(echo "$actual_hash" | tr '[:upper:]' '[:lower:]')
        
        if [ "$expected_hash_lower" = "$actual_hash_lower" ]; then
            print_success "  ✓ PCR $pcr_index matches"
        else
            print_error "  ✗ PCR $pcr_index MISMATCH"
            print_error "    Expected: $expected_hash"
            print_error "    Actual:   $actual_hash"
            MISMATCH_FOUND=true
            MISMATCH_DETAILS="${MISMATCH_DETAILS}\nPCR ${pcr_index}:"
            MISMATCH_DETAILS="${MISMATCH_DETAILS}\n  Expected: ${expected_hash}"
            MISMATCH_DETAILS="${MISMATCH_DETAILS}\n  Actual:   ${actual_hash}"
        fi
    else
        print_warning "  Invalid TPM selector format: $selector"
    fi
    
    echo ""
done <<< "$TPM_SELECTORS"

#############################################
# Step 7: Report Results
#############################################
echo "=========================================="

if [ "$MISMATCH_FOUND" = true ]; then
    print_error "PCR MISMATCH DETECTED"
    echo "=========================================="
    echo ""
    print_error "One or more PCR values do not match the registered selectors."
    print_error "This indicates that the system state has changed since registration."
    echo ""
    print_error "Mismatch Details:"
    echo -e "$MISMATCH_DETAILS"
    echo ""
    print_error "SVID REQUEST WILL BE DENIED"
    echo ""
    print_info "Possible Causes:"
    echo "  1. System firmware or bootloader has been updated"
    echo "  2. BIOS/UEFI settings have changed"
    echo "  3. Secure Boot configuration has changed"
    echo "  4. Operating system kernel or initramfs has been updated"
    echo "  5. TPM has been cleared or reset"
    echo ""
    print_info "Resolution Steps:"
    echo "  1. If changes are legitimate, update workload registration:"
    echo "     - Read current PCR values: tpm2_pcrread sha256"
    echo "     - Delete old registration: sudo $SPIRE_SERVER_BIN entry delete -spiffeID $SPIFFE_ID"
    echo "     - Register with new PCR values: ./register_workload_tpm.sh --spiffe-id $SPIFFE_ID --pcr-index <index> --pcr-hash <new_hash>"
    echo ""
    echo "  2. If changes are unexpected, investigate potential security issues:"
    echo "     - Review system logs: journalctl -xe"
    echo "     - Check for unauthorized firmware updates"
    echo "     - Verify system integrity"
    echo ""
    echo "  3. To view all current PCR values:"
    echo "     tpm2_pcrread sha256"
    echo ""
    echo "=========================================="
    
    exit $EXIT_PCR_MISMATCH
else
    print_success "ALL PCR VALUES MATCH"
    echo "=========================================="
    echo ""
    print_success "All TPM PCR values match the registered selectors."
    print_success "Workload is eligible for SVID issuance."
    echo ""
    print_info "Workload: $SPIFFE_ID"
    print_info "TPM Device: $TPM_DEVICE"
    echo ""
    echo "=========================================="
    
    exit $EXIT_SUCCESS
fi
