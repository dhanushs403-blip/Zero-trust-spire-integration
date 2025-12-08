#!/bin/bash

# TPM Attestation Verification Script
# This script verifies that TPM attestation is active in SPIRE
# Requirements: 4.5, 7.1, 7.2, 7.3, 7.4, 7.5

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration paths
SPIRE_SERVER_BIN="/opt/spire/bin/spire-server"
SPIRE_AGENT_BIN="/opt/spire/bin/spire-agent"
SPIRE_AGENT_LOG="/var/log/spire/agent.log"
SPIRE_SERVER_SOCKET="/tmp/spire-server/private/api.sock"
SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"

# Verification results
TPM_ATTESTATION_ACTIVE=false
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Function to print colored messages
print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
    ((CHECKS_FAILED++))
}

print_success() {
    echo -e "${GREEN}✓ SUCCESS: $1${NC}"
    ((CHECKS_PASSED++))
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
    ((CHECKS_WARNING++))
}

print_info() {
    echo -e "${BLUE}ℹ INFO: $1${NC}"
}

print_section() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to check if SPIRE binaries exist
check_spire_binaries() {
    print_section "Checking SPIRE Binaries"
    
    if [ -x "$SPIRE_SERVER_BIN" ]; then
        print_success "SPIRE Server binary found at $SPIRE_SERVER_BIN"
    else
        print_error "SPIRE Server binary not found or not executable at $SPIRE_SERVER_BIN"
        return 1
    fi
    
    if [ -x "$SPIRE_AGENT_BIN" ]; then
        print_success "SPIRE Agent binary found at $SPIRE_AGENT_BIN"
    else
        print_error "SPIRE Agent binary not found or not executable at $SPIRE_AGENT_BIN"
        return 1
    fi
    
    return 0
}

# Function to check SPIRE Agent parent ID for TPM indicator (Requirement 7.1)
check_agent_parent_id() {
    print_section "Checking SPIRE Agent Parent ID"
    
    # Check if agent socket exists
    if [ ! -S "$SPIRE_AGENT_SOCKET" ]; then
        print_error "SPIRE Agent socket not found at $SPIRE_AGENT_SOCKET"
        print_info "HINT: Ensure SPIRE Agent is running"
        return 1
    fi
    
    # Try to get agent info using spire-agent api fetch
    local agent_info
    if agent_info=$("$SPIRE_AGENT_BIN" api fetch 2>&1); then
        print_success "Successfully connected to SPIRE Agent API"
        
        # Check if the output contains TPM-related information
        if echo "$agent_info" | grep -qi "tpm"; then
            print_success "Agent parent ID contains 'tpm' indicator"
            print_info "TPM attestation is active for this agent"
            TPM_ATTESTATION_ACTIVE=true
            
            # Extract and display the SPIFFE ID
            local spiffe_id
            spiffe_id=$(echo "$agent_info" | grep -i "spiffe://" | head -1 || echo "")
            if [ -n "$spiffe_id" ]; then
                print_info "Agent SPIFFE ID: $spiffe_id"
            fi
        else
            print_warning "Agent parent ID does not contain 'tpm' indicator"
            print_info "TPM attestation may not be active"
            print_info "Agent info output:"
            echo "$agent_info" | head -10
        fi
    else
        print_error "Failed to fetch agent information"
        print_info "HINT: Ensure SPIRE Agent is running and accessible"
        print_info "HINT: Check agent logs: tail -f $SPIRE_AGENT_LOG"
        return 1
    fi
    
    return 0
}

# Function to query SPIRE Server entries for TPM selectors (Requirement 7.2)
check_server_entries() {
    print_section "Checking SPIRE Server Entries for TPM Selectors"
    
    # Check if server socket exists
    if [ ! -S "$SPIRE_SERVER_SOCKET" ]; then
        print_error "SPIRE Server socket not found at $SPIRE_SERVER_SOCKET"
        print_info "HINT: Ensure SPIRE Server is running"
        return 1
    fi
    
    # Try to list entries
    local entries
    if entries=$("$SPIRE_SERVER_BIN" entry show 2>&1); then
        print_success "Successfully queried SPIRE Server entries"
        
        # Check if any entries have TPM selectors
        if echo "$entries" | grep -q "tpm:pcr:"; then
            print_success "Found workload entries with TPM PCR selectors"
            
            # Count and display TPM entries
            local tpm_entry_count
            tpm_entry_count=$(echo "$entries" | grep -c "tpm:pcr:" || echo "0")
            print_info "Number of TPM selector entries: $tpm_entry_count"
            
            # Display sample TPM selectors
            print_info "Sample TPM selectors:"
            echo "$entries" | grep "tpm:pcr:" | head -3 | sed 's/^/  /'
        else
            print_warning "No workload entries with TPM PCR selectors found"
            print_info "This is normal if workloads are using Docker selectors only"
            print_info "To use TPM workload attestation, register entries with TPM selectors"
        fi
        
        # Check for TPM-attested agents
        if echo "$entries" | grep -qi "spire/agent/tpm"; then
            print_success "Found TPM-attested agent entries"
            TPM_ATTESTATION_ACTIVE=true
        else
            print_warning "No TPM-attested agent entries found"
        fi
    else
        print_error "Failed to query SPIRE Server entries"
        print_info "HINT: Ensure SPIRE Server is running and accessible"
        print_info "HINT: You may need appropriate permissions to query entries"
        return 1
    fi
    
    return 0
}

# Function to examine SPIRE Agent logs for TPM initialization (Requirement 7.3)
check_agent_logs() {
    print_section "Checking SPIRE Agent Logs for TPM Initialization"
    
    # Try multiple possible log locations
    local log_locations=(
        "$SPIRE_AGENT_LOG"
        "/var/log/spire-agent.log"
        "/tmp/spire-agent.log"
        "/opt/spire/logs/agent.log"
    )
    
    local log_file=""
    for location in "${log_locations[@]}"; do
        if [ -f "$location" ]; then
            log_file="$location"
            break
        fi
    done
    
    if [ -z "$log_file" ]; then
        print_warning "SPIRE Agent log file not found at standard locations"
        print_info "Checked locations: ${log_locations[*]}"
        print_info "HINT: Check systemd journal: journalctl -u spire-agent -n 100"
        return 1
    fi
    
    print_success "Found SPIRE Agent log at $log_file"
    
    # Check agent logs for TPM initialization
    print_info "Checking agent logs for TPM initialization..."
    if grep -q "tpm_devid" "$log_file" 2>/dev/null; then
        print_success "TPM initialization messages found in agent logs"
        TPM_ATTESTATION_ACTIVE=true
        print_info "Recent TPM-related log entries:"
        grep -i "tpm_devid" "$log_file" | tail -5 | sed 's/^/  /'
    else
        print_warning "No TPM-specific messages in agent logs"
        print_info "This may indicate TPM attestation is not configured"
        
        # Show recent log entries for context
        print_info "Recent agent log entries:"
        tail -5 "$log_file" | sed 's/^/  /'
    fi
    
    # Check for TPM-related errors
    if grep -qi "tpm.*error\|tpm.*fail" "$log_file"; then
        print_error "Found TPM-related errors in agent logs"
        print_info "TPM error messages:"
        grep -i "tpm.*error\|tpm.*fail" "$log_file" | tail -3 | sed 's/^/  /'
        return 1
    fi
    
    return 0
}

# Function to read and display current TPM PCR values (Requirement 7.4)
check_tpm_pcr_values() {
    print_section "Reading Current TPM PCR Values"
    
    # Check if tpm2_pcrread is available
    if ! command -v tpm2_pcrread &> /dev/null; then
        print_warning "tpm2_pcrread command not found"
        print_info "HINT: Install tpm2-tools: sudo apt-get install tpm2-tools"
        return 1
    fi
    
    # Check if TPM device is accessible
    if [ ! -e /dev/tpmrm0 ] && [ ! -e /dev/tpm0 ]; then
        print_error "TPM device not found at /dev/tpmrm0 or /dev/tpm0"
        print_info "HINT: Verify TPM is enabled in BIOS/UEFI settings"
        return 1
    fi
    
    # Try to read PCR values
    local pcr_output
    if pcr_output=$(tpm2_pcrread sha256 2>&1); then
        print_success "Successfully read TPM PCR values"
        
        # Display PCR values
        print_info "TPM PCR Values (SHA256 bank):"
        echo "$pcr_output" | sed 's/^/  /'
        
        # Highlight commonly used PCRs
        print_info "Commonly used PCRs for attestation:"
        echo "$pcr_output" | grep -E "^\s*(0|1|2|3|4|5|6|7):" | sed 's/^/  /' || true
    else
        print_error "Failed to read TPM PCR values"
        print_info "Error output:"
        echo "$pcr_output" | sed 's/^/  /'
        print_info "HINT: Ensure TPM device is accessible and tpm2-abrmd is running"
        return 1
    fi
    
    return 0
}

# Function to check TPM device accessibility
check_tpm_device() {
    print_section "Checking TPM Device Accessibility"
    
    if [ -e /dev/tpmrm0 ]; then
        print_success "TPM resource manager device found: /dev/tpmrm0"
        ls -la /dev/tpmrm0 | sed 's/^/  /'
    elif [ -e /dev/tpm0 ]; then
        print_success "TPM character device found: /dev/tpm0"
        ls -la /dev/tpm0 | sed 's/^/  /'
        print_warning "/dev/tpmrm0 (resource manager) is preferred"
    else
        print_error "TPM device not found"
        print_info "HINT: Verify TPM is enabled in BIOS/UEFI settings"
        return 1
    fi
    
    return 0
}

# Function to check SPIRE configuration files
check_spire_configs() {
    print_section "Checking SPIRE Configuration Files"
    
    local server_conf="/opt/spire/conf/server/server.conf"
    local agent_conf="/opt/spire/conf/agent/agent.conf"
    
    # Verify server config
    if [ -f "$SPIRE_SERVER_CONF" ]; then
        if grep -q 'NodeAttestor "tpm_devid"' "$SPIRE_SERVER_CONF"; then
            print_success "Server configuration contains TPM node attestor"
        else
            print_error "Server configuration missing TPM node attestor"
            verification_passed=false
            print_info "HINT: Run setup_tpm.sh to configure TPM attestation"
        fi
    else
        print_warning "Server configuration not found at $server_conf"
    fi
    
    # Check agent config
    if [ -f "$agent_conf" ]; then
        if grep -q 'NodeAttestor "tpm_devid"' "$agent_conf"; then
            print_success "Agent configuration contains TPM node attestor"
            
            # Check for TPM device path
            if grep -q "tpm_device_path" "$agent_conf"; then
                local device_path
                device_path=$(grep "tpm_device_path" "$agent_conf" | sed 's/.*=\s*"\([^"]*\)".*/\1/')
                print_info "Configured TPM device path: $device_path"
            fi
        else
            print_warning "Agent configuration does not contain TPM node attestor"
            print_info "HINT: Run setup_tpm.sh to configure TPM attestation"
        fi
    else
        print_warning "Agent configuration not found at $agent_conf"
    fi
    
    return 0
}

# Function to report overall TPM attestation status (Requirement 7.5)
report_attestation_status() {
    print_section "TPM Attestation Status Report"
    
    echo ""
    echo "Verification Summary:"
    echo "  ✓ Checks Passed:  $CHECKS_PASSED"
    echo "  ✗ Checks Failed:  $CHECKS_FAILED"
    echo "  ⚠ Warnings:       $CHECKS_WARNING"
    echo ""
    
    if [ "$TPM_ATTESTATION_ACTIVE" = true ]; then
        print_success "TPM ATTESTATION IS ACTIVE"
        echo ""
        print_info "TPM attestation is properly configured and functioning"
        print_info "The SPIRE Agent is using TPM for node attestation"
        echo ""
        return 0
    else
        print_warning "TPM ATTESTATION IS INACTIVE OR NOT DETECTED"
        echo ""
        print_info "TPM attestation may not be configured or active"
        print_info "Possible reasons:"
        echo "  1. SPIRE components not configured for TPM attestation"
        echo "  2. SPIRE Agent not started with TPM configuration"
        echo "  3. TPM device not accessible or not functioning"
        echo ""
        print_info "To enable TPM attestation:"
        echo "  1. Run setup_tpm.sh to configure SPIRE for TPM"
        echo "  2. Restart SPIRE Server and Agent"
        echo "  3. Re-run this verification script"
        echo ""
        return 1
    fi
}

# Main execution
main() {
    echo ""
    print_section "TPM Attestation Verification for SPIRE"
    echo ""
    print_info "This script verifies that TPM attestation is active in SPIRE"
    print_info "Checking multiple indicators to determine TPM attestation status"
    echo ""
    
    # Run all verification checks
    check_spire_binaries || true
    echo ""
    
    check_tpm_device || true
    echo ""
    
    check_spire_configs || true
    echo ""
    
    check_agent_parent_id || true
    echo ""
    
    check_server_entries || true
    echo ""
    
    check_agent_logs || true
    echo ""
    
    check_tpm_pcr_values || true
    echo ""
    
    # Report final status
    report_attestation_status
    
    # Exit with appropriate code
    if [ "$TPM_ATTESTATION_ACTIVE" = true ] && [ "$CHECKS_FAILED" -eq 0 ]; then
        exit 0
    elif [ "$TPM_ATTESTATION_ACTIVE" = true ]; then
        exit 0  # Active but with some warnings
    else
        exit 1  # Not active
    fi
}

# Run main function
main "$@"
