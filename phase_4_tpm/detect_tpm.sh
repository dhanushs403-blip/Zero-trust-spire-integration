#!/bin/bash

# TPM Device Detection Script
# This script checks for TPM device presence, accessibility, and capabilities
# Requirements: 1.5, 4.2, 6.1, 7.4

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Exit codes
EXIT_SUCCESS=0
EXIT_TPM_NOT_FOUND=1
EXIT_TPM_NOT_ACCESSIBLE=2
EXIT_TPM_TOOLS_MISSING=3
EXIT_TPM_CAPABILITY_ERROR=4

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
    echo "INFO: $1"
}

# Function to check if TPM device exists
check_tpm_device() {
    print_info "Checking for TPM device..."
    
    if [ -e /dev/tpmrm0 ]; then
        TPM_DEVICE="/dev/tpmrm0"
        print_success "Found TPM resource manager device: $TPM_DEVICE"
        return 0
    elif [ -e /dev/tpm0 ]; then
        TPM_DEVICE="/dev/tpm0"
        print_warning "Found TPM character device: $TPM_DEVICE"
        print_info "Note: /dev/tpmrm0 (resource manager) is preferred for better isolation"
        return 0
    else
        print_error "TPM device not found at /dev/tpmrm0 or /dev/tpm0"
        print_error "HINT: Verify TPM is enabled in BIOS/UEFI settings"
        print_error "HINT: Check if tpm2-abrmd service is running: systemctl status tpm2-abrmd"
        return $EXIT_TPM_NOT_FOUND
    fi
}

# Function to check TPM device accessibility
check_tpm_accessibility() {
    print_info "Checking TPM device accessibility..."
    
    if [ ! -r "$TPM_DEVICE" ] || [ ! -w "$TPM_DEVICE" ]; then
        print_error "TPM device $TPM_DEVICE is not accessible (permission denied)"
        print_error "Current permissions:"
        ls -la "$TPM_DEVICE" >&2
        print_error "HINT: Ensure the current user has read/write access to the TPM device"
        print_error "HINT: You may need to add your user to the 'tss' group: sudo usermod -a -G tss \$USER"
        print_error "HINT: Or run this script with appropriate privileges"
        return $EXIT_TPM_NOT_ACCESSIBLE
    fi
    
    print_success "TPM device $TPM_DEVICE is accessible"
    return 0
}

# Function to check if tpm2-tools is installed
check_tpm_tools() {
    print_info "Checking for tpm2-tools..."
    
    if ! command -v tpm2_getcap &> /dev/null; then
        print_error "tpm2-tools not found"
        print_error "HINT: Install tpm2-tools: sudo apt-get install tpm2-tools"
        return $EXIT_TPM_TOOLS_MISSING
    fi
    
    if ! command -v tpm2_pcrread &> /dev/null; then
        print_error "tpm2_pcrread not found"
        print_error "HINT: Install tpm2-tools: sudo apt-get install tpm2-tools"
        return $EXIT_TPM_TOOLS_MISSING
    fi
    
    print_success "tpm2-tools is installed"
    return 0
}

# Function to check TPM capabilities
check_tpm_capabilities() {
    print_info "Checking TPM capabilities..."
    
    # Try to get TPM properties
    if ! tpm2_getcap properties-fixed > /dev/null 2>&1; then
        print_error "Failed to read TPM capabilities"
        print_error "HINT: Ensure TPM is properly initialized"
        print_error "HINT: Check if tpm2-abrmd service is running: systemctl status tpm2-abrmd"
        return $EXIT_TPM_CAPABILITY_ERROR
    fi
    
    print_success "TPM capabilities check passed"
    
    # Display TPM version information
    print_info "TPM Version Information:"
    tpm2_getcap properties-fixed | grep -E "TPM2_PT_FAMILY_INDICATOR|TPM2_PT_MANUFACTURER|TPM2_PT_VENDOR_STRING" || true
    
    return 0
}

# Function to read and display PCR values
read_pcr_values() {
    print_info "Reading TPM PCR values..."
    
    if ! tpm2_pcrread sha256 > /dev/null 2>&1; then
        print_error "Failed to read PCR values"
        print_error "HINT: Ensure TPM is accessible and properly configured"
        return $EXIT_TPM_CAPABILITY_ERROR
    fi
    
    print_success "PCR values read successfully"
    print_info "PCR Values (SHA256 bank):"
    tpm2_pcrread sha256
    
    return 0
}

# Main execution
main() {
    echo "========================================="
    echo "TPM Device Detection and Verification"
    echo "========================================="
    echo ""
    
    # Check for TPM device
    if ! check_tpm_device; then
        exit $EXIT_TPM_NOT_FOUND
    fi
    
    echo ""
    
    # Check TPM accessibility
    if ! check_tpm_accessibility; then
        exit $EXIT_TPM_NOT_ACCESSIBLE
    fi
    
    echo ""
    
    # Check for tpm2-tools
    if ! check_tpm_tools; then
        exit $EXIT_TPM_TOOLS_MISSING
    fi
    
    echo ""
    
    # Check TPM capabilities
    if ! check_tpm_capabilities; then
        exit $EXIT_TPM_CAPABILITY_ERROR
    fi
    
    echo ""
    
    # Read PCR values
    if ! read_pcr_values; then
        exit $EXIT_TPM_CAPABILITY_ERROR
    fi
    
    echo ""
    echo "========================================="
    print_success "TPM device verification completed successfully"
    echo "TPM Device: $TPM_DEVICE"
    echo "========================================="
    
    exit $EXIT_SUCCESS
}

# Run main function
main "$@"
