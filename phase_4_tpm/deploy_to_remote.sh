#!/bin/bash

#############################################
# Remote TPM Deployment Script
#############################################
# Purpose: Deploy phase 4 TPM-integrated SPIRE system to remote TPM-enabled machine
# Requirements: 4.1, 4.2
#
# This script copies all necessary files from the local phase_4_tpm directory
# to a remote TPM-enabled Ubuntu machine and performs pre-deployment checks.
#
# Usage:
#   ./deploy_to_remote.sh <remote_user> <remote_host> [remote_path]
#
# Arguments:
#   remote_user  - Username on the remote machine
#   remote_host  - Hostname or IP address of the remote machine
#   remote_path  - Optional: Destination path on remote (default: ~/phase_4_tpm)
#
# Examples:
#   ./deploy_to_remote.sh ubuntu 192.168.1.100
#   ./deploy_to_remote.sh admin tpm-server.example.com /opt/spire-demo
#
# Prerequisites:
#   - SSH access to remote machine (password or key-based)
#   - rsync installed on both local and remote machines
#   - Remote machine has TPM 2.0 device
#
# Exit Codes:
#   0 - Success: Files deployed and TPM verified
#   1 - Failure: Invalid arguments, connection failed, or TPM not accessible
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
EXIT_INVALID_ARGS=1
EXIT_CONNECTION_FAILED=2
EXIT_TPM_CHECK_FAILED=3
EXIT_DEPLOYMENT_FAILED=4

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

# Function to display usage
print_usage() {
    cat << EOF
Usage: $0 <remote_user> <remote_host> [remote_path]

Deploy phase 4 TPM-integrated SPIRE system to remote TPM-enabled machine.

Arguments:
  remote_user  - Username on the remote machine
  remote_host  - Hostname or IP address of the remote machine
  remote_path  - Optional: Destination path on remote (default: ~/phase_4_tpm)

Examples:
  $0 ubuntu 192.168.1.100
  $0 admin tpm-server.example.com /opt/spire-demo

Prerequisites:
  - SSH access to remote machine
  - rsync installed on both machines
  - Remote machine has TPM 2.0 device

EOF
}

# Parse command line arguments
if [ $# -lt 2 ]; then
    print_error "Insufficient arguments"
    echo ""
    print_usage
    exit $EXIT_INVALID_ARGS
fi

REMOTE_USER="$1"
REMOTE_HOST="$2"
REMOTE_PATH="${3:-~/phase_4_tpm}"

# Validate arguments
if [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_HOST" ]; then
    print_error "Remote user and host cannot be empty"
    exit $EXIT_INVALID_ARGS
fi

echo "=========================================="
echo "   Remote TPM Deployment"
echo "=========================================="
echo ""
print_info "Deployment Configuration:"
echo "  Remote User: $REMOTE_USER"
echo "  Remote Host: $REMOTE_HOST"
echo "  Remote Path: $REMOTE_PATH"
echo ""

#############################################
# Step 1: Verify Local Files
#############################################
print_info "Step 1: Verifying local files..."

# Check if we're in the correct directory
if [ ! -f "mtls_demo.py" ] || [ ! -f "setup_tpm.sh" ]; then
    print_error "This script must be run from the phase_4_tpm directory"
    print_error "Current directory: $(pwd)"
    exit $EXIT_INVALID_ARGS
fi

# List of required files
REQUIRED_FILES=(
    "mtls_demo.py"
    "setup_tpm.sh"
    "detect_tpm.sh"
    "register_workload_tpm.sh"
    "server.conf.tpm"
    "agent.conf.tpm"
    "mtls-app.yaml"
    "Dockerfile"
    "setup_k8s.sh"
    "complete_k8s_setup.sh"
    "fix_cni_manual.sh"
)

# Check for required files
MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        MISSING_FILES+=("$file")
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    print_error "Missing required files:"
    for file in "${MISSING_FILES[@]}"; do
        echo "  - $file"
    done
    exit $EXIT_INVALID_ARGS
fi

print_success "All required files present"

#############################################
# Step 2: Test SSH Connection
#############################################
print_info "Step 2: Testing SSH connection to remote machine..."

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_USER@$REMOTE_HOST" "echo 'Connection successful'" 2>/dev/null; then
    print_warning "SSH key-based authentication failed, will prompt for password"
    
    # Try with password prompt
    if ! ssh -o ConnectTimeout=10 "$REMOTE_USER@$REMOTE_HOST" "echo 'Connection successful'" 2>/dev/null; then
        print_error "Cannot connect to $REMOTE_USER@$REMOTE_HOST"
        print_error "Please verify:"
        print_error "  1. Remote host is reachable"
        print_error "  2. SSH service is running on remote host"
        print_error "  3. Username and credentials are correct"
        exit $EXIT_CONNECTION_FAILED
    fi
fi

print_success "SSH connection established"

#############################################
# Step 3: Check Remote Prerequisites
#############################################
print_info "Step 3: Checking remote prerequisites..."

# Check if rsync is installed on remote
if ! ssh "$REMOTE_USER@$REMOTE_HOST" "command -v rsync >/dev/null 2>&1"; then
    print_warning "rsync not found on remote machine"
    print_info "Attempting to install rsync on remote machine..."
    
    if ssh "$REMOTE_USER@$REMOTE_HOST" "sudo apt-get update && sudo apt-get install -y rsync" 2>/dev/null; then
        print_success "rsync installed on remote machine"
    else
        print_error "Failed to install rsync on remote machine"
        print_error "Please install rsync manually: sudo apt-get install rsync"
        exit $EXIT_CONNECTION_FAILED
    fi
else
    print_success "rsync is available on remote machine"
fi

#############################################
# Step 4: Pre-Deployment TPM Check (Requirement 4.2)
#############################################
print_info "Step 4: Checking TPM device accessibility on remote machine..."

# Check for TPM device
TPM_CHECK_RESULT=$(ssh "$REMOTE_USER@$REMOTE_HOST" "
    if [ -e /dev/tpmrm0 ]; then
        echo 'FOUND:/dev/tpmrm0'
    elif [ -e /dev/tpm0 ]; then
        echo 'FOUND:/dev/tpm0'
    else
        echo 'NOT_FOUND'
    fi
" 2>/dev/null)

if [[ "$TPM_CHECK_RESULT" == "NOT_FOUND" ]]; then
    print_error "TPM device not found on remote machine"
    print_error "Expected device at /dev/tpmrm0 or /dev/tpm0"
    print_error ""
    print_error "Troubleshooting steps:"
    print_error "  1. Verify TPM is enabled in BIOS/UEFI settings"
    print_error "  2. Check if TPM kernel modules are loaded: lsmod | grep tpm"
    print_error "  3. Install tpm2-tools: sudo apt-get install tpm2-tools tpm2-abrmd"
    print_error "  4. Check dmesg for TPM-related messages: dmesg | grep -i tpm"
    exit $EXIT_TPM_CHECK_FAILED
elif [[ "$TPM_CHECK_RESULT" == FOUND:/dev/tpm0 ]]; then
    print_warning "TPM device found at /dev/tpm0 (character device)"
    print_info "Note: /dev/tpmrm0 (resource manager) is preferred but /dev/tpm0 will work"
    TPM_DEVICE="/dev/tpm0"
else
    print_success "TPM device found at /dev/tpmrm0 (resource manager)"
    TPM_DEVICE="/dev/tpmrm0"
fi

# Check TPM device accessibility
print_info "Checking TPM device permissions..."
TPM_ACCESSIBLE=$(ssh "$REMOTE_USER@$REMOTE_HOST" "
    if [ -r $TPM_DEVICE ] && [ -w $TPM_DEVICE ]; then
        echo 'ACCESSIBLE'
    else
        echo 'NOT_ACCESSIBLE'
    fi
" 2>/dev/null)

if [[ "$TPM_ACCESSIBLE" == "NOT_ACCESSIBLE" ]]; then
    print_warning "TPM device exists but may not be accessible to current user"
    print_info "Current permissions:"
    ssh "$REMOTE_USER@$REMOTE_HOST" "ls -la $TPM_DEVICE" 2>/dev/null || true
    print_info ""
    print_info "The setup script will handle TPM access configuration"
    print_info "You may need to run setup_tpm.sh with sudo privileges"
else
    print_success "TPM device is accessible"
fi

# Check if tpm2-tools is installed
print_info "Checking for tpm2-tools on remote machine..."
if ssh "$REMOTE_USER@$REMOTE_HOST" "command -v tpm2_getcap >/dev/null 2>&1"; then
    print_success "tpm2-tools is installed"
    
    # Try to read TPM capabilities
    print_info "Testing TPM functionality..."
    if ssh "$REMOTE_USER@$REMOTE_HOST" "tpm2_getcap properties-fixed >/dev/null 2>&1"; then
        print_success "TPM is functional and responding"
    else
        print_warning "TPM device exists but may not be fully functional"
        print_info "The setup script will verify TPM functionality"
    fi
else
    print_warning "tpm2-tools not installed on remote machine"
    print_info "The setup script will install tpm2-tools automatically"
fi

#############################################
# Step 5: Create Remote Directory
#############################################
print_info "Step 5: Creating remote directory..."

if ssh "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_PATH"; then
    print_success "Remote directory created: $REMOTE_PATH"
else
    print_error "Failed to create remote directory: $REMOTE_PATH"
    exit $EXIT_DEPLOYMENT_FAILED
fi

#############################################
# Step 6: Copy Files to Remote Machine (Requirement 4.1)
#############################################
print_info "Step 6: Copying files to remote machine..."

# Use rsync for efficient file transfer
print_info "Using rsync to transfer files..."

# Exclude unnecessary files
RSYNC_EXCLUDES=(
    "--exclude=__pycache__"
    "--exclude=*.pyc"
    "--exclude=.pytest_cache"
    "--exclude=.hypothesis"
    "--exclude=*.log"
    "--exclude=svid.*"
    "--exclude=bundle.*"
)

if rsync -avz --progress "${RSYNC_EXCLUDES[@]}" \
    ./ "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/"; then
    print_success "Files copied successfully"
else
    print_error "Failed to copy files to remote machine"
    exit $EXIT_DEPLOYMENT_FAILED
fi

#############################################
# Step 7: Set Execute Permissions on Scripts
#############################################
print_info "Step 7: Setting execute permissions on scripts..."

SCRIPTS=(
    "setup_tpm.sh"
    "detect_tpm.sh"
    "register_workload_tpm.sh"
    "run_tpm_demo.sh"
    "complete_k8s_setup.sh"
    "setup_k8s.sh"
    "fix_cni_manual.sh"
    "start_spire_agent.sh"
    "verify_tpm.sh"
)

for script in "${SCRIPTS[@]}"; do
    ssh "$REMOTE_USER@$REMOTE_HOST" "chmod +x $REMOTE_PATH/$script 2>/dev/null" || true
done

print_success "Execute permissions set on scripts"

#############################################
# Step 8: Verify Deployment
#############################################
print_info "Step 8: Verifying deployment..."

# Check if files were copied correctly
FILE_COUNT=$(ssh "$REMOTE_USER@$REMOTE_HOST" "find $REMOTE_PATH -type f | wc -l")
print_info "Files deployed: $FILE_COUNT"

# Verify key files exist
print_info "Verifying key files..."
VERIFICATION_FAILED=false

for file in "${REQUIRED_FILES[@]}"; do
    if ! ssh "$REMOTE_USER@$REMOTE_HOST" "[ -f $REMOTE_PATH/$file ]"; then
        print_error "Missing file on remote: $file"
        VERIFICATION_FAILED=true
    fi
done

if [ "$VERIFICATION_FAILED" = true ]; then
    print_error "Deployment verification failed"
    exit $EXIT_DEPLOYMENT_FAILED
fi

print_success "All key files verified on remote machine"

#############################################
# Step 9: Display Next Steps
#############################################
echo ""
echo "=========================================="
print_success "Deployment Complete!"
echo "=========================================="
echo ""
print_info "Files have been deployed to: $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"
echo ""
print_info "Next Steps:"
echo ""
echo "1. SSH into the remote machine:"
echo "   ssh $REMOTE_USER@$REMOTE_HOST"
echo ""
echo "2. Navigate to the deployment directory:"
echo "   cd $REMOTE_PATH"
echo ""
echo "3. Run the TPM detection script to verify TPM:"
echo "   ./detect_tpm.sh"
echo ""
echo "4. Run the setup script to configure SPIRE with TPM:"
echo "   sudo ./setup_tpm.sh"
echo ""
echo "5. Run the demo script to deploy and test the system:"
echo "   sudo ./run_tpm_demo.sh"
echo ""
print_info "For detailed instructions, see README-tpm-phase4.md"
echo ""
echo "=========================================="

exit $EXIT_SUCCESS
