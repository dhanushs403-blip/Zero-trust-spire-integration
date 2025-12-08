#!/bin/bash

# TPM Setup Script for SPIRE Integration
# This script automates the setup of TPM attestation for SPIRE
# Requirements: 6.1, 6.2, 6.3, 6.4, 6.5

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration paths
SPIRE_SERVER_CONF="/opt/spire/conf/server/server.conf"
SPIRE_AGENT_CONF="/opt/spire/conf/agent/agent.conf"
BACKUP_DIR="/opt/spire/conf/backup_$(date +%Y%m%d_%H%M%S)"

# TPM device path (prefer resource manager)
TPM_DEVICE=""

# Exit codes
EXIT_SUCCESS=0
EXIT_TPM_NOT_FOUND=1
EXIT_TPM_NOT_ACCESSIBLE=2
EXIT_PACKAGE_INSTALL_FAILED=3
EXIT_BACKUP_FAILED=4
EXIT_CONFIG_UPDATE_FAILED=5

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

# Function to check if running with sufficient privileges
check_privileges() {
    if [ "$EUID" -ne 0 ]; then
        print_warning "This script may require root privileges for package installation"
        print_info "If package installation fails, please run with sudo"
    fi
}

# Function to check for TPM device (Requirement 6.1)
check_tpm_device() {
    print_info "Checking for TPM device presence..."
    
    if [ -e /dev/tpmrm0 ]; then
        TPM_DEVICE="/dev/tpmrm0"
        print_success "Found TPM resource manager device: $TPM_DEVICE"
        return 0
    elif [ -e /dev/tpm0 ]; then
        TPM_DEVICE="/dev/tpm0"
        print_warning "Found TPM character device: $TPM_DEVICE"
        print_info "Note: /dev/tpmrm0 is preferred but /dev/tpm0 will work"
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
    
    if [ ! -r "$TPM_DEVICE" ]; then
        print_error "TPM device $TPM_DEVICE is not readable"
        print_error "Current permissions:"
        ls -la "$TPM_DEVICE" >&2
        print_error "HINT: Ensure proper permissions are set on the TPM device"
        return $EXIT_TPM_NOT_ACCESSIBLE
    fi
    
    print_success "TPM device $TPM_DEVICE is accessible"
    return 0
}

# Function to install TPM tools (Requirement 6.2)
install_tpm_tools() {
    print_info "Checking for tpm2-tools and tpm2-abrmd..."
    
    local needs_install=false
    
    if ! command -v tpm2_getcap &> /dev/null; then
        print_warning "tpm2-tools not found, will install"
        needs_install=true
    else
        print_success "tpm2-tools is already installed"
    fi
    
    if ! systemctl is-active --quiet tpm2-abrmd 2>/dev/null; then
        if ! command -v tpm2-abrmd &> /dev/null; then
            print_warning "tpm2-abrmd not found, will install"
            needs_install=true
        fi
    else
        print_success "tpm2-abrmd service is running"
    fi
    
    if [ "$needs_install" = true ]; then
        print_info "Installing tpm2-tools and tpm2-abrmd..."
        
        if command -v apt-get &> /dev/null; then
            if ! apt-get update && apt-get install -y tpm2-tools tpm2-abrmd; then
                print_error "Failed to install TPM packages using apt-get"
                return $EXIT_PACKAGE_INSTALL_FAILED
            fi
        elif command -v yum &> /dev/null; then
            if ! yum install -y tpm2-tools tpm2-abrmd; then
                print_error "Failed to install TPM packages using yum"
                return $EXIT_PACKAGE_INSTALL_FAILED
            fi
        else
            print_error "No supported package manager found (apt-get or yum)"
            print_error "Please install tpm2-tools and tpm2-abrmd manually"
            return $EXIT_PACKAGE_INSTALL_FAILED
        fi
        
        print_success "TPM packages installed successfully"
        
        # Try to start tpm2-abrmd service
        if systemctl start tpm2-abrmd 2>/dev/null; then
            systemctl enable tpm2-abrmd 2>/dev/null || true
            print_success "tpm2-abrmd service started and enabled"
        else
            print_warning "Could not start tpm2-abrmd service automatically"
            print_info "You may need to start it manually: sudo systemctl start tpm2-abrmd"
        fi
    fi
    
    return 0
}

# Function to backup existing configuration files (Requirement 6.3)
backup_configurations() {
    print_info "Backing up existing SPIRE configuration files..."
    
    # Create backup directory
    if ! mkdir -p "$BACKUP_DIR"; then
        print_error "Failed to create backup directory: $BACKUP_DIR"
        return $EXIT_BACKUP_FAILED
    fi
    
    print_success "Created backup directory: $BACKUP_DIR"
    
    # Backup server configuration if it exists
    if [ -f "$SPIRE_SERVER_CONF" ]; then
        if cp "$SPIRE_SERVER_CONF" "$BACKUP_DIR/server.conf.backup"; then
            print_success "Backed up server configuration to $BACKUP_DIR/server.conf.backup"
        else
            print_error "Failed to backup server configuration"
            return $EXIT_BACKUP_FAILED
        fi
    else
        print_warning "Server configuration not found at $SPIRE_SERVER_CONF, skipping backup"
    fi
    
    # Backup agent configuration if it exists
    if [ -f "$SPIRE_AGENT_CONF" ]; then
        if cp "$SPIRE_AGENT_CONF" "$BACKUP_DIR/agent.conf.backup"; then
            print_success "Backed up agent configuration to $BACKUP_DIR/agent.conf.backup"
        else
            print_error "Failed to backup agent configuration"
            return $EXIT_BACKUP_FAILED
        fi
    else
        print_warning "Agent configuration not found at $SPIRE_AGENT_CONF, skipping backup"
    fi
    
    return 0
}

# Function to generate DevID certificates (Required for tpm_devid)
generate_devid_certs() {
    print_info "Generating DevID certificates for tpm_devid plugin..."
    
    local cert_dir="/opt/spire/conf/tpm"
    mkdir -p "$cert_dir"
    
    # Generate CA key and cert (Self-signed for demo)
    if [ ! -f "$cert_dir/devid-ca.key" ]; then
        openssl req -new -x509 -days 365 -nodes \
            -subj "/C=US/O=SPIRE/CN=DevID-CA" \
            -keyout "$cert_dir/devid-ca.key" \
            -out "$cert_dir/devid-ca.crt"
    fi
    
    # Generate DevID key and CSR
    if [ ! -f "$cert_dir/devid.key" ]; then
        openssl req -new -nodes \
            -subj "/C=US/O=SPIRE/CN=spire-agent-tpm" \
            -keyout "$cert_dir/devid.key" \
            -out "$cert_dir/devid.csr"
            
        # Sign DevID cert with CA
        openssl x509 -req -days 365 \
            -in "$cert_dir/devid.csr" \
            -signkey "$cert_dir/devid-ca.key" \
            -out "$cert_dir/devid.crt"
    fi
    
    print_success "DevID certificates generated in $cert_dir"
    return 0
}

# Function to update SPIRE Server configuration (Requirement 6.4)
update_server_config() {
    print_info "Updating SPIRE Server configuration with TPM node attestor..."
    
    if [ ! -f "$SPIRE_SERVER_CONF" ]; then
        print_error "Server configuration not found at $SPIRE_SERVER_CONF"
        print_error "Please ensure SPIRE Server is installed"
        return $EXIT_CONFIG_UPDATE_FAILED
    fi
    
    # Check if TPM node attestor already exists
    if grep -q 'NodeAttestor "tpm_devid"' "$SPIRE_SERVER_CONF"; then
        print_warning "TPM node attestor already configured in server.conf"
        return 0
    fi
    
    # Add TPM node attestor configuration
    cat >> "$SPIRE_SERVER_CONF" << 'EOF'

# TPM Node Attestor Plugin (tpm_devid)
NodeAttestor "tpm_devid" {
    plugin_cmd = "/opt/spire/bin/spire-server"
    plugin_data {
        # Path to the CA certificate that signed the DevID certificate
        devid_ca_path = "/opt/spire/conf/tpm/devid-ca.crt"
    }
}
EOF
    
    if [ $? -eq 0 ]; then
        print_success "Updated SPIRE Server configuration with TPM node attestor"
    else
        print_error "Failed to update SPIRE Server configuration"
        return $EXIT_CONFIG_UPDATE_FAILED
    fi
    
    return 0
}

# Function to update SPIRE Agent configuration (Requirement 6.5)
update_agent_config() {
    print_info "Updating SPIRE Agent configuration with TPM node attestor..."
    
    if [ ! -f "$SPIRE_AGENT_CONF" ]; then
        print_error "Agent configuration not found at $SPIRE_AGENT_CONF"
        print_error "Please ensure SPIRE Agent is installed"
        return $EXIT_CONFIG_UPDATE_FAILED
    fi
    
    # Check if TPM node attestor already exists
    if grep -q 'NodeAttestor "tpm_devid"' "$SPIRE_AGENT_CONF"; then
        print_warning "TPM node attestor already configured in agent.conf"
        return 0
    fi
    
    # Add TPM node attestor configuration with detected device path
    cat >> "$SPIRE_AGENT_CONF" << EOF

# TPM Node Attestor Plugin (tpm_devid)
NodeAttestor "tpm_devid" {
    plugin_cmd = "/opt/spire/bin/spire-agent"
    plugin_data {
        # TPM device path
        tpm_device_path = "$TPM_DEVICE"
        
        # DevID Certificate and Private Key
        devid_cert_path = "/opt/spire/conf/tpm/devid.crt"
        devid_priv_key_path = "/opt/spire/conf/tpm/devid.key"
    }
}
EOF
    
    if [ $? -eq 0 ]; then
        print_success "Updated SPIRE Agent configuration with TPM node attestor"
        print_info "TPM device path set to: $TPM_DEVICE"
    else
        print_error "Failed to update SPIRE Agent configuration"
        return $EXIT_CONFIG_UPDATE_FAILED
    fi
    
    return 0
}

# Function to verify configuration updates
verify_configuration() {
    print_info "Verifying configuration updates..."
    
    local verification_passed=true
    
    # Verify server config
    if [ -f "$SPIRE_SERVER_CONF" ]; then
        if grep -q 'NodeAttestor "tpm_devid"' "$SPIRE_SERVER_CONF"; then
            print_success "Server configuration contains TPM node attestor"
        else
            print_error "Server configuration missing TPM node attestor"
            verification_passed=false
        fi
    fi
    
    # Verify agent config
    if [ -f "$SPIRE_AGENT_CONF" ]; then
        if grep -q 'NodeAttestor "tpm_devid"' "$SPIRE_AGENT_CONF"; then
            print_success "Agent configuration contains TPM node attestor"
        else
            print_error "Agent configuration missing TPM node attestor"
            verification_passed=false
        fi
        
        if grep -q "tpm_device_path.*$TPM_DEVICE" "$SPIRE_AGENT_CONF"; then
            print_success "Agent configuration has correct TPM device path"
        else
            print_error "Agent configuration has incorrect TPM device path"
            verification_passed=false
        fi
    fi
    
    if [ "$verification_passed" = true ]; then
        return 0
    else
        return 1
    fi
}

# Main execution
main() {
    echo "========================================="
    echo "TPM Setup for SPIRE Integration"
    echo "========================================="
    echo ""
    
    check_privileges
    echo ""
    
    # Step 1: Check for TPM device (Requirement 6.1)
    if ! check_tpm_device; then
        exit $EXIT_TPM_NOT_FOUND
    fi
    echo ""
    
    # Step 2: Check TPM accessibility
    if ! check_tpm_accessibility; then
        exit $EXIT_TPM_NOT_ACCESSIBLE
    fi
    echo ""
    
    # Step 3: Install TPM tools if needed (Requirement 6.2)
    if ! install_tpm_tools; then
        exit $EXIT_PACKAGE_INSTALL_FAILED
    fi
    echo ""
    
    # Step 4: Backup existing configurations (Requirement 6.3)
    if ! backup_configurations; then
        exit $EXIT_BACKUP_FAILED
    fi
    echo ""
    
    # Step 5: Generate DevID certificates
    if ! generate_devid_certs; then
        print_error "Failed to generate DevID certificates"
        exit $EXIT_CONFIG_UPDATE_FAILED
    fi
    echo ""
    
    # Step 6: Update SPIRE Server configuration (Requirement 6.4)
    if ! update_server_config; then
        print_error "Failed to update server configuration"
        print_info "Configuration backup available at: $BACKUP_DIR"
        exit $EXIT_CONFIG_UPDATE_FAILED
    fi
    echo ""
    
    # Step 7: Update SPIRE Agent configuration (Requirement 6.5)
    if ! update_agent_config; then
        print_error "Failed to update agent configuration"
        print_info "Configuration backup available at: $BACKUP_DIR"
        exit $EXIT_CONFIG_UPDATE_FAILED
    fi
    echo ""
    
    # Step 8: Verify configuration updates
    if ! verify_configuration; then
        print_error "Configuration verification failed"
        print_info "Configuration backup available at: $BACKUP_DIR"
        exit $EXIT_CONFIG_UPDATE_FAILED
    fi
    echo ""
    
    echo "========================================="
    print_success "TPM setup completed successfully!"
    echo ""
    print_info "Summary:"
    echo "  - TPM Device: $TPM_DEVICE"
    echo "  - Backup Directory: $BACKUP_DIR"
    echo "  - Server Config: $SPIRE_SERVER_CONF"
    echo "  - Agent Config: $SPIRE_AGENT_CONF"
    echo "  - DevID Certs: /opt/spire/conf/tpm/"
    echo ""
    print_info "Next steps:"
    echo "  1. Restart SPIRE Server: sudo systemctl restart spire-server"
    echo "  2. Restart SPIRE Agent: sudo systemctl restart spire-agent"
    echo "  3. Verify TPM attestation: ./verify_tpm.sh"
    echo "========================================="
    
    exit $EXIT_SUCCESS
}

# Run main function
main "$@"
