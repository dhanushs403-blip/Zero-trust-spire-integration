# Building SPIRE with TPM Support

## Important Note

As of SPIRE 1.12.5, the TPM node attestor plugin is **not included** in the standard SPIRE distribution. There are several approaches to enable TPM attestation:

## Option 1: Use SPIRE TPM Plugin (Recommended)

The SPIRE community maintains TPM plugins as external plugins. However, these are experimental and may not be production-ready.

### Check for Official TPM Plugin

1. **Check SPIRE Plugin Repository:**
   ```bash
   # Visit: https://github.com/spiffe/spire-plugin-sdk
   # Look for TPM-related plugins
   ```

2. **Check SPIRE Issues/Discussions:**
   ```bash
   # Visit: https://github.com/spiffe/spire/issues
   # Search for "TPM" to see current status
   ```

## Option 2: Build Custom SPIRE with TPM Support

If you want to build SPIRE from source with TPM support, you'll need to:

### Prerequisites

```bash
# Install Go (1.21 or later)
sudo apt update
sudo apt install -y golang-go

# Verify Go installation
go version

# Install build dependencies
sudo apt install -y git make gcc libc6-dev

# Install TPM development libraries
sudo apt install -y libtss2-dev libtss2-esys-3.0.2-0
```

### Clone and Build SPIRE

```bash
# Create workspace
mkdir -p ~/spire-build
cd ~/spire-build

# Clone SPIRE repository
git clone https://github.com/spiffe/spire.git
cd spire

# Checkout stable version
git checkout v1.12.5

# Build SPIRE
make build

# Binaries will be in: ./bin/
ls -la bin/
```

### Note on TPM Plugin

The standard SPIRE build **does not include TPM attestor**. You would need to:

1. **Find or create a TPM plugin** that implements the SPIRE plugin interface
2. **Build it as an external plugin**
3. **Configure SPIRE to load the external plugin**

## Option 3: Use Alternative Attestation (Practical Approach)

Since TPM support in SPIRE is limited, consider these alternatives:

### 3.1 Use Join Token Attestation

This is the simplest approach and works with your current SPIRE installation:

```bash
# Server config (already in your setup)
NodeAttestor "join_token" {
    plugin_data {}
}
```

### 3.2 Use X.509 Certificate Attestation

If you have machine certificates:

```bash
NodeAttestor "x509pop" {
    plugin_data {
        ca_bundle_path = "/path/to/ca-bundle.pem"
    }
}
```

### 3.3 Use AWS/Azure/GCP Attestation

If running in cloud:

```bash
# For AWS
NodeAttestor "aws_iid" {
    plugin_data {}
}

# For Azure
NodeAttestor "azure_msi" {
    plugin_data {}
}

# For GCP
NodeAttestor "gcp_iit" {
    plugin_data {}
}
```

## Option 4: Simulate TPM Attestation for Testing

For development/testing purposes, you can simulate TPM-like behavior:

### Create a Custom Attestation Flow

1. **Use join tokens with TPM-derived values:**
   ```bash
   # Generate token based on TPM PCR values
   TOKEN=$(tpm2_pcrread sha256:0 | sha256sum | cut -d' ' -f1)
   
   # Create entry with this token
   /opt/spire/bin/spire-server token generate \
       -spiffeID spiffe://example.org/agent/tpm-simulated \
       -token $TOKEN
   ```

2. **Use workload attestation with TPM selectors:**
   - Even without TPM node attestation, you can use Docker/K8s workload attestation
   - Add custom selectors that reference TPM state
   - Validate TPM state in your application layer

## Recommended Path Forward

Given the current state of SPIRE TPM support, I recommend:

### Phase 4A: Use Standard SPIRE with Enhanced Workload Attestation

1. **Use join_token for node attestation** (already supported)
2. **Use Docker/K8s for workload attestation** (already supported)
3. **Add TPM validation at application layer:**

```python
# In your Python application
import subprocess
import hashlib

def verify_tpm_state():
    """Verify TPM PCR values before requesting SVID"""
    try:
        # Read PCR values
        result = subprocess.run(
            ['tpm2_pcrread', 'sha256:0'],
            capture_output=True,
            text=True
        )
        
        pcr_value = extract_pcr_value(result.stdout)
        expected_pcr = load_expected_pcr()
        
        if pcr_value != expected_pcr:
            raise Exception("TPM PCR mismatch - system may be compromised")
        
        return True
    except Exception as e:
        print(f"TPM verification failed: {e}")
        return False

# Call before fetching SVID
if verify_tpm_state():
    svid = fetch_svid_from_spire()
else:
    exit(1)
```

### Phase 4B: Document TPM Integration Points

Create documentation showing:
1. Where TPM attestation would fit in the architecture
2. How to validate TPM state at application layer
3. Migration path when SPIRE adds official TPM support

## Current Status Check

Let's verify what your SPIRE installation supports:

```bash
# Check SPIRE version
/opt/spire/bin/spire-server --version

# List available plugins
/opt/spire/bin/spire-server run -help 2>&1 | grep -A 50 "Node attestor plugins"

# Check if any TPM-related plugins exist
find /opt/spire -name "*tpm*" -o -name "*TPM*"
```

## Next Steps

1. **Verify current SPIRE capabilities:**
   ```bash
   /opt/spire/bin/spire-server run -help 2>&1 | grep -i attestor
   ```

2. **Check SPIRE community for TPM plugin status:**
   - Visit: https://github.com/spiffe/spire/discussions
   - Search for: "TPM attestation"

3. **Consider hybrid approach:**
   - Use standard SPIRE attestation (join_token, x509pop, cloud providers)
   - Add TPM validation in application layer
   - Document architecture for future TPM plugin integration

## References

- SPIRE Documentation: https://spiffe.io/docs/latest/spire/
- SPIRE Plugin SDK: https://github.com/spiffe/spire-plugin-sdk
- TPM 2.0 Tools: https://github.com/tpm2-software/tpm2-tools
- SPIFFE Community: https://slack.spiffe.io/

## Support

If you need TPM attestation for production:
1. Consider reaching out to SPIFFE community
2. Explore commercial SPIRE distributions that may include TPM support
3. Implement TPM validation at application layer as interim solution
