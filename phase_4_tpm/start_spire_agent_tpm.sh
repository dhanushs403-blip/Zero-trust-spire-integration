#!/bin/bash

#############################################
# SPIRE Agent Startup Script with TPM Error Handling
#############################################
# Purpose: Start SPIRE Agent with comprehensive TPM device error handling
# Requirements: 1.5
#
# This script implements fail-fast behavior for SPIRE Agent startup when
# TPM attestation is configured. It performs pre-flight checks to ensure
# the TPM device is accessible before attempting to start the agent.
#
# Usage:
#   sudo ./start_spire_agent_tpm.sh [OPTIONS]
#
# Options:
#   --config <path>    Path to agent configuration file (default: /opt/spire/conf/agent/agent.conf)
#   --join-token <token>  Join token for agent registration (optional)
#   --help             Display this help message
#
# Exit Codes:
#   0 - Success: Agent started successfully
#   1 - Failure: TPM device not found
#   2 - Failure: TPM device not accessible (permission denied)
#   3 - Failure: TPM configuration invalid
#   4 - Failure: Agent startup failed
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
EXIT_TPM_NOT_FOUND=1
EXIT_TPM_NOT_ACCESSIBLE=2
EXIT_TPM_CONFIG_INVALID=3
EXIT_AGENT_START_FAILED=4

# Default configuration
SPIRE_AGENT_BIN="/opt/spire/bin/spire-agent"
SPIRE_AGENT_CONF="/opt/spire/conf/agent/agent.conf"
SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
JOIN_TOKEN=""
AGENT_LOG="/opt/spire/agent.log"

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

# Function to print usage
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Start SPIRE Agent with TPM attestation and comprehensive error handling.

Options:
  --config <path>        Path to agent configuration file
                         (default: /opt/spire/conf/agent/agent.conf)
  --join-token <token>   Join token for agent registration (optional)
  --help                 Display this help message

Examples:
  # Start agent with default configuration
  sudo $0

  # Start agent with custom configuration
  sudo $0 --config /path/to/agent.conf

  # Start agent with join token
  sudo $0 --join-token <token>

Exit Codes:
  0 - Success
  1 - TPM device not found
  2 - TPM device not accessible
  3 - TPM configuration invalid
  4 - Agent startup failed

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            SPIRE_AGENT_CONF="$2"
            shift 2
            ;;
        --join-token)
            JOIN_TOKEN="$2"
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "   SPIRE Agent Startup (TPM-Enabled)"
echo "=========================================="
echo ""

#############################################
# Step 1: Check if TPM attestation is configured
#############################################
print_info "Step 1: Checking agent configuration..."

if [ ! -f "$SPIRE_AGENT_CONF" ]; then
    print_error "Agent configuration file not found: $SPIRE_AGENT_CONF"
    print_error "HINT: Ensure SPIRE Agent is installed and configured"
    exit $EXIT_TPM_CONFIG_INVALID
fi

# Check if TPM node attestor is configured
if ! grep -q 'NodeAttestor.*"tpm"' "$SPIRE_AGENT_CONF"; then
    print_warning "TPM node attestor not found in configuration"
    print_info "Starting agent without TPM pre-flight checks"
    TPM_ENABLED=false
else
    print_success "TPM node attestor configured"
    TPM_ENABLED=true
fi

echo ""

#############################################
# Step 2: TPM Device Pre-Flight Checks (if TPM is enabled)
#############################################
if [ "$TPM_ENABLED" = true ]; then
    print_info "Step 2: Performing TPM device pre-flight checks..."
    
    # Extract TPM device path from configuration
    TPM_DEVICE_PATH=$(grep -A 10 'NodeAttestor.*"tpm"' "$SPIRE_AGENT_CONF" | grep "tpm_device_path" | sed 's/.*=\s*"\([^"]*\)".*/\1/')
    
    if [ -z "$TPM_DEVICE_PATH" ]; then
        # Default to /dev/tpmrm0 if not specified
        TPM_DEVICE_PATH="/dev/tpmrm0"
        print_info "No TPM device path specified in config, using default: $TPM_DEVICE_PATH"
    else
        print_info "TPM device path from config: $TPM_DEVICE_PATH"
    fi
    
    # Check if TPM device exists
    if [ ! -e "$TPM_DEVICE_PATH" ]; then
        # Try fallback to /dev/tpm0
        if [ ! -e "/dev/tpm0" ]; then
            print_error "TPM device not found at $TPM_DEVICE_PATH or /dev/tpm0"
            print_error ""
            print_error "TROUBLESHOOTING HINTS:"
            print_error "  1. Verify TPM is enabled in BIOS/UEFI settings"
            print_error "     - Reboot and enter BIOS/UEFI setup"
            print_error "     - Look for 'Security' or 'Advanced' settings"
            print_error "     - Enable 'TPM Device' or 'Security Chip'"
            print_error ""
            print_error "  2. Check if TPM kernel modules are loaded:"
            print_error "     lsmod | grep tpm"
            print_error ""
            print_error "  3. Check if tpm2-abrmd service is running:"
            print_error "     systemctl status tpm2-abrmd"
            print_error ""
            print_error "  4. Try starting tpm2-abrmd service:"
            print_error "     sudo systemctl start tpm2-abrmd"
            print_error ""
            print_error "  5. Check dmesg for TPM-related errors:"
            print_error "     dmesg | grep -i tpm"
            print_error ""
            print_error "SPIRE Agent startup aborted to prevent insecure operation without TPM attestation."
            exit $EXIT_TPM_NOT_FOUND
        else
            print_warning "TPM device not found at $TPM_DEVICE_PATH, but found at /dev/tpm0"
            print_info "Consider updating configuration to use /dev/tpm0"
            TPM_DEVICE_PATH="/dev/tpm0"
        fi
    fi
    
    print_success "TPM device found: $TPM_DEVICE_PATH"
    
    # Check TPM device accessibility (read/write permissions)
    if [ ! -r "$TPM_DEVICE_PATH" ]; then
        print_error "TPM device $TPM_DEVICE_PATH is not readable (permission denied)"
        print_error ""
        print_error "Current permissions:"
        ls -la "$TPM_DEVICE_PATH" >&2
        print_error ""
        print_error "TROUBLESHOOTING HINTS:"
        print_error "  1. Check device ownership and permissions:"
        print_error "     ls -la $TPM_DEVICE_PATH"
        print_error ""
        print_error "  2. Add current user to 'tss' group:"
        print_error "     sudo usermod -a -G tss \$USER"
        print_error "     Then log out and log back in"
        print_error ""
        print_error "  3. Temporarily change device permissions (not recommended for production):"
        print_error "     sudo chmod 666 $TPM_DEVICE_PATH"
        print_error ""
        print_error "  4. Run SPIRE Agent as root or with appropriate privileges:"
        print_error "     sudo $0"
        print_error ""
        print_error "  5. Check if tpm2-abrmd is running with correct permissions:"
        print_error "     systemctl status tpm2-abrmd"
        print_error ""
        print_error "SPIRE Agent startup aborted to prevent insecure operation without TPM attestation."
        exit $EXIT_TPM_NOT_ACCESSIBLE
    fi
    
    if [ ! -w "$TPM_DEVICE_PATH" ]; then
        print_error "TPM device $TPM_DEVICE_PATH is not writable (permission denied)"
        print_error ""
        print_error "Current permissions:"
        ls -la "$TPM_DEVICE_PATH" >&2
        print_error ""
        print_error "TROUBLESHOOTING HINTS:"
        print_error "  1. Check device ownership and permissions:"
        print_error "     ls -la $TPM_DEVICE_PATH"
        print_error ""
        print_error "  2. Add current user to 'tss' group:"
        print_error "     sudo usermod -a -G tss \$USER"
        print_error "     Then log out and log back in"
        print_error ""
        print_error "  3. Temporarily change device permissions (not recommended for production):"
        print_error "     sudo chmod 666 $TPM_DEVICE_PATH"
        print_error ""
        print_error "  4. Run SPIRE Agent as root or with appropriate privileges:"
        print_error "     sudo $0"
        print_error ""
        print_error "  5. Check if tpm2-abrmd is running with correct permissions:"
        print_error "     systemctl status tpm2-abrmd"
        print_error ""
        print_error "SPIRE Agent startup aborted to prevent insecure operation without TPM attestation."
        exit $EXIT_TPM_NOT_ACCESSIBLE
    fi
    
    print_success "TPM device is accessible (read/write permissions OK)"
    
    # Verify TPM is functional by attempting to read capabilities
    if command -v tpm2_getcap &> /dev/null; then
        print_info "Verifying TPM functionality..."
        if ! tpm2_getcap properties-fixed > /dev/null 2>&1; then
            print_error "TPM device exists but is not functional"
            print_error ""
            print_error "TROUBLESHOOTING HINTS:"
            print_error "  1. Check if TPM is properly initialized:"
            print_error "     tpm2_getcap properties-fixed"
            print_error ""
            print_error "  2. Check if tpm2-abrmd service is running:"
            print_error "     systemctl status tpm2-abrmd"
            print_error ""
            print_error "  3. Try restarting tpm2-abrmd service:"
            print_error "     sudo systemctl restart tpm2-abrmd"
            print_error ""
            print_error "  4. Check dmesg for TPM errors:"
            print_error "     dmesg | grep -i tpm"
            print_error ""
            print_error "  5. Try clearing TPM (WARNING: This will erase TPM data):"
            print_error "     tpm2_clear"
            print_error ""
            print_error "SPIRE Agent startup aborted to prevent insecure operation without TPM attestation."
            exit $EXIT_TPM_NOT_ACCESSIBLE
        fi
        print_success "TPM device is functional"
    else
        print_warning "tpm2-tools not installed, skipping TPM functionality check"
        print_info "Install tpm2-tools for better diagnostics: sudo apt-get install tpm2-tools"
    fi
    
    print_success "All TPM pre-flight checks passed"
    echo ""
fi

#############################################
# Step 3: Stop Existing Agent
#############################################
print_info "Step 3: Stopping existing SPIRE Agent processes..."

if pgrep -f "spire-agent" > /dev/null; then
    print_info "Found running SPIRE Agent, stopping..."
    pkill -f "spire-agent" || true
    sleep 2
    
    # Verify agent stopped
    if pgrep -f "spire-agent" > /dev/null; then
        print_warning "SPIRE Agent did not stop gracefully, forcing..."
        pkill -9 -f "spire-agent" || true
        sleep 1
    fi
fi

# Clean up socket
if [ -S "$SPIRE_AGENT_SOCKET" ]; then
    print_info "Removing existing socket..."
    rm -f "$SPIRE_AGENT_SOCKET"
fi

print_success "No existing agent processes running"
echo ""

#############################################
# Step 4: Start SPIRE Agent
#############################################
print_info "Step 4: Starting SPIRE Agent..."

# Create socket directory
mkdir -p "$(dirname $SPIRE_AGENT_SOCKET)"

# Build agent command
AGENT_CMD="$SPIRE_AGENT_BIN run -config $SPIRE_AGENT_CONF"

if [ -n "$JOIN_TOKEN" ]; then
    AGENT_CMD="$AGENT_CMD -joinToken $JOIN_TOKEN"
    print_info "Using provided join token"
fi

# Start agent in background
print_info "Executing: $AGENT_CMD"
nohup $AGENT_CMD > "$AGENT_LOG" 2>&1 &
AGENT_PID=$!

print_info "SPIRE Agent started with PID: $AGENT_PID"
print_info "Log file: $AGENT_LOG"

# Wait for agent to initialize
print_info "Waiting for agent to initialize..."
sleep 5

# Check if agent process is still running
if ! kill -0 $AGENT_PID 2>/dev/null; then
    print_error "SPIRE Agent process died shortly after startup"
    print_error ""
    print_error "Last 30 lines of agent log:"
    echo "=========================================="
    tail -30 "$AGENT_LOG" >&2
    echo "=========================================="
    print_error ""
    
    # Check for TPM-specific errors in log
    if grep -i "tpm" "$AGENT_LOG" | grep -i "error\|fail" > /dev/null 2>&1; then
        print_error "TPM-related errors found in log:"
        grep -i "tpm" "$AGENT_LOG" | grep -i "error\|fail" >&2
        print_error ""
        print_error "TROUBLESHOOTING HINTS:"
        print_error "  1. Verify TPM device path in configuration matches actual device"
        print_error "  2. Check TPM device permissions"
        print_error "  3. Ensure tpm2-abrmd service is running"
        print_error "  4. Review full agent log: tail -100 $AGENT_LOG"
    fi
    
    exit $EXIT_AGENT_START_FAILED
fi

print_success "Agent process is running"

# Wait for socket to be created
print_info "Waiting for agent socket to be created..."
SOCKET_TIMEOUT=30
SOCKET_ELAPSED=0

while [ $SOCKET_ELAPSED -lt $SOCKET_TIMEOUT ]; do
    if [ -S "$SPIRE_AGENT_SOCKET" ]; then
        print_success "Agent socket created: $SPIRE_AGENT_SOCKET"
        ls -la "$SPIRE_AGENT_SOCKET"
        break
    fi
    
    # Check if agent is still running
    if ! kill -0 $AGENT_PID 2>/dev/null; then
        print_error "SPIRE Agent process died while waiting for socket"
        print_error ""
        print_error "Last 30 lines of agent log:"
        echo "=========================================="
        tail -30 "$AGENT_LOG" >&2
        echo "=========================================="
        exit $EXIT_AGENT_START_FAILED
    fi
    
    sleep 1
    SOCKET_ELAPSED=$((SOCKET_ELAPSED + 1))
done

if [ ! -S "$SPIRE_AGENT_SOCKET" ]; then
    print_error "Agent socket not created within timeout ($SOCKET_TIMEOUT seconds)"
    print_error ""
    print_error "Last 30 lines of agent log:"
    echo "=========================================="
    tail -30 "$AGENT_LOG" >&2
    echo "=========================================="
    print_error ""
    print_error "TROUBLESHOOTING HINTS:"
    print_error "  1. Check agent configuration for socket_path setting"
    print_error "  2. Verify directory permissions for socket path"
    print_error "  3. Review full agent log: tail -100 $AGENT_LOG"
    exit $EXIT_AGENT_START_FAILED
fi

# Verify agent is responding
print_info "Verifying agent health..."
sleep 2

if ! "$SPIRE_AGENT_BIN" healthcheck -socketPath "$SPIRE_AGENT_SOCKET" > /dev/null 2>&1; then
    print_warning "Agent healthcheck failed, but process is running"
    print_info "Agent may still be initializing, check logs for details"
else
    print_success "Agent healthcheck passed"
fi

echo ""

#############################################
# Step 5: Verify TPM Attestation (if enabled)
#############################################
if [ "$TPM_ENABLED" = true ]; then
    print_info "Step 5: Verifying TPM attestation initialization..."
    
    # Wait a bit more for TPM attestation to complete
    sleep 5
    
    # Check agent log for TPM-related messages
    if grep -i "tpm" "$AGENT_LOG" > /dev/null 2>&1; then
        print_info "TPM-related log messages:"
        echo "=========================================="
        grep -i "tpm" "$AGENT_LOG" | tail -10
        echo "=========================================="
        
        # Check for errors
        if grep -i "tpm" "$AGENT_LOG" | grep -i "error\|fail" > /dev/null 2>&1; then
            print_warning "TPM errors detected in agent log"
            print_warning "Agent may not be using TPM attestation correctly"
            print_info "Review full log: tail -100 $AGENT_LOG"
        else
            print_success "TPM attestation appears to be working"
        fi
    else
        print_warning "No TPM-related messages found in agent log"
        print_info "Agent may still be initializing, check logs later"
    fi
    
    echo ""
fi

#############################################
# Summary
#############################################
echo "=========================================="
print_success "SPIRE Agent Started Successfully!"
echo "=========================================="
echo ""
print_info "Agent Details:"
echo "  - PID: $AGENT_PID"
echo "  - Socket: $SPIRE_AGENT_SOCKET"
echo "  - Config: $SPIRE_AGENT_CONF"
echo "  - Log: $AGENT_LOG"
if [ "$TPM_ENABLED" = true ]; then
    echo "  - TPM Device: $TPM_DEVICE_PATH"
    echo "  - TPM Attestation: Enabled"
fi
echo ""
print_info "Useful Commands:"
echo "  - Check agent health: $SPIRE_AGENT_BIN healthcheck -socketPath $SPIRE_AGENT_SOCKET"
echo "  - View agent log: tail -f $AGENT_LOG"
echo "  - Stop agent: sudo pkill -f spire-agent"
echo ""
echo "=========================================="

exit $EXIT_SUCCESS
