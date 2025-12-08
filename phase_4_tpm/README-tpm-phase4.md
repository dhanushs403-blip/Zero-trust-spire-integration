# Phase 4: TPM-Integrated SPIRE mTLS Demonstration

## Overview

Phase 4 extends the Kubernetes-based SPIRE mTLS demonstration (Phase 3) with Trusted Platform Module (TPM) 2.0 attestation capabilities. This integration replaces software-based node attestation with hardware-rooted cryptographic attestation, providing stronger security guarantees for workload identity.

The system leverages TPM hardware on the host machine for both node attestation (SPIRE Agent to SPIRE Server) and optionally for workload attestation (application to SPIRE Agent). The Python mTLS demonstration application fetches TPM-attested SVIDs and establishes mutual TLS connections with hardware-backed certificates.

## What's New in Phase 4

### Hardware-Backed Security
- **TPM Node Attestation**: SPIRE Agent identity is cryptographically bound to TPM hardware
- **Endorsement Key (EK)**: Unique hardware identifier burned into TPM during manufacturing
- **Attestation Key (AK)**: TPM-generated key certified by EK for attestation operations
- **Platform Configuration Registers (PCRs)**: Hardware-protected measurements of system state

### Enhanced Trust Model
- Agent identity rooted in hardware rather than software tokens
- Cryptographic proof of platform integrity through PCR measurements
- Protection against agent impersonation and identity theft
- Stronger guarantees for workload identity issuance

### Backward Compatibility
- Maintains support for Docker label-based workload attestation
- Allows gradual migration from Phase 3 to Phase 4
- Workloads can use both TPM and Docker selectors simultaneously

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│         Remote TPM-Enabled Machine (Ubuntu 22.04)               │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    TPM 2.0 Hardware                        │ │
│  │  - Endorsement Key (EK) - Factory provisioned              │ │
│  │  - Attestation Key (AK) - Generated on demand              │ │
│  │  - PCR Registers - Platform measurements                   │ │
│  └────────────────┬───────────────────────────────────────────┘ │
│                   │ /dev/tpm0 or /dev/tpmrm0                    │
│  ┌────────────────▼───────────────────────────────────────────┐ │
│  │              SPIRE Server                                  │ │
│  │  - TPM Node Attestor Plugin (server-side)                  │ │
│  │  - Validates AK certificates against EK                    │ │
│  │  - Issues agent SPIFFE ID: spiffe://example.org/agent/tpm  │ │
│  └────────────────┬───────────────────────────────────────────┘ │
│                   │                                             │
│  ┌────────────────▼───────────────────────────────────────────┐ │
│  │              SPIRE Agent                                   │ │
│  │  - TPM Node Attestor Plugin (agent-side)                   │ │
│  │  - Generates/retrieves AK from TPM                         │ │
│  │  - Docker Workload Attestor (backward compat)              │ │
│  │  - Socket: /tmp/spire-agent/public/api.sock                │ │
│  └────────────────┬───────────────────────────────────────────┘ │
│                   │                                             │
│  ┌────────────────▼───────────────────────────────────────────┐ │
│  │         Minikube Kubernetes Cluster                        │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │         Pod: mtls-app-xxxxx                          │  │ │
│  │  │                                                      │  │ │
│  │  │  Volumes:                                            │  │ │
│  │  │  - /tmp/spire-agent/public/api.sock                  │  │ │
│  │  │  - /opt/spire/bin/spire-agent                        │  │ │
│  │  │                                                      │  │ │
│  │  │  ┌────────────────────────────────────────────────┐  │  │ │
│  │  │  │  Python mTLS Application                       │  │  │ │
│  │  │  │  1. Call SPIRE Agent Workload API              │  │  │ │
│  │  │  │  2. Agent performs TPM attestation             │  │  │ │
│  │  │  │  3. Receive TPM-attested SVID                  │  │  │ │
│  │  │  │  4. Establish mTLS with hardware-backed certs  │  │  │ │
│  │  │  └────────────────────────────────────────────────┘  │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### TPM Attestation Flow

1. **Node Attestation (Agent → Server)**:
   - SPIRE Agent reads TPM device (/dev/tpm0 or /dev/tpmrm0)
   - Agent generates or retrieves Attestation Key (AK) from TPM
   - Agent sends AK certificate and EK public key to SPIRE Server
   - Server validates AK certificate chain against EK
   - Server issues agent SPIFFE ID: `spiffe://example.org/spire/agent/tpm/<hash>`

2. **Workload Registration**:
   - Administrator registers workload with TPM selectors (optional) or Docker selectors
   - Example TPM selector: `tpm:pcr:0:<sha256-hash>`
   - Example Docker selector: `docker:label:io.kubernetes.container.name:mtls-app`
   - Registration stored in SPIRE Server datastore

3. **Workload Attestation (Application → Agent)**:
   - Python application calls SPIRE Agent Workload API
   - Agent identifies workload via Docker labels (Kubernetes pod)
   - Agent optionally validates TPM PCR values if TPM selectors are configured
   - Agent issues SVID with SPIFFE ID: `spiffe://example.org/k8s-workload`

4. **mTLS Connection**:
   - Application loads TPM-attested SVID certificates
   - Server and client perform mutual TLS handshake
   - Both parties verify peer certificates against trust bundle

## Prerequisites

### Hardware Requirements
- **TPM 2.0 Device**: Physical TPM chip or firmware TPM (fTPM)
  - Check in BIOS/UEFI: Look for "TPM", "Security Chip", or "Platform Trust Technology"
  - Enable TPM if disabled
  - Clear TPM if previously used (optional, for clean state)

### Software Requirements
- Ubuntu 22.04 LTS (or compatible Linux distribution)
- Root/sudo access
- SPIRE Server and Agent binaries installed at `/opt/spire`
- Docker installed and running
- Kubernetes (Minikube with `--driver=none`)
- Internet connection for package installation

### TPM Tools
- `tpm2-tools`: Command-line utilities for TPM operations
- `tpm2-abrmd`: TPM2 Access Broker & Resource Manager Daemon
- These will be installed automatically by the setup script

## Setup Instructions

### Step 1: Verify TPM Device

Before proceeding, verify that your system has a TPM device:

```bash
# Check for TPM device
ls -la /dev/tpm*

# Expected output:
# crw-rw---- 1 tss tss 10, 224 Nov 27 10:00 /dev/tpm0
# crw-rw---- 1 tss tss 10, 225 Nov 27 10:00 /dev/tpmrm0
```

If no TPM device is found:
1. Enter BIOS/UEFI settings (usually F2, F10, or Del during boot)
2. Navigate to Security settings
3. Enable TPM/Security Chip/Platform Trust Technology
4. Save and reboot

Run the TPM detection script for detailed diagnostics:

```bash
cd phase_4_tpm
chmod +x detect_tpm.sh
sudo ./detect_tpm.sh
```

**Expected Output:**
```
=========================================
TPM Device Detection and Verification
=========================================

INFO: Checking for TPM device...
SUCCESS: Found TPM resource manager device: /dev/tpmrm0

INFO: Checking TPM device accessibility...
SUCCESS: TPM device /dev/tpmrm0 is accessible

INFO: Checking for tpm2-tools...
SUCCESS: tpm2-tools is installed

INFO: Checking TPM capabilities...
SUCCESS: TPM capabilities check passed
INFO: TPM Version Information:
  TPM2_PT_FAMILY_INDICATOR: 2.0
  TPM2_PT_MANUFACTURER: ...
  TPM2_PT_VENDOR_STRING: ...

INFO: Reading TPM PCR values...
SUCCESS: PCR values read successfully
INFO: PCR Values (SHA256 bank):
  sha256:
    0 : 0x...
    1 : 0x...
    ...

=========================================
SUCCESS: TPM device verification completed successfully
TPM Device: /dev/tpmrm0
=========================================
```

### Step 2: Run Automated TPM Setup

The setup script automates TPM integration with SPIRE:

```bash
cd phase_4_tpm
chmod +x setup_tpm.sh
sudo ./setup_tpm.sh
```

**What the script does:**
1. Checks for TPM device presence and accessibility
2. Installs `tpm2-tools` and `tpm2-abrmd` if missing
3. Backs up existing SPIRE configuration files
4. Updates SPIRE Server configuration with TPM node attestor
5. Updates SPIRE Agent configuration with TPM node attestor and device path
6. Verifies configuration updates

**Expected Output:**
```
=========================================
TPM Setup for SPIRE Integration
=========================================

INFO: Checking for TPM device...
SUCCESS: Found TPM resource manager device: /dev/tpmrm0

INFO: Checking TPM device accessibility...
SUCCESS: TPM device /dev/tpmrm0 is accessible

INFO: Checking for tpm2-tools and tpm2-abrmd...
SUCCESS: tpm2-tools is already installed
SUCCESS: tpm2-abrmd service is running

INFO: Backing up existing SPIRE configuration files...
SUCCESS: Created backup directory: /opt/spire/conf/backup_20241127_100000
SUCCESS: Backed up server configuration
SUCCESS: Backed up agent configuration

INFO: Updating SPIRE Server configuration with TPM node attestor...
SUCCESS: Updated SPIRE Server configuration with TPM node attestor

INFO: Updating SPIRE Agent configuration with TPM node attestor...
SUCCESS: Updated SPIRE Agent configuration with TPM node attestor
INFO: TPM device path set to: /dev/tpmrm0

INFO: Verifying configuration updates...
SUCCESS: Server configuration contains TPM node attestor
SUCCESS: Agent configuration contains TPM node attestor
SUCCESS: Agent configuration has correct TPM device path

=========================================
SUCCESS: TPM setup completed successfully!

Summary:
  - TPM Device: /dev/tpmrm0
  - Backup Directory: /opt/spire/conf/backup_20241127_100000
  - Server Config: /opt/spire/conf/server/server.conf
  - Agent Config: /opt/spire/conf/agent/agent.conf

Next steps:
  1. Restart SPIRE Server: sudo systemctl restart spire-server
  2. Restart SPIRE Agent: sudo systemctl restart spire-agent
  3. Verify TPM attestation: ./verify_tpm.sh
=========================================
```

### Step 3: Build Docker Image

Build the mTLS demo Docker image:

```bash
cd phase_4_tpm
sudo docker build -t mtls-demo-image:latest .

# Verify the image exists
sudo docker images | grep mtls-demo-image
```

### Step 4: Setup Kubernetes Environment

Ensure Kubernetes is running with the correct configuration:

```bash
# If Minikube is not already running, set it up
sudo ./complete_k8s_setup.sh

# Verify node is ready
kubectl get nodes

# Expected output:
# NAME   STATUS   ROLES           AGE   VERSION
# vso    Ready    control-plane   10m   v1.28.3
```

### Step 5: Run the TPM-Integrated Demo

Execute the complete demo with TPM attestation:

```bash
cd phase_4_tpm
chmod +x run_tpm_demo.sh
sudo ./run_tpm_demo.sh
```

**What the script does:**
1. Checks prerequisites (TPM device, tools, binaries)
2. Stops existing SPIRE processes
3. Starts SPIRE Server with TPM configuration
4. Starts SPIRE Agent with TPM configuration
5. Verifies TPM node attestation succeeded
6. Sets up Kubernetes environment
7. Registers workload with TPM and Docker selectors
8. Deploys Kubernetes application
9. Monitors application logs
10. Verifies TPM attestation is active

**Expected Output:**
```
==========================================
   TPM-Integrated SPIRE Demo
==========================================

INFO: Step 1: Checking prerequisites...
SUCCESS: Found TPM resource manager: /dev/tpmrm0
SUCCESS: TPM device is accessible
SUCCESS: tpm2-tools is installed
SUCCESS: SPIRE binaries found
SUCCESS: kubectl is installed
SUCCESS: Docker is installed
SUCCESS: All prerequisites met

INFO: Step 2: Stopping existing SPIRE processes...
SUCCESS: Existing SPIRE processes stopped

INFO: Step 3: Starting SPIRE Server with TPM configuration...
SUCCESS: SPIRE Server started successfully (PID: 12345)

INFO: Step 4: Starting SPIRE Agent with TPM configuration...
INFO: Waiting for agent to complete TPM attestation...
SUCCESS: SPIRE Agent started successfully (PID: 12346)
SUCCESS: TPM attestation successful - agent registered with TPM parent ID
  SPIFFE ID: spiffe://example.org/spire/agent/tpm/...

INFO: Step 5: Setting up Kubernetes environment...
SUCCESS: Kubernetes environment ready

INFO: Step 6: Registering workload with SPIRE Server...
INFO: Reading current TPM PCR values...
INFO: PCR 0 value: a3f5d8c2e1b4...
INFO: Registering workload with TPM PCR selector and Docker selectors...
SUCCESS: Workload registered with TPM and Docker selectors
  Entry ID: ...

INFO: Step 7: Deploying Kubernetes application...
SUCCESS: Application deployed and running

INFO: Step 8: Monitoring application logs...
INFO: Pod name: mtls-app-7699857877-87mzx
==========================================
[SVID Fetch] Calling SPIRE Agent API...
✅ Successfully ran fetch command
✅ SVID files found on disk: svid.0.pem, svid.0.key, bundle.0.pem
[Server] Secure mTLS Server listening on 9999
[Client] ✅ VERIFIED SERVER IDENTITY
[Server] ✅ VERIFIED CLIENT IDENTITY
==========================================

INFO: Step 9: Verifying TPM attestation...
SUCCESS: Agent is using TPM attestation
SUCCESS: Workload entry includes TPM PCR selector
SUCCESS: TPM initialization messages found in agent logs

==========================================
SUCCESS: Demo Execution Complete!
==========================================
```

### Step 6: Verify TPM Attestation

Run the verification script to confirm TPM attestation is active:

```bash
cd phase_4_tpm
chmod +x verify_tpm.sh
sudo ./verify_tpm.sh
```

**Expected Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Checking SPIRE Agent Parent ID
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ SUCCESS: Successfully connected to SPIRE Agent API
✓ SUCCESS: Agent parent ID contains 'tpm' indicator
ℹ INFO: TPM attestation is active for this agent
ℹ INFO: Agent SPIFFE ID: spiffe://example.org/spire/agent/tpm/...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Checking SPIRE Server Entries for TPM Selectors
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ SUCCESS: Successfully queried SPIRE Server entries
✓ SUCCESS: Found workload entries with TPM PCR selectors
ℹ INFO: Number of TPM selector entries: 1
ℹ INFO: Sample TPM selectors:
  tpm:pcr:0:a3f5d8c2e1b4...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TPM Attestation Status Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Verification Summary:
  ✓ Checks Passed:  8
  ✗ Checks Failed:  0
  ⚠ Warnings:       0

✓ SUCCESS: TPM ATTESTATION IS ACTIVE

ℹ INFO: TPM attestation is properly configured and functioning
ℹ INFO: The SPIRE Agent is using TPM for node attestation
```

## SPIRE Configuration Details

### Server Configuration (server.conf.tpm)

The TPM-enabled server configuration includes:

```hcl
NodeAttestor "tpm" {
    plugin_data {
        # Hash algorithm for PCR banks (sha256 recommended)
        hash_algorithm = "sha256"
        
        # Optional: Path to CA certificates for EK validation
        # ca_path = "/opt/spire/conf/tpm-ca-certs"
    }
}
```

**Key Parameters:**
- `hash_algorithm`: Must match agent configuration (sha256 recommended)
- `ca_path`: Optional path to manufacturer CA certificates for EK validation

### Agent Configuration (agent.conf.tpm)

The TPM-enabled agent configuration includes:

```hcl
NodeAttestor "tpm" {
    plugin_data {
        # TPM device path - use resource manager for better isolation
        tpm_device_path = "/dev/tpmrm0"
        
        # Hash algorithm (must match server)
        hash_algorithm = "sha256"
        
        # Optional: Persistent handle for AK (will be generated if not exists)
        # ak_handle = "0x81010001"
    }
}
```

**Key Parameters:**
- `tpm_device_path`: Path to TPM device (`/dev/tpmrm0` preferred, `/dev/tpm0` fallback)
- `hash_algorithm`: Must match server configuration
- `ak_handle`: Optional persistent handle for Attestation Key (auto-generated if omitted)

### Workload Registration with TPM Selectors

Register workloads with TPM PCR selectors for hardware-backed attestation:

```bash
# Get current PCR value
PCR_VALUE=$(tpm2_pcrread sha256:0 | grep "0 :" | awk '{print $3}')

# Register workload with TPM selector
sudo /opt/spire/bin/spire-server entry create \
  -parentID spiffe://example.org/spire/agent/tpm/<hash> \
  -spiffeID spiffe://example.org/k8s-workload \
  -selector tpm:pcr:0:$PCR_VALUE \
  -selector docker:label:io.kubernetes.container.name:mtls-app
```

**TPM Selector Format:**
- `tpm:pcr:<index>:<hash>` where:
  - `<index>`: PCR register number (0-23)
  - `<hash>`: Expected SHA256 hash value

**Commonly Used PCRs:**
- PCR 0: BIOS/UEFI firmware
- PCR 1: BIOS/UEFI configuration
- PCR 2: Option ROM code
- PCR 3: Option ROM configuration
- PCR 4: Boot loader code
- PCR 5: Boot loader configuration
- PCR 7: Secure Boot state

## Testing and Verification

### Manual Testing Inside Pod

Access the running pod to inspect certificates and test mTLS:

```bash
# Get pod name
POD_NAME=$(kubectl get pods -l app=mtls-demo -o jsonpath="{.items[0].metadata.name}")

# Execute into the pod
sudo kubectl exec -it $POD_NAME -- /bin/bash

# Inside the pod:

# List certificate files
ls -la /app/*.pem /app/*.key

# View SVID certificate
cat /app/svid.0.pem

# View certificate details
openssl x509 -in /app/svid.0.pem -text -noout | grep -A 5 "Subject:"

# Test mTLS client
python3 mtls_demo.py client
```

### Verify SPIRE Agent Parent ID

Check that the agent is using TPM attestation:

```bash
# List agents
sudo /opt/spire/bin/spire-server agent list

# Expected output should show:
# SPIFFE ID: spiffe://example.org/spire/agent/tpm/<hash>
```

### Verify Workload Entries

Check registered workload entries:

```bash
# Show all entries
sudo /opt/spire/bin/spire-server entry show

# Look for TPM selectors:
# Selectors:
#   tpm:pcr:0:<hash>
#   docker:label:io.kubernetes.container.name:mtls-app
```

### Check SPIRE Agent Logs

Examine agent logs for TPM initialization:

```bash
# View agent logs
tail -50 /opt/spire/agent.log

# Look for TPM-related messages:
# - "tpm node attestor"
# - "TPM device"
# - "attestation key"
```

### Read Current TPM PCR Values

View current platform measurements:

```bash
# Read all PCR values
tpm2_pcrread sha256

# Read specific PCR
tpm2_pcrread sha256:0

# Get TPM capabilities
tpm2_getcap properties-fixed
```

## Deployment Commands for Remote Machine

### Transfer Files to Remote Machine

```bash
# From local machine, copy phase_4_tpm directory
scp -r phase_4_tpm user@remote-machine:/home/user/

# Or use rsync for incremental updates
rsync -avz --progress phase_4_tpm/ user@remote-machine:/home/user/phase_4_tpm/
```

### Execute on Remote Machine

```bash
# SSH into remote machine
ssh user@remote-machine

# Navigate to phase_4_tpm directory
cd /home/user/phase_4_tpm

# Run TPM detection
sudo ./detect_tpm.sh

# Run TPM setup
sudo ./setup_tpm.sh

# Build Docker image
sudo docker build -t mtls-demo-image:latest .

# Run complete demo
sudo ./run_tpm_demo.sh

# Verify TPM attestation
sudo ./verify_tpm.sh
```

## Troubleshooting

### Issue 1: TPM Device Not Found

**Symptoms:**
- `ls /dev/tpm*` shows no devices
- Error: "TPM device not found"

**Diagnosis:**
```bash
# Check if TPM is enabled in kernel
dmesg | grep -i tpm

# Check for TPM modules
lsmod | grep tpm

# Check systemd services
systemctl status tpm2-abrmd
```

**Resolution:**
1. Enter BIOS/UEFI and enable TPM/Security Chip
2. Reboot the system
3. Load TPM kernel modules:
   ```bash
   sudo modprobe tpm
   sudo modprobe tpm_tis
   ```
4. Start TPM resource manager:
   ```bash
   sudo systemctl start tpm2-abrmd
   sudo systemctl enable tpm2-abrmd
   ```

### Issue 2: TPM Device Permission Denied

**Symptoms:**
- TPM device exists but not accessible
- Error: "permission denied" when accessing /dev/tpm*

**Diagnosis:**
```bash
# Check device permissions
ls -la /dev/tpm*

# Check current user groups
groups

# Check TPM device ownership
stat /dev/tpmrm0
```

**Resolution:**
1. Add user to `tss` group:
   ```bash
   sudo usermod -a -G tss $USER
   ```
2. Log out and log back in for group changes to take effect
3. Or run scripts with sudo:
   ```bash
   sudo ./detect_tpm.sh
   sudo ./run_tpm_demo.sh
   ```

### Issue 3: TPM Attestation Fails

**Symptoms:**
- SPIRE Agent starts but doesn't show TPM in parent ID
- Agent logs show TPM-related errors

**Diagnosis:**
```bash
# Check agent logs
tail -100 /opt/spire/agent.log | grep -i tpm

# Check server logs
tail -100 /opt/spire/server.log | grep -i tpm

# Verify TPM is accessible
sudo tpm2_getcap properties-fixed

# Check agent configuration
grep -A 10 'NodeAttestor "tpm"' /opt/spire/conf/agent/agent.conf
```

**Resolution:**
1. Verify TPM device path in agent.conf matches actual device
2. Ensure hash_algorithm matches between server and agent
3. Clear TPM if previously used:
   ```bash
   sudo tpm2_clear
   ```
4. Restart SPIRE components:
   ```bash
   sudo pkill -f spire-agent
   sudo pkill -f spire-server
   sudo ./run_tpm_demo.sh
   ```

### Issue 4: PCR Mismatch During Workload Attestation

**Symptoms:**
- Workload cannot fetch SVID
- Error: "PCR mismatch" in agent logs

**Diagnosis:**
```bash
# Read current PCR values
tpm2_pcrread sha256

# Check registered PCR values
sudo /opt/spire/bin/spire-server entry show -spiffeID spiffe://example.org/k8s-workload

# Compare expected vs actual PCR values
```

**Resolution:**
1. PCR values change with system state (boot, updates, configuration)
2. Re-register workload with current PCR values:
   ```bash
   # Get current PCR value
   PCR_VALUE=$(tpm2_pcrread sha256:0 | grep "0 :" | awk '{print $3}')
   
   # Delete old entry
   sudo /opt/spire/bin/spire-server entry delete -spiffeID spiffe://example.org/k8s-workload
   
   # Create new entry with current PCR
   sudo /opt/spire/bin/spire-server entry create \
     -parentID <agent-id> \
     -spiffeID spiffe://example.org/k8s-workload \
     -selector tpm:pcr:0:$PCR_VALUE \
     -selector docker:label:io.kubernetes.container.name:mtls-app
   ```
3. For development, use Docker selectors only (no TPM selectors)
4. For production, document expected PCR values and update after system changes

### Issue 5: tpm2-tools Not Found

**Symptoms:**
- Command not found: tpm2_getcap, tpm2_pcrread
- Setup script fails to install packages

**Diagnosis:**
```bash
# Check if tpm2-tools is installed
which tpm2_getcap

# Check package manager
apt-cache policy tpm2-tools
```

**Resolution:**
1. Install manually:
   ```bash
   sudo apt-get update
   sudo apt-get install -y tpm2-tools tpm2-abrmd
   ```
2. Verify installation:
   ```bash
   tpm2_getcap --version
   ```
3. Start resource manager:
   ```bash
   sudo systemctl start tpm2-abrmd
   sudo systemctl enable tpm2-abrmd
   ```

### Issue 6: SPIRE Agent Fails to Start with TPM Configuration

**Symptoms:**
- Agent process exits immediately
- Error in logs about TPM initialization

**Diagnosis:**
```bash
# Check agent logs
tail -100 /opt/spire/agent.log

# Try starting agent in foreground for detailed errors
sudo /opt/spire/bin/spire-agent run -config /opt/spire/conf/agent/agent.conf

# Verify TPM device is accessible
sudo tpm2_getcap properties-fixed
```

**Resolution:**
1. Check TPM device path in configuration
2. Ensure TPM is not locked or in use by another process
3. Try clearing TPM:
   ```bash
   sudo tpm2_clear
   ```
4. Verify configuration syntax:
   ```bash
   # Check for syntax errors
   cat /opt/spire/conf/agent/agent.conf
   ```
5. Restore backup configuration if needed:
   ```bash
   sudo cp /opt/spire/conf/backup_*/agent.conf.backup /opt/spire/conf/agent/agent.conf
   ```

### Issue 7: Pod Cannot Fetch SVID

**Symptoms:**
- Pod logs show SVID fetch errors
- Certificate files not created

**Diagnosis:**
```bash
# Check pod logs
kubectl logs <pod-name>

# Check SPIRE Agent socket
ls -la /tmp/spire-agent/public/api.sock

# Check workload registration
sudo /opt/spire/bin/spire-server entry show

# Exec into pod to debug
kubectl exec -it <pod-name> -- /bin/bash
ls -la /tmp/spire-agent/public/
```

**Resolution:**
1. Verify SPIRE Agent is running and socket exists
2. Check workload is registered with correct selectors
3. Verify pod labels match registration selectors
4. Check agent logs for attestation errors
5. Re-register workload if needed
6. Restart pod to retry SVID fetch

## Key Files

- `README-tpm-phase4.md` - This file
- `MIGRATION-from-phase3.md` - Migration guide from Phase 3
- `setup_tpm.sh` - Automated TPM setup script
- `verify_tpm.sh` - TPM attestation verification script
- `run_tpm_demo.sh` - Complete demo execution script
- `detect_tpm.sh` - TPM device detection and diagnostics
- `server.conf.tpm` - SPIRE Server configuration with TPM
- `agent.conf.tpm` - SPIRE Agent configuration with TPM
- `register_workload_tpm.sh` - Workload registration helper
- `mtls_demo.py` - Python mTLS demonstration application
- `mtls-app.yaml` - Kubernetes deployment manifest
- `Dockerfile` - Container image definition

## Security Considerations

### TPM Device Access Control
- Restrict TPM device permissions to SPIRE Agent user only
- Use `/dev/tpmrm0` (resource manager) for better isolation
- Run SPIRE Agent with minimal privileges
- Audit TPM access logs regularly

### Endorsement Key Privacy
- EK is a unique identifier that could be used for tracking
- Use Attestation Key (AK) for attestation instead of EK directly
- EK public key is shared, but private key never leaves TPM
- Consider using Privacy CA for EK certificate validation in production

### PCR Measurement Integrity
- PCR values change with system state (firmware, boot, configuration)
- Document expected PCR values for your environment
- Update workload registrations after system changes
- Use measured boot (UEFI Secure Boot + TPM) for stronger guarantees

### Certificate Rotation
- TPM-attested SVIDs have limited validity (1 hour default)
- Python application should automatically refresh SVIDs before expiration
- SPIRE Agent handles rotation transparently
- Monitor certificate expiration and renewal in logs

### Backward Compatibility
- Supporting both TPM and Docker attestation could weaken security
- Clearly document which attestation method is used for each workload
- Log attestation method used for each SVID issuance
- Provide migration path to TPM-only attestation
- Consider deprecating Docker-only attestation after migration period

## Performance Notes

### TPM Operation Latency
- AK generation: ~100-500ms (one-time on agent startup)
- PCR read: ~10-50ms per read
- Signing operations: ~50-200ms
- Use `/dev/tpmrm0` for better concurrency

### SVID Fetch Performance
- Additional 50-100ms per SVID fetch for PCR validation
- Negligible impact on mTLS handshake (certificates cached)
- SPIRE Agent caches SVIDs and refreshes proactively

### Kubernetes Pod Startup
- Additional 100-200ms for initial SVID fetch
- No impact on subsequent pod operations
- Use init containers to fetch SVID before main container starts

## Next Steps

1. **Multi-Pod Communication**: Deploy client and server pods for pod-to-pod mTLS
2. **SVID Rotation**: Implement automatic certificate rotation for long-running pods
3. **Production Hardening**: Add monitoring, alerting, and proper error handling
4. **Measured Boot**: Integrate with UEFI Secure Boot for stronger platform integrity
5. **HSM Integration**: Extend to support Hardware Security Module attestation

## References

- [SPIRE Documentation](https://spiffe.io/docs/latest/spire/)
- [TPM 2.0 Specification](https://trustedcomputinggroup.org/resource/tpm-library-specification/)
- [SPIRE TPM Node Attestor](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_tpm.md)
- [tpm2-tools Documentation](https://github.com/tpm2-software/tpm2-tools)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [SPIFFE Specification](https://github.com/spiffe/spiffe/blob/main/standards/SPIFFE.md)
