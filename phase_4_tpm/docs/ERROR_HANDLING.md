# TPM Error Handling Implementation

This document describes the comprehensive error handling implementation for TPM attestation in the SPIRE integration.

## Overview

The error handling implementation addresses two critical requirements:
1. **TPM Device Error Handling (Requirement 1.5)**: Handle missing or inaccessible TPM devices with descriptive error messages and fail-fast behavior
2. **PCR Mismatch Error Handling (Requirement 2.4)**: Log detailed PCR mismatch information and provide debugging guidance

## Components

### 1. SPIRE Agent Startup with TPM Error Handling

**File**: `start_spire_agent_tpm.sh`

**Purpose**: Provides fail-fast behavior for SPIRE Agent startup when TPM attestation is configured.

**Features**:
- Pre-flight checks for TPM device presence and accessibility
- Detailed error messages with troubleshooting hints
- Automatic fallback from `/dev/tpmrm0` to `/dev/tpm0`
- Permission validation (read/write access)
- TPM functionality verification using `tpm2_getcap`
- Process monitoring during startup
- Socket creation verification
- Health check validation

**Exit Codes**:
- `0`: Success - Agent started successfully
- `1`: TPM device not found
- `2`: TPM device not accessible (permission denied)
- `3`: TPM configuration invalid
- `4`: Agent startup failed

**Error Scenarios Handled**:

#### TPM Device Not Found
```
ERROR: TPM device not found at /dev/tpmrm0 or /dev/tpm0

TROUBLESHOOTING HINTS:
  1. Verify TPM is enabled in BIOS/UEFI settings
  2. Check if TPM kernel modules are loaded: lsmod | grep tpm
  3. Check if tpm2-abrmd service is running: systemctl status tpm2-abrmd
  4. Try starting tpm2-abrmd service: sudo systemctl start tpm2-abrmd
  5. Check dmesg for TPM-related errors: dmesg | grep -i tpm
```

#### TPM Device Not Accessible
```
ERROR: TPM device /dev/tpmrm0 is not readable (permission denied)

Current permissions:
crw-rw---- 1 tss tss 10, 224 Nov 27 10:00 /dev/tpmrm0

TROUBLESHOOTING HINTS:
  1. Check device ownership and permissions: ls -la /dev/tpmrm0
  2. Add current user to 'tss' group: sudo usermod -a -G tss $USER
  3. Run SPIRE Agent as root or with appropriate privileges: sudo ./start_spire_agent_tpm.sh
  4. Check if tpm2-abrmd is running with correct permissions
```

#### TPM Device Not Functional
```
ERROR: TPM device exists but is not functional

TROUBLESHOOTING HINTS:
  1. Check if TPM is properly initialized: tpm2_getcap properties-fixed
  2. Check if tpm2-abrmd service is running: systemctl status tpm2-abrmd
  3. Try restarting tpm2-abrmd service: sudo systemctl restart tpm2-abrmd
  4. Check dmesg for TPM errors: dmesg | grep -i tpm
  5. Try clearing TPM (WARNING: This will erase TPM data): tpm2_clear
```

**Usage**:
```bash
# Start agent with default configuration
sudo ./start_spire_agent_tpm.sh

# Start agent with custom configuration
sudo ./start_spire_agent_tpm.sh --config /path/to/agent.conf

# Start agent with join token
sudo ./start_spire_agent_tpm.sh --join-token <token>
```

### 2. PCR Validation and Mismatch Detection

**File**: `validate_pcr_match.sh`

**Purpose**: Validate TPM PCR values against registered selectors and provide detailed error messages for mismatches.

**Features**:
- Retrieves workload entry from SPIRE Server
- Extracts TPM PCR selectors from entry
- Reads current TPM PCR values
- Compares expected vs actual PCR values
- Provides detailed mismatch information
- Suggests resolution steps

**Exit Codes**:
- `0`: Success - All PCR values match
- `1`: PCR mismatch detected
- `2`: Invalid arguments or configuration
- `3`: TPM device not accessible

**Error Scenarios Handled**:

#### PCR Mismatch Detected
```
ERROR: PCR MISMATCH DETECTED
==========================================

One or more PCR values do not match the registered selectors.
This indicates that the system state has changed since registration.

Mismatch Details:
PCR 0:
  Expected: a3f5d8c2e1b4567890abcdef1234567890abcdef1234567890abcdef12345678
  Actual:   b7e2c9f1a8d3456789bcdef01234567890abcdef1234567890abcdef12345678

SVID REQUEST WILL BE DENIED

Possible Causes:
  1. System firmware or BIOS updates
  2. Bootloader changes (GRUB, systemd-boot)
  3. Kernel or initramfs updates
  4. Secure Boot configuration changes
  5. TPM has been cleared or reset

Resolution Steps:
  1. If changes are legitimate, update workload registration:
     - Read current PCR values: tpm2_pcrread sha256
     - Delete old registration: sudo /opt/spire/bin/spire-server entry delete -spiffeID <id>
     - Register with new PCR values: ./register_workload_tpm.sh --spiffe-id <id> --pcr-index 0 --pcr-hash <new_hash>

  2. If changes are unexpected, investigate potential security issues:
     - Review system logs: journalctl -xe
     - Check for unauthorized firmware updates
     - Verify system integrity

  3. To view all current PCR values:
     tpm2_pcrread sha256
```

**Usage**:
```bash
# Validate PCR values for a workload
sudo ./validate_pcr_match.sh --spiffe-id spiffe://example.org/k8s-workload

# Validate with verbose output
sudo ./validate_pcr_match.sh --spiffe-id spiffe://example.org/k8s-workload --verbose
```

### 3. Enhanced Workload Registration

**File**: `register_workload_tpm.sh` (enhanced)

**New Features**:
- PCR accessibility validation before registration
- Detailed warning about PCR mismatch scenarios
- Guidance on resolving PCR mismatches

**New Functions**:

#### `validate_pcr_values_accessible()`
Validates that TPM PCR values can be read before registration:
```bash
validate_pcr_values_accessible() {
    local pcr_index="$1"
    
    if ! command -v tpm2_pcrread &> /dev/null; then
        # Warn but don't fail
        return 0
    fi
    
    if ! tpm2_pcrread "sha256:${pcr_index}" > /dev/null 2>&1; then
        echo "ERROR: Cannot read PCR ${pcr_index} from TPM"
        return 1
    fi
    
    return 0
}
```

#### `warn_about_pcr_mismatch()`
Provides comprehensive warning about PCR mismatch handling:
```bash
warn_about_pcr_mismatch() {
    local pcr_index="$1"
    local pcr_hash="$2"
    
    echo "IMPORTANT: PCR Mismatch Handling"
    echo "If the current PCR value does NOT match the registered hash,"
    echo "SPIRE will DENY SVID requests with detailed error information."
    echo ""
    echo "Common causes of PCR mismatches:"
    echo "  1. System firmware or BIOS updates"
    echo "  2. Bootloader changes"
    echo "  3. Kernel or initramfs updates"
    echo "  ..."
}
```

### 4. Python Application Error Handling

**File**: `mtls_demo.py` (enhanced)

**Enhanced Features**:
- Detects PCR mismatch errors in SVID fetch failures
- Provides detailed troubleshooting steps
- Guides users through resolution process

**Error Detection**:
```python
if result.returncode != 0:
    stderr_lower = result.stderr.lower()
    if "pcr" in stderr_lower or "mismatch" in stderr_lower or "permission denied" in stderr_lower:
        # Display detailed PCR mismatch troubleshooting
        print("TPM PCR MISMATCH DETECTED")
        print("Troubleshooting steps...")
```

**Error Output Example**:
```
❌ Error fetching SVID from SPIRE Agent
Return code: 1

============================================================
   TPM PCR MISMATCH DETECTED
============================================================

The SPIRE Agent denied the SVID request due to a PCR mismatch.
This indicates that the system's TPM measurements have changed
since the workload was registered.

Error details:
[SPIRE error message]

============================================================
TROUBLESHOOTING STEPS:
============================================================

1. Check current TPM PCR values:
   tpm2_pcrread sha256

2. View workload registration:
   sudo /opt/spire/bin/spire-server entry show

3. Validate PCR match:
   sudo ./validate_pcr_match.sh --spiffe-id <your-spiffe-id>

4. If system changes are legitimate, update registration:
   [detailed steps]

5. Common causes of PCR changes:
   - Firmware or BIOS updates
   - Bootloader changes
   - Kernel or initramfs updates
   - Secure Boot configuration changes
   - TPM has been cleared or reset
```

## Error Handling Flow

### TPM Device Error Flow

```
┌─────────────────────────────────────┐
│  Start SPIRE Agent                  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Check TPM Configuration            │
│  - Is TPM node attestor configured? │
└──────────────┬──────────────────────┘
               │
               ▼
         ┌─────┴─────┐
         │ TPM       │
         │ Enabled?  │
         └─────┬─────┘
               │
        ┌──────┴──────┐
        │             │
       Yes           No
        │             │
        ▼             ▼
┌───────────────┐  ┌──────────────────┐
│ Check TPM     │  │ Start Agent      │
│ Device Exists │  │ (No TPM checks)  │
└───────┬───────┘  └──────────────────┘
        │
        ▼
   ┌────┴────┐
   │ Exists? │
   └────┬────┘
        │
   ┌────┴────┐
   │         │
  Yes       No
   │         │
   │         ▼
   │    ┌─────────────────────────┐
   │    │ ERROR: TPM Not Found    │
   │    │ Exit Code: 1            │
   │    │ Show troubleshooting    │
   │    └─────────────────────────┘
   │
   ▼
┌───────────────────────┐
│ Check TPM Accessible  │
│ - Read permission?    │
│ - Write permission?   │
└───────┬───────────────┘
        │
        ▼
   ┌────┴────┐
   │ Access? │
   └────┬────┘
        │
   ┌────┴────┐
   │         │
  Yes       No
   │         │
   │         ▼
   │    ┌─────────────────────────┐
   │    │ ERROR: Not Accessible   │
   │    │ Exit Code: 2            │
   │    │ Show permissions        │
   │    │ Show troubleshooting    │
   │    └─────────────────────────┘
   │
   ▼
┌───────────────────────┐
│ Check TPM Functional  │
│ - tpm2_getcap test    │
└───────┬───────────────┘
        │
        ▼
   ┌────┴────┐
   │ Works?  │
   └────┬────┘
        │
   ┌────┴────┐
   │         │
  Yes       No
   │         │
   │         ▼
   │    ┌─────────────────────────┐
   │    │ ERROR: Not Functional   │
   │    │ Exit Code: 2            │
   │    │ Show troubleshooting    │
   │    └─────────────────────────┘
   │
   ▼
┌───────────────────────┐
│ Start SPIRE Agent     │
│ Monitor startup       │
└───────┬───────────────┘
        │
        ▼
┌───────────────────────┐
│ SUCCESS               │
│ Exit Code: 0          │
└───────────────────────┘
```

### PCR Mismatch Error Flow

```
┌─────────────────────────────────────┐
│  Workload Requests SVID             │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  SPIRE Agent Performs Attestation   │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Check Workload Entry Selectors     │
│  - TPM PCR selectors present?       │
└──────────────┬──────────────────────┘
               │
               ▼
         ┌─────┴─────┐
         │ TPM PCR   │
         │ Selector? │
         └─────┬─────┘
               │
        ┌──────┴──────┐
        │             │
       Yes           No
        │             │
        ▼             ▼
┌───────────────┐  ┌──────────────────┐
│ Read Current  │  │ Use Other        │
│ TPM PCR Value │  │ Attestation      │
└───────┬───────┘  └──────────────────┘
        │
        ▼
┌───────────────────────┐
│ Compare PCR Values    │
│ Expected vs Actual    │
└───────┬───────────────┘
        │
        ▼
   ┌────┴────┐
   │ Match?  │
   └────┬────┘
        │
   ┌────┴────┐
   │         │
  Yes       No
   │         │
   │         ▼
   │    ┌─────────────────────────────┐
   │    │ DENY SVID Request           │
   │    │ Error: PERMISSION_DENIED    │
   │    │                             │
   │    │ Log Details:                │
   │    │ - PCR Index: X              │
   │    │ - Expected: <hash>          │
   │    │ - Actual: <hash>            │
   │    │                             │
   │    │ Return to Workload          │
   │    └──────────┬──────────────────┘
   │               │
   │               ▼
   │    ┌─────────────────────────────┐
   │    │ Workload Receives Error     │
   │    │ - Detect PCR mismatch       │
   │    │ - Display troubleshooting   │
   │    │ - Show resolution steps     │
   │    └─────────────────────────────┘
   │
   ▼
┌───────────────────────┐
│ Issue SVID            │
│ SUCCESS               │
└───────────────────────┘
```

## Testing Error Handling

### Test TPM Device Errors

1. **Test TPM Not Found**:
   ```bash
   # Temporarily hide TPM device
   sudo mv /dev/tpmrm0 /dev/tpmrm0.backup
   sudo ./start_spire_agent_tpm.sh
   # Should exit with code 1 and show troubleshooting hints
   sudo mv /dev/tpmrm0.backup /dev/tpmrm0
   ```

2. **Test TPM Not Accessible**:
   ```bash
   # Change permissions
   sudo chmod 000 /dev/tpmrm0
   sudo ./start_spire_agent_tpm.sh
   # Should exit with code 2 and show permission hints
   sudo chmod 666 /dev/tpmrm0
   ```

3. **Test TPM Not Functional**:
   ```bash
   # Stop tpm2-abrmd service
   sudo systemctl stop tpm2-abrmd
   sudo ./start_spire_agent_tpm.sh
   # Should exit with code 2 and show service hints
   sudo systemctl start tpm2-abrmd
   ```

### Test PCR Mismatch Errors

1. **Register with Current PCR**:
   ```bash
   # Read current PCR 0 value
   PCR_VALUE=$(tpm2_pcrread sha256:0 | grep "0 :" | awk '{print $3}')
   
   # Register workload
   sudo ./register_workload_tpm.sh \
     --spiffe-id spiffe://example.org/test-workload \
     --pcr-index 0 \
     --pcr-hash $PCR_VALUE
   ```

2. **Simulate PCR Change**:
   ```bash
   # Update registration with incorrect PCR value
   sudo /opt/spire/bin/spire-server entry delete \
     -spiffeID spiffe://example.org/test-workload
   
   sudo ./register_workload_tpm.sh \
     --spiffe-id spiffe://example.org/test-workload \
     --pcr-index 0 \
     --pcr-hash "0000000000000000000000000000000000000000000000000000000000000000"
   ```

3. **Validate Mismatch Detection**:
   ```bash
   # Should show detailed mismatch information
   sudo ./validate_pcr_match.sh \
     --spiffe-id spiffe://example.org/test-workload
   ```

4. **Test Application Error Handling**:
   ```bash
   # Deploy application with mismatched PCR
   # Application should detect and display PCR mismatch troubleshooting
   kubectl logs <pod-name>
   ```

## Best Practices

### For Operators

1. **Always use the enhanced startup script** (`start_spire_agent_tpm.sh`) instead of starting the agent directly
2. **Validate PCR values** before and after system updates using `validate_pcr_match.sh`
3. **Monitor agent logs** for TPM-related errors during startup
4. **Document PCR values** used in registrations for audit purposes
5. **Test error scenarios** in non-production environments first

### For Developers

1. **Handle SVID fetch failures gracefully** with detailed error messages
2. **Check for PCR mismatch indicators** in error responses
3. **Provide clear resolution steps** to users when errors occur
4. **Log error details** for debugging and audit purposes
5. **Implement retry logic** with exponential backoff for transient errors

### For Security Teams

1. **Investigate unexpected PCR changes** as potential security incidents
2. **Maintain audit logs** of PCR value changes and registration updates
3. **Establish change management** processes for system updates that affect PCR values
4. **Monitor for repeated PCR mismatches** which may indicate attacks
5. **Review error logs regularly** for patterns or anomalies

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue: "TPM device not found"
**Cause**: TPM is disabled in BIOS or kernel modules not loaded
**Solution**:
1. Enable TPM in BIOS/UEFI settings
2. Check kernel modules: `lsmod | grep tpm`
3. Load modules if needed: `sudo modprobe tpm_tis`

#### Issue: "TPM device not accessible"
**Cause**: Insufficient permissions
**Solution**:
1. Add user to tss group: `sudo usermod -a -G tss $USER`
2. Or run as root: `sudo ./start_spire_agent_tpm.sh`

#### Issue: "PCR mismatch detected"
**Cause**: System state changed since registration
**Solution**:
1. Verify change is legitimate
2. Read new PCR values: `tpm2_pcrread sha256`
3. Update registration with new values

#### Issue: "Agent starts but TPM attestation not working"
**Cause**: Configuration issue or TPM not functional
**Solution**:
1. Check agent logs: `tail -100 /opt/spire/agent.log`
2. Verify TPM functionality: `tpm2_getcap properties-fixed`
3. Check tpm2-abrmd service: `systemctl status tpm2-abrmd`

## References

- **Requirements**: See `.kiro/specs/tpm-spire-integration/requirements.md`
  - Requirement 1.5: TPM device error handling
  - Requirement 2.4: PCR mismatch error handling
- **Design**: See `.kiro/specs/tpm-spire-integration/design.md`
  - Error Handling section
- **SPIRE Documentation**: https://spiffe.io/docs/latest/spire/
- **TPM 2.0 Specification**: https://trustedcomputinggroup.org/resource/tpm-library-specification/
