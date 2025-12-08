#!/bin/bash

# SPIRE Demo with TPM Validation (Without TPM Plugin)
# This script demonstrates TPM-aware workload attestation using standard SPIRE
# with TPM validation at the application layer

set -e

echo "=========================================="
echo "SPIRE Demo with Application-Layer TPM Validation"
echo "=========================================="
echo ""
echo "NOTE: This uses standard SPIRE attestation (join_token)"
echo "      with TPM validation performed at the application layer"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SPIRE_SERVER_CONFIG="/opt/spire/conf/server.conf"
SPIRE_AGENT_CONFIG="/opt/spire/conf/agent.conf"
SPIRE_SERVER_BIN="/opt/spire/bin/spire-server"
SPIRE_AGENT_BIN="/opt/spire/bin/spire-agent"
TRUST_DOMAIN="example.org"
AGENT_SOCKET="/tmp/spire-agent/public/api.sock"

# Function to print colored output
print_info() {
    echo -e "${GREEN}INFO: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Step 1: Checking prerequisites..."
    
    # Check for TPM device
    print_info "Checking for TPM device..."
    if [ -e "/dev/tpmrm0" ]; then
        print_info "SUCCESS: Found TPM resource manager: /dev/tpmrm0"
        
        # Try to read TPM
        if tpm2_pcrread sha256:0 > /dev/null 2>&1; then
            print_info "SUCCESS: TPM device is accessible"
        else
            print_warning "TPM device exists but may not be accessible"
        fi
    else
        print_warning "TPM device not found - will proceed without TPM validation"
    fi
    
    # Check for tpm2-tools
    if command -v tpm2_pcrread &> /dev/null; then
        print_info "SUCCESS: tpm2-tools is installed"
    else
        print_warning "tpm2-tools not found - TPM validation will be skipped"
    fi
    
    # Check for SPIRE binaries
    if [ -f "$SPIRE_SERVER_BIN" ] && [ -f "$SPIRE_AGENT_BIN" ]; then
        print_info "SUCCESS: SPIRE binaries found"
    else
        print_error "SPIRE binaries not found"
        exit 1
    fi
    
    # Check for kubectl
    if command -v kubectl &> /dev/null; then
        print_info "SUCCESS: kubectl is installed"
    else
        print_warning "kubectl not found - Kubernetes deployment will be skipped"
    fi
    
    print_info "SUCCESS: All prerequisites met"
    echo ""
}

# Function to stop existing SPIRE processes
stop_spire() {
    print_info "Step 2: Stopping existing SPIRE processes..."
    
    print_info "Stopping SPIRE Agent..."
    pkill -9 spire-agent || true
    
    print_info "Stopping SPIRE Server..."
    pkill -9 spire-server || true
    
    # Clean up socket
    rm -rf /tmp/spire-agent
    
    sleep 2
    print_info "SUCCESS: Existing SPIRE processes stopped"
    echo ""
}

# Function to start SPIRE Server
start_server() {
    print_info "Step 3: Starting SPIRE Server..."
    
    if [ ! -f "$SPIRE_SERVER_CONFIG" ]; then
        print_error "SPIRE Server config not found: $SPIRE_SERVER_CONFIG"
        exit 1
    fi
    
    print_info "Starting SPIRE Server with standard configuration..."
    $SPIRE_SERVER_BIN run -config "$SPIRE_SERVER_CONFIG" > /opt/spire/server.log 2>&1 &
    
    # Wait for server to start
    print_info "Waiting for SPIRE Server to start..."
    for i in {1..30}; do
        if $SPIRE_SERVER_BIN healthcheck > /dev/null 2>&1; then
            print_info "SUCCESS: SPIRE Server is running"
            echo ""
            return 0
        fi
        sleep 1
    done
    
    print_error "SPIRE Server failed to start"
    print_error "Check logs: tail -50 /opt/spire/server.log"
    exit 1
}

# Function to generate join token
generate_join_token() {
    print_info "Step 4: Generating join token for agent..."
    
    # Generate token with TPM-aware SPIFFE ID
    TOKEN=$($SPIRE_SERVER_BIN token generate \
        -spiffeID spiffe://$TRUST_DOMAIN/agent/tpm-validated \
        -ttl 600 | grep "Token:" | awk '{print $2}')
    
    if [ -z "$TOKEN" ]; then
        print_error "Failed to generate join token"
        exit 1
    fi
    
    print_info "SUCCESS: Join token generated"
    echo "Token: $TOKEN"
    echo ""
    
    echo "$TOKEN"
}

# Function to start SPIRE Agent
start_agent() {
    local TOKEN=$1
    
    print_info "Step 5: Starting SPIRE Agent..."
    
    if [ ! -f "$SPIRE_AGENT_CONFIG" ]; then
        print_error "SPIRE Agent config not found: $SPIRE_AGENT_CONFIG"
        exit 1
    fi
    
    print_info "Starting SPIRE Agent with join token..."
    $SPIRE_AGENT_BIN run \
        -config "$SPIRE_AGENT_CONFIG" \
        -joinToken "$TOKEN" > /opt/spire/agent.log 2>&1 &
    
    # Wait for agent to start
    print_info "Waiting for SPIRE Agent to start..."
    for i in {1..30}; do
        if [ -S "$AGENT_SOCKET" ]; then
            print_info "SUCCESS: SPIRE Agent is running"
            echo ""
            return 0
        fi
        sleep 1
    done
    
    print_error "SPIRE Agent failed to start"
    print_error "Check logs: tail -50 /opt/spire/agent.log"
    exit 1
}

# Function to register workload
register_workload() {
    print_info "Step 6: Registering workload..."
    
    # Register workload with Docker selector
    $SPIRE_SERVER_BIN entry create \
        -parentID spiffe://$TRUST_DOMAIN/agent/tpm-validated \
        -spiffeID spiffe://$TRUST_DOMAIN/workload/mtls-demo \
        -selector docker:label:app:mtls-demo \
        -x509SVIDTTL 3600 2>&1 | tee /tmp/spire-entry-create.log
    
    if [ $? -eq 0 ]; then
        print_info "SUCCESS: Workload registered"
    elif grep -q "AlreadyExists" /tmp/spire-entry-create.log; then
        print_info "SUCCESS: Workload entry already exists (skipping)"
    else
        print_error "Failed to register workload"
        cat /tmp/spire-entry-create.log
        exit 1
    fi
    echo ""
}

# Function to read and log TPM PCR values
log_tpm_state() {
    print_info "Step 7: Reading TPM state..."
    
    if command -v tpm2_pcrread &> /dev/null && [ -e "/dev/tpmrm0" ]; then
        print_info "Current TPM PCR values:"
        tpm2_pcrread sha256:0,1,2,3,4,5,6,7 || print_warning "Could not read all PCRs"
    else
        print_warning "TPM not available - skipping PCR read"
    fi
    echo ""
}

# Function to run Python demo
run_python_demo() {
    print_info "Step 8: Running Python mTLS demo..."
    
    if [ ! -f "mtls_demo.py" ]; then
        print_error "mtls_demo.py not found in current directory"
        exit 1
    fi
    
    print_info "Starting mTLS demo with TPM validation..."
    print_info "The application will validate TPM state before fetching SVIDs"
    echo ""
    
    # Run the demo
    python3 mtls_demo.py
    
    if [ $? -eq 0 ]; then
        print_info "SUCCESS: Demo completed successfully"
    else
        print_error "Demo failed"
        exit 1
    fi
}

# Function to verify setup
verify_setup() {
    print_info "Step 9: Verifying setup..."
    
    # Check agent list
    print_info "Checking registered agents:"
    $SPIRE_SERVER_BIN agent list
    
    echo ""
    
    # Check entries
    print_info "Checking registered workload entries:"
    $SPIRE_SERVER_BIN entry show
    
    echo ""
    print_info "SUCCESS: Verification complete"
}

# Main execution
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Run all steps
    check_prerequisites
    stop_spire
    start_server
    TOKEN=$(generate_join_token)
    start_agent "$TOKEN"
    register_workload
    log_tpm_state
    
    print_info "=========================================="
    print_info "SPIRE Setup Complete!"
    print_info "=========================================="
    echo ""
    print_info "Next steps:"
    echo "  1. Run the Python demo: python3 mtls_demo.py"
    echo "  2. Verify TPM state: tpm2_pcrread"
    echo "  3. Check SPIRE logs:"
    echo "     - Server: tail -f /opt/spire/server.log"
    echo "     - Agent: tail -f /opt/spire/agent.log"
    echo ""
    print_info "Note: This setup uses standard SPIRE attestation"
    print_info "      TPM validation is performed at the application layer"
    echo ""
    
    # Ask if user wants to run demo now
    read -p "Run Python mTLS demo now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_python_demo
    fi
}

# Run main function
main
