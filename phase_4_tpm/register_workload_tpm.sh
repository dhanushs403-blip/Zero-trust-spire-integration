#!/bin/bash

#############################################
# TPM-Aware Workload Registration Script
#############################################
# Purpose: Register workloads with TPM PCR selectors and Docker selectors
# Requirements: 2.1, 2.5
#
# This script registers workload entries with SPIRE Server using:
# - TPM PCR selectors (format: tpm:pcr:<index>:<hash>)
# - Docker label selectors (for backward compatibility)
#
# Usage:
#   sudo ./register_workload_tpm.sh [OPTIONS]
#
# Options:
#   -s, --spiffe-id <id>       SPIFFE ID for the workload (required)
#   -p, --pcr-index <index>    TPM PCR index (0-23, optional)
#   -h, --pcr-hash <hash>      TPM PCR hash value (hex string, optional)
#   -d, --docker-label <label> Docker label selector (can be specified multiple times)
#   --help                     Display this help message
#
# Examples:
#   # Register with TPM PCR selector only
#   sudo ./register_workload_tpm.sh \
#     --spiffe-id spiffe://example.org/k8s-workload \
#     --pcr-index 0 \
#     --pcr-hash a3f5d8c2e1b4...
#
#   # Register with both TPM and Docker selectors (backward compatibility)
#   sudo ./register_workload_tpm.sh \
#     --spiffe-id spiffe://example.org/k8s-workload \
#     --pcr-index 0 \
#     --pcr-hash a3f5d8c2e1b4... \
#     --docker-label io.kubernetes.container.name:mtls-app \
#     --docker-label io.kubernetes.pod.namespace:default
#
# Exit Codes:
#   0 - Success: Workload registered successfully
#   1 - Failure: Invalid arguments, validation failed, or registration failed
#############################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
SPIFFE_ID=""
PCR_INDEX=""
PCR_HASH=""
DOCKER_LABELS=()
SPIRE_SERVER_BIN="/opt/spire/bin/spire-server"

#############################################
# Function: print_usage
# Display usage information
#############################################
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Register workloads with TPM PCR selectors and Docker selectors for backward compatibility.

Options:
  -s, --spiffe-id <id>       SPIFFE ID for the workload (required)
  -p, --pcr-index <index>    TPM PCR index (0-23, optional)
  -h, --pcr-hash <hash>      TPM PCR hash value (hex string, optional)
  -d, --docker-label <label> Docker label selector in format key:value (can be specified multiple times)
  --help                     Display this help message

Examples:
  # Register with TPM PCR selector only
  $0 --spiffe-id spiffe://example.org/k8s-workload \\
     --pcr-index 0 \\
     --pcr-hash a3f5d8c2e1b4567890abcdef1234567890abcdef1234567890abcdef12345678

  # Register with both TPM and Docker selectors (backward compatibility)
  $0 --spiffe-id spiffe://example.org/k8s-workload \\
     --pcr-index 0 \\
     --pcr-hash a3f5d8c2e1b4567890abcdef1234567890abcdef1234567890abcdef12345678 \\
     --docker-label io.kubernetes.container.name:mtls-app \\
     --docker-label io.kubernetes.pod.namespace:default

Exit Codes:
  0 - Success
  1 - Failure

EOF
}

#############################################
# Function: validate_pcr_selector_format
# Validates TPM PCR selector format
# Arguments:
#   $1 - PCR index
#   $2 - PCR hash
# Returns:
#   0 if valid, 1 if invalid
#############################################
validate_pcr_selector_format() {
    local pcr_index="$1"
    local pcr_hash="$2"
    
    # Validate PCR index is a number between 0 and 23
    if ! [[ "$pcr_index" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ ERROR: PCR index must be a number${NC}" >&2
        return 1
    fi
    
    if [ "$pcr_index" -lt 0 ] || [ "$pcr_index" -gt 23 ]; then
        echo -e "${RED}❌ ERROR: PCR index must be between 0 and 23 (got: $pcr_index)${NC}" >&2
        return 1
    fi
    
    # Validate hash is a valid hexadecimal string
    if ! [[ "$pcr_hash" =~ ^[0-9a-fA-F]+$ ]]; then
        echo -e "${RED}❌ ERROR: PCR hash must be a hexadecimal string (0-9, a-f, A-F)${NC}" >&2
        return 1
    fi
    
    # Validate hash length (common lengths: 32=MD5, 40=SHA1, 48=SHA224, 64=SHA256, 96=SHA384, 128=SHA512)
    local hash_len=${#pcr_hash}
    local valid_lengths=(32 40 48 64 96 128)
    local valid=0
    
    for len in "${valid_lengths[@]}"; do
        if [ "$hash_len" -eq "$len" ]; then
            valid=1
            break
        fi
    done
    
    if [ "$valid" -eq 0 ]; then
        echo -e "${RED}❌ ERROR: PCR hash length must be one of: ${valid_lengths[*]} (got: $hash_len)${NC}" >&2
        echo -e "${YELLOW}   Common lengths: 40 (SHA1), 64 (SHA256), 96 (SHA384), 128 (SHA512)${NC}" >&2
        return 1
    fi
    
    return 0
}

#############################################
# Function: validate_spiffe_id
# Validates SPIFFE ID format
# Arguments:
#   $1 - SPIFFE ID
# Returns:
#   0 if valid, 1 if invalid
#############################################
validate_spiffe_id() {
    local spiffe_id="$1"
    
    if [ -z "$spiffe_id" ]; then
        echo -e "${RED}❌ ERROR: SPIFFE ID cannot be empty${NC}" >&2
        return 1
    fi
    
    if ! [[ "$spiffe_id" =~ ^spiffe:// ]]; then
        echo -e "${RED}❌ ERROR: SPIFFE ID must start with 'spiffe://' (got: $spiffe_id)${NC}" >&2
        return 1
    fi
    
    return 0
}

#############################################
# Function: get_agent_id
# Retrieves the SPIRE Agent ID dynamically
# Returns:
#   Agent ID on success, exits on failure
#############################################
get_agent_id() {
    echo "Retrieving SPIRE Agent ID..."
    
    local agent_id
    agent_id=$($SPIRE_SERVER_BIN agent list 2>/dev/null | grep "SPIFFE ID" | awk '{print $4}' | head -n 1)
    
    if [ -z "$agent_id" ]; then
        echo -e "${RED}❌ ERROR: Could not retrieve SPIRE Agent ID${NC}" >&2
        echo "Make sure the SPIRE Server is running and the agent is registered" >&2
        exit 1
    fi
    
    echo -e "${GREEN}✅ Agent ID retrieved: $agent_id${NC}"
    echo "$agent_id"
}

#############################################
# Function: delete_existing_entry
# Deletes existing workload entry if it exists
# Arguments:
#   $1 - SPIFFE ID
#############################################
delete_existing_entry() {
    local spiffe_id="$1"
    
    echo ""
    echo "Checking for existing registrations with spiffeID: $spiffe_id"
    
    # Check if entry exists
    if $SPIRE_SERVER_BIN entry show -spiffeID "$spiffe_id" &>/dev/null; then
        echo "Found existing registration for $spiffe_id"
        echo "Deleting old entry..."
        
        if $SPIRE_SERVER_BIN entry delete -spiffeID "$spiffe_id" 2>&1; then
            echo -e "${GREEN}✅ Successfully deleted old registration${NC}"
        else
            echo -e "${YELLOW}⚠️  Warning: Could not delete old registration${NC}"
        fi
    else
        echo "No existing registrations found for $spiffe_id"
    fi
}

#############################################
# Function: register_workload
# Registers workload with SPIRE Server
# Arguments:
#   $1 - Parent ID (agent ID)
#   $2 - SPIFFE ID
#   $3 - PCR index (optional)
#   $4 - PCR hash (optional)
#   $@ - Docker labels (remaining arguments)
#############################################
register_workload() {
    local parent_id="$1"
    local spiffe_id="$2"
    local pcr_index="$3"
    local pcr_hash="$4"
    shift 4
    local docker_labels=("$@")
    
    echo ""
    echo "Creating new workload registration..."
    
    # Build the registration command
    local cmd=("$SPIRE_SERVER_BIN" "entry" "create")
    cmd+=("-parentID" "$parent_id")
    cmd+=("-spiffeID" "$spiffe_id")
    
    # Add TPM PCR selector if provided
    if [ -n "$pcr_index" ] && [ -n "$pcr_hash" ]; then
        local tpm_selector="tpm:pcr:${pcr_index}:${pcr_hash}"
        cmd+=("-selector" "$tpm_selector")
        echo "  Adding TPM selector: $tpm_selector"
    fi
    
    # Add Docker label selectors
    for label in "${docker_labels[@]}"; do
        cmd+=("-selector" "docker:label:${label}")
        echo "  Adding Docker selector: docker:label:${label}"
    done
    
    # Execute registration command
    local output
    output=$("${cmd[@]}" 2>&1)
    
    # Validate registration was created successfully
    if echo "$output" | grep -q "Entry ID"; then
        local entry_id
        entry_id=$(echo "$output" | grep "Entry ID" | awk '{print $4}')
        echo -e "${GREEN}✅ Workload registration created successfully${NC}"
        echo "   Entry ID: $entry_id"
        echo "   SPIFFE ID: $spiffe_id"
        echo "   Parent ID: $parent_id"
        
        # Display selectors
        echo "   Selectors:"
        if [ -n "$pcr_index" ] && [ -n "$pcr_hash" ]; then
            echo "     - tpm:pcr:${pcr_index}:${pcr_hash}"
        fi
        for label in "${docker_labels[@]}"; do
            echo "     - docker:label:${label}"
        done
        
        return 0
    else
        echo -e "${RED}❌ ERROR: Failed to create workload registration${NC}" >&2
        echo "Output: $output" >&2
        return 1
    fi
}

#############################################
# Function: verify_registration
# Verifies the registration exists in SPIRE Server
# Arguments:
#   $1 - SPIFFE ID
#############################################
verify_registration() {
    local spiffe_id="$1"
    
    echo ""
    echo "Verifying registration..."
    
    if $SPIRE_SERVER_BIN entry show -spiffeID "$spiffe_id" | grep -q "$spiffe_id"; then
        echo -e "${GREEN}✅ Registration verified in SPIRE Server${NC}"
        return 0
    else
        echo -e "${RED}❌ ERROR: Registration not found in SPIRE Server after creation${NC}" >&2
        return 1
    fi
}

#############################################
# Function: validate_pcr_values_accessible
# Validates that TPM PCR values can be read
# Arguments:
#   $1 - PCR index
# Returns:
#   0 if PCR can be read, 1 otherwise
#############################################
validate_pcr_values_accessible() {
    local pcr_index="$1"
    
    # Check if tpm2_pcrread is available
    if ! command -v tpm2_pcrread &> /dev/null; then
        echo -e "${YELLOW}⚠️  Warning: tpm2_pcrread not found, cannot validate PCR accessibility${NC}"
        echo "   Install tpm2-tools for PCR validation: sudo apt-get install tpm2-tools"
        return 0  # Don't fail registration, just warn
    fi
    
    # Try to read the specific PCR
    if ! tpm2_pcrread "sha256:${pcr_index}" > /dev/null 2>&1; then
        echo -e "${RED}❌ ERROR: Cannot read PCR ${pcr_index} from TPM${NC}" >&2
        echo "   This may indicate TPM is not accessible or PCR index is invalid" >&2
        return 1
    fi
    
    return 0
}

#############################################
# Function: warn_about_pcr_mismatch
# Provides detailed warning about PCR mismatch scenarios
# Arguments:
#   $1 - PCR index
#   $2 - PCR hash
#############################################
warn_about_pcr_mismatch() {
    local pcr_index="$1"
    local pcr_hash="$2"
    
    echo ""
    echo -e "${YELLOW}=========================================="
    echo "   IMPORTANT: PCR Mismatch Handling"
    echo "==========================================${NC}"
    echo ""
    echo "You have registered a workload with TPM PCR selector:"
    echo "  PCR Index: $pcr_index"
    echo "  PCR Hash:  $pcr_hash"
    echo ""
    echo -e "${YELLOW}⚠️  PCR Mismatch Scenarios:${NC}"
    echo ""
    echo "If the current PCR value does NOT match the registered hash,"
    echo "SPIRE will DENY SVID requests with detailed error information."
    echo ""
    echo "Common causes of PCR mismatches:"
    echo "  1. System firmware or BIOS updates"
    echo "  2. Bootloader changes (GRUB, systemd-boot)"
    echo "  3. Kernel or initramfs updates"
    echo "  4. Secure Boot configuration changes"
    echo "  5. TPM has been cleared or reset"
    echo ""
    echo "When a mismatch occurs, you will see:"
    echo "  - Error code: PERMISSION_DENIED"
    echo "  - Expected PCR value: $pcr_hash"
    echo "  - Actual PCR value: <current_value>"
    echo "  - PCR index: $pcr_index"
    echo ""
    echo "To resolve PCR mismatches:"
    echo "  1. Verify the change is legitimate"
    echo "  2. Read current PCR values: tpm2_pcrread sha256"
    echo "  3. Update registration with new PCR hash:"
    echo "     sudo $0 --spiffe-id <id> --pcr-index $pcr_index --pcr-hash <new_hash>"
    echo ""
    echo "To validate current PCR values match registration:"
    echo "  sudo ./validate_pcr_match.sh --spiffe-id <spiffe_id>"
    echo ""
    echo "=========================================="
    echo ""
}

#############################################
# Main Script
#############################################

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--spiffe-id)
            SPIFFE_ID="$2"
            shift 2
            ;;
        -p|--pcr-index)
            PCR_INDEX="$2"
            shift 2
            ;;
        -h|--pcr-hash)
            PCR_HASH="$2"
            shift 2
            ;;
        -d|--docker-label)
            DOCKER_LABELS+=("$2")
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo -e "${RED}❌ ERROR: Unknown option: $1${NC}" >&2
            print_usage
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "   TPM-Aware Workload Registration"
echo "=========================================="

# Validate required arguments
if [ -z "$SPIFFE_ID" ]; then
    echo -e "${RED}❌ ERROR: SPIFFE ID is required${NC}" >&2
    echo ""
    print_usage
    exit 1
fi

# Validate SPIFFE ID format
if ! validate_spiffe_id "$SPIFFE_ID"; then
    exit 1
fi

# Validate TPM PCR selector if provided
if [ -n "$PCR_INDEX" ] || [ -n "$PCR_HASH" ]; then
    # Both PCR index and hash must be provided together
    if [ -z "$PCR_INDEX" ] || [ -z "$PCR_HASH" ]; then
        echo -e "${RED}❌ ERROR: Both --pcr-index and --pcr-hash must be provided together${NC}" >&2
        exit 1
    fi
    
    # Validate PCR selector format
    if ! validate_pcr_selector_format "$PCR_INDEX" "$PCR_HASH"; then
        exit 1
    fi
    
    echo -e "${GREEN}✅ TPM PCR selector format validated${NC}"
    
    # Validate PCR values are accessible
    if ! validate_pcr_values_accessible "$PCR_INDEX"; then
        echo -e "${RED}❌ ERROR: PCR validation failed${NC}" >&2
        exit 1
    fi
    
    echo -e "${GREEN}✅ TPM PCR ${PCR_INDEX} is accessible${NC}"
fi

# Ensure at least one selector is provided
if [ -z "$PCR_INDEX" ] && [ ${#DOCKER_LABELS[@]} -eq 0 ]; then
    echo -e "${RED}❌ ERROR: At least one selector must be provided (TPM PCR or Docker label)${NC}" >&2
    exit 1
fi

# Check if SPIRE Server binary exists
if [ ! -f "$SPIRE_SERVER_BIN" ]; then
    echo -e "${RED}❌ ERROR: SPIRE Server binary not found at $SPIRE_SERVER_BIN${NC}" >&2
    exit 1
fi

# Get SPIRE Agent ID
AGENT_ID=$(get_agent_id)

# Delete existing entry if present
delete_existing_entry "$SPIFFE_ID"

# Register workload
if ! register_workload "$AGENT_ID" "$SPIFFE_ID" "$PCR_INDEX" "$PCR_HASH" "${DOCKER_LABELS[@]}"; then
    exit 1
fi

# Verify registration
if ! verify_registration "$SPIFFE_ID"; then
    exit 1
fi

# Warn about PCR mismatch handling if TPM selectors were used
if [ -n "$PCR_INDEX" ] && [ -n "$PCR_HASH" ]; then
    warn_about_pcr_mismatch "$PCR_INDEX" "$PCR_HASH"
fi

echo ""
echo "=========================================="
echo "   Registration Complete"
echo "=========================================="
echo ""
echo "The workload has been successfully registered with SPIRE Server."
echo ""
echo "To view all registrations:"
echo "  sudo $SPIRE_SERVER_BIN entry show"
echo ""
echo "To view this specific registration:"
echo "  sudo $SPIRE_SERVER_BIN entry show -spiffeID $SPIFFE_ID"
echo ""

exit 0
