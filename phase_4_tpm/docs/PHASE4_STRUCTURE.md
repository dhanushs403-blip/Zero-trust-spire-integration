# Phase 4 TPM Directory Structure

This directory contains the Phase 4 implementation with TPM attestation integration.

## Directory Layout

```
phase_4_tpm/
├── docs/                          # Documentation files
│   └── PHASE4_STRUCTURE.md        # This file
├── tests/                         # Test suite directory
│   ├── test_tpm_attestation.py    # Property-based tests (to be added)
│   ├── test_integration.py        # Integration tests (to be added)
│   └── test_scripts.sh            # Script tests (to be added)
├── complete_k8s_setup.sh          # Kubernetes setup script (from phase 3)
├── Dockerfile                     # Container image definition (from phase 3)
├── fix_cni_manual.sh              # CNI fix script (from phase 3)
├── mtls_demo.py                   # Python mTLS application (to be modified for TPM)
├── mtls-app.yaml                  # Kubernetes manifest (to be modified for TPM)
├── README-docker-phase2.md        # Phase 2 documentation (reference)
├── README-k8s-phase3.md           # Phase 3 documentation (reference)
├── README-spire-setup.md          # SPIRE setup documentation (reference)
├── run_k8s_demo.sh                # Demo execution script (from phase 3)
├── RUNBOOK-k8s-spire.md           # Phase 3 runbook (reference)
├── setup_k8s.sh                   # Kubernetes setup (from phase 3)
└── start_spire_agent.sh           # SPIRE agent startup (from phase 3)
```

## Files Copied from Phase 3

All files from `phase_3_k8s` have been copied to this directory to serve as the foundation for Phase 4 TPM integration. The original phase 3 files remain in `phase_3_k8s` for reference.

## New Directories

- **docs/**: Contains documentation specific to Phase 4 TPM integration
- **tests/**: Contains the test suite including property-based tests and integration tests

## Next Steps

The following files will be added or modified during Phase 4 implementation:

### New Files to be Added:
- `README-tpm-phase4.md` - Main Phase 4 documentation
- `MIGRATION-from-phase3.md` - Migration guide from Phase 3 to Phase 4
- `setup_tpm.sh` - Automated TPM setup script
- `verify_tpm.sh` - TPM verification script
- `run_tpm_demo.sh` - TPM demo execution script
- `server.conf.tpm` - SPIRE Server configuration with TPM
- `agent.conf.tpm` - SPIRE Agent configuration with TPM

### Files to be Modified:
- `mtls_demo.py` - Add TPM attestation logging
- `mtls-app.yaml` - Add TPM device mounts and configuration

## Requirements Validated

This directory structure satisfies:
- **Requirement 8.1**: All files from phase_3_k8s copied to phase_4_tpm
- **Requirement 8.2**: Original phase 3 configuration files preserved in phase_3_k8s directory
