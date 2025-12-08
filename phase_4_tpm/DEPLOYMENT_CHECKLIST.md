# Phase 4 TPM Deployment Checklist

## Pre-Deployment Verification

This folder has been cleaned and is ready for deployment to your remote TPM-enabled machine.

### ✅ Removed Files (Phase 3 artifacts no longer needed)
- README-docker-phase2.md
- README-k8s-phase3.md
- README-spire-setup.md
- RUNBOOK-k8s-spire.md
- run_k8s_demo.sh
- start_spire_agent.sh
- complete_k8s_setup.sh
- setup_k8s.sh
- fix_cni_manual.sh
- All __pycache__ directories
- All .pytest_cache directories
- All .hypothesis cache directories

### 📦 Files Ready for Deployment

#### Configuration Files
- `agent.conf.tpm` - SPIRE Agent configuration with TPM node attestor
- `server.conf.tpm` - SPIRE Server configuration with TPM node attestor
- `mtls-app.yaml` - Kubernetes deployment manifest
- `Dockerfile` - Container image definition

#### Scripts
- `setup_tpm.sh` - Automated TPM setup and configuration
- `detect_tpm.sh` - TPM device detection utility
- `start_spire_agent_tpm.sh` - Start SPIRE Agent with TPM attestation
- `register_workload_tpm.sh` - Register workloads with TPM selectors
- `validate_pcr_match.sh` - Validate PCR value matching
- `verify_tpm.sh` - Verify TPM attestation is active
- `run_tpm_demo.sh` - Run the complete TPM demo
- `deploy_to_remote.sh` - Deploy to remote machine

#### Application
- `mtls_demo.py` - Python mTLS application with TPM attestation support

#### Documentation
- `README-tpm-phase4.md` - Main documentation for Phase 4
- `MIGRATION-from-phase3.md` - Migration guide from Phase 3
- `docs/ERROR_HANDLING.md` - Error handling documentation
- `docs/PHASE4_STRUCTURE.md` - Phase 4 structure documentation

#### Tests
- `tests/test_tpm_setup.py` - Property-based tests for TPM setup
- `tests/test_mtls_demo.py` - Property-based tests for mTLS demo
- `tests/test_integration.py` - Integration tests

## Test Results

All tests passed successfully:
- **92 tests passed** (0 failures)
- Test execution time: ~107 seconds
- All property-based tests validated
- All integration tests validated

## Deployment Steps

1. **Transfer to Remote Machine**
   ```bash
   # From your local machine
   scp -r phase_4_tpm user@remote-machine:/path/to/destination/
   ```

2. **On Remote Machine - Verify TPM**
   ```bash
   cd phase_4_tpm
   chmod +x *.sh
   ./detect_tpm.sh
   ```

3. **On Remote Machine - Setup**
   ```bash
   ./setup_tpm.sh
   ```

4. **On Remote Machine - Run Demo**
   ```bash
   ./run_tpm_demo.sh
   ```

5. **On Remote Machine - Verify**
   ```bash
   ./verify_tpm.sh
   ```

## Prerequisites on Remote Machine

- Ubuntu 22.04 or later
- TPM 2.0 device (/dev/tpm0 or /dev/tpmrm0)
- Kubernetes (Minikube with --driver=none)
- SPIRE binaries installed
- Python 3.8+ with required packages
- Root or sudo access

## Verification Commands

After deployment, verify TPM attestation is working:

```bash
# Check SPIRE Agent parent ID (should contain "tpm")
/opt/spire/bin/spire-server agent list

# Check workload entries (should show TPM selectors)
/opt/spire/bin/spire-server entry show

# Check SPIRE Agent logs for TPM initialization
journalctl -u spire-agent | grep -i tpm

# Read current TPM PCR values
tpm2_pcrread

# Run verification script
./verify_tpm.sh
```

## Support

For issues or questions:
1. Check `README-tpm-phase4.md` for detailed documentation
2. Review `docs/ERROR_HANDLING.md` for common errors
3. Check `MIGRATION-from-phase3.md` for migration guidance

## Notes

- This folder is self-contained and ready for deployment
- All tests have been validated on the development machine
- Scripts will need execute permissions on the remote machine
- TPM device must be accessible before running setup
