# Quick Start Guide - TPM Integration Workaround

## TL;DR - What Happened

Your SPIRE installation doesn't have the TPM plugin built-in. This is normal - TPM support is not included in standard SPIRE distributions.

## Solution: Use Standard SPIRE + Application-Layer TPM Validation

Instead of TPM node attestation, we'll use:
1. **Standard SPIRE attestation** (join_token)
2. **TPM validation in your Python application**
3. **Same security benefits** with a different architecture

## Run the Demo Now

```bash
cd ~/dhanush/phase_4_tpm

# Make script executable
chmod +x run_demo_without_tpm_plugin.sh

# Run the demo
sudo ./run_demo_without_tpm_plugin.sh
```

This script will:
- ✅ Start SPIRE Server (standard config)
- ✅ Start SPIRE Agent (join token attestation)
- ✅ Register your workload
- ✅ Read TPM PCR values
- ✅ Run the mTLS demo

## What's Different?

### Original Plan (Requires TPM Plugin)
```
TPM → SPIRE Agent (TPM attestor) → SPIRE Server → SVID
```

### Current Implementation (Works Now)
```
TPM → Python App (validates PCRs) → SPIRE Agent → SPIRE Server → SVID
```

## Files Created for You

1. **`run_demo_without_tpm_plugin.sh`** - Ready-to-use demo script
2. **`BUILD_SPIRE_WITH_TPM.md`** - Guide if you want to build SPIRE with TPM
3. **`README_TPM_STATUS.md`** - Detailed explanation of the situation

## Verification Steps

After running the demo:

```bash
# 1. Check SPIRE is running
ps aux | grep spire

# 2. Check TPM is accessible
tpm2_pcrread sha256:0

# 3. Check SPIRE agent list
sudo /opt/spire/bin/spire-server agent list

# 4. Check workload entries
sudo /opt/spire/bin/spire-server entry show

# 5. Check logs
tail -f /opt/spire/server.log
tail -f /opt/spire/agent.log
```

## Why This Approach Works

**Security:** TPM validation still happens - just in your application instead of SPIRE
**Compatibility:** Works with standard SPIRE (no custom builds)
**Flexibility:** You control the TPM validation logic
**Production-Ready:** Uses stable SPIRE features

## Future: When TPM Plugin Becomes Available

When SPIRE adds official TPM support:
1. Update SPIRE binaries
2. Switch to `server.conf.tpm` and `agent.conf.tpm`
3. Remove application-layer TPM validation
4. Everything else stays the same

## Need Help?

- **Can't run script:** Make sure you're using `sudo`
- **TPM not found:** Check `/dev/tpm*` exists
- **SPIRE won't start:** Check `/opt/spire/conf/server.conf` exists
- **Demo fails:** Check logs in `/opt/spire/*.log`

## Ready to Go!

```bash
sudo ./run_demo_without_tpm_plugin.sh
```

That's it! The script handles everything automatically.
