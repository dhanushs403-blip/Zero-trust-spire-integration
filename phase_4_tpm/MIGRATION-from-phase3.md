# Migration Guide: Phase 3 to Phase 4 (TPM Integration)

## Overview

This guide provides step-by-step instructions for migrating from Phase 3 (Kubernetes-based SPIRE mTLS) to Phase 4 (TPM-integrated SPIRE mTLS). The migration adds hardware-backed attestation while maintaining backward compatibility with existing workloads.

## Key Differences Between Phase 3 and Phase 4

### Phase 3 (Kubernetes SPIRE Integration)
- **Node Attestation**: Join token-based (software)
- **Agent Identity**: Based on join token
- **Workload Attestation**: Docker labels only
- **Security Model**: Software-based trust
- **Agent SPIFFE ID**: `spiffe://example.org/spire/agent/join_token/<hash>`

### Phase 4 (TPM-Integrated SPIRE)
- **Node Attestation**: TPM hardware-based
- **Agent Identity**: Cryptographically bound to TPM
- **Workload Attestation**: Docker labels + optional TPM PCR selectors
- **Security Model**: Hardware-rooted trust
- **Agent SPIFFE ID**: `spiffe://example.org/spire/agent/tpm/<hash>`

## Prerequisites for Migration

### Hardware Requirements
- TPM 2.0 device (physical or firmware TPM)
- TPM must be enabled in BIOS/UEFI
- TPM device accessible at `/dev/tpm0` or `/dev/tpmrm0`

### Software Requirements
- All Phase 3 components working correctly
- Root/sudo access for configuration changes
- Ability to restart SPIRE Server and Agent

### Pre-Migration Checklist
- [ ] Phase 3 demo runs successfully
- [ ] TPM device is present and accessible
- [ ] No critical workloads running (or plan for downtime)
- [ ] Backup of current SPIRE configuration files
- [ ] Understanding of current workload registrations

## Configuration Changes

### 1. SPIRE Server Configuration

**Phase 3 Configuration:**
```hcl
plugins {
    NodeAttestor "join_token" {
        plugin_data {}
    }
}
```

**Phase 4 Configuration:**
```hcl
plugins {
    # Keep join_token for backward compatibility during migration
    NodeAttestor "join_token" {
        plugin_data {}
    }
    
    # Add TPM node attestor
    NodeAttestor "tpm" {
        plugin_data {
            hash_algorithm = "sha256"
        }
    }
}
```

**Changes:**
- Added `NodeAttestor "tpm"` plugin
- Kept `join_token` attestor for backward compatibility
- Specified `hash_algorithm = "sha256"` for PCR banks

### 2. SPIRE Agent Configuration

**Phase 3 Configuration:**
```hcl
plugins {
    NodeAttestor "join_token" {
        plugin_data {}
    }
    
    WorkloadAttestor "docker" {
        plugin_data {
            docker_socket_path = "/var/run/docker.sock"
        }
    }
}
```

**Phase 4 Configuration:**
```hcl
plugins {
    # Keep join_token for backward compatibility during migration
    NodeAttestor "join_token" {
        plugin_data {}
    }
    
    # Add TPM node attestor
    NodeAttestor "tpm" {
        plugin_data {
            tpm_device_path = "/dev/tpmrm0"
            hash_algorithm = "sha256"
        }
    }
    
    # Docker workload attestor unchanged
    WorkloadAttestor "docker" {
        plugin_data {
            docker_socket_path = "/var/run/docker.sock"
        }
    }
}
```

**Changes:**
- Added `NodeAttestor "tpm"` plugin with device path
- Specified `tpm_device_path = "/dev/tpmrm0"` (or `/dev/tpm0`)
- Specified `hash_algorithm = "sha256"` matching server
- Docker workload attestor remains unchanged

### 3. Workload Registration

**Phase 3 Registration:**
```bash
/opt/spire/bin/spire-server entry create \
  -parentID spiffe://example.org/spire/agent/join_token/<hash> \
  -spiffeID spiffe://example.org/k8s-workload \
  -selector docker:label:io.kubernetes.container.name:mtls-app \
  -selector docker:label:io.kubernetes.pod.namespace:default
```

**Phase 4 Registration (Option 1: Docker selectors only):**
```bash
/opt/spire/bin/spire-server entry create \
  -parentID spiffe://example.org/spire/agent/tpm/<hash> \
  -spiffeID spiffe://example.org/k8s-workload \
  -selector docker:label:io.kubernetes.container.name:mtls-app \
  -selector docker:label:io.kubernetes.pod.namespace:default
```

**Phase 4 Registration (Option 2: TPM + Docker selectors):**
```bash
# Get current PCR value
PCR_VALUE=$(tpm2_pcrread sha256:0 | grep "0 :" | awk '{print $3}')

/opt/spire/bin/spire-server entry create \
  -parentID spiffe://example.org/spire/agent/tpm/<hash> \
  -spiffeID spiffe://example.org/k8s-workload \
  -selector tpm:pcr:0:$PCR_VALUE \
  -selector docker:label:io.kubernetes.container.name:mtls-app \
  -selector docker:label:io.kubernetes.pod.namespace:default
```

**Changes:**
- Parent ID changes from `join_token/<hash>` to `tpm/<hash>`
- Optional: Add TPM PCR selectors for hardware-backed workload attestation
- Docker selectors remain unchanged for backward compatibility

### 4. Python Application

**Phase 3 Application:**
- Fetches SVID from SPIRE Agent
- No TPM-specific logic

**Phase 4 Application:**
- Fetches SVID from SPIRE Agent (same API)
- Optional: Logs TPM attestation status
- Optional: Verifies agent parent ID contains "tpm"

**Changes:**
- Application code largely unchanged
- TPM attestation is transparent to the application
- Optional logging enhancements for TPM status

### 5. Kubernetes Deployment Manifest

**Phase 3 Manifest:**
```yaml
volumes:
  - name: spire-agent-socket
    hostPath:
      path: /tmp/spire-agent/public/api.sock
      type: Socket
  - name: spire-agent-bin
    hostPath:
      path: /opt/spire/bin/spire-agent
      type: File
```

**Phase 4 Manifest:**
```yaml
volumes:
  - name: spire-agent-socket
    hostPath:
      path: /tmp/spire-agent/public/api.sock
      type: Socket
  - name: spire-agent-bin
    hostPath:
      path: /opt/spire/bin/spire-agent
      type: File
  # Optional: Mount TPM device for direct access (not required)
  - name: tpm-device
    hostPath:
      path: /dev/tpmrm0
      type: CharDevice
```

**Changes:**
- Optional: Add TPM device mount (not required for basic flow)
- SPIRE Agent socket and binary mounts unchanged
- Most workloads don't need direct TPM access

## Step-by-Step Migration Instructions

### Step 1: Verify Phase 3 is Working

Before migrating, ensure Phase 3 is functioning correctly:

```bash
cd phase_3_k8s

# Verify SPIRE components are running
pgrep -a spire-server
pgrep -a spire-agent

# Verify Kubernetes is running
kubectl get nodes

# Verify demo works
sudo ./run_k8s_demo.sh

# Check pod logs
kubectl logs <pod-name>
```

**Expected:** Demo completes successfully with mTLS communication.

### Step 2: Verify TPM Device

Check that your system has a TPM device:

```bash
cd phase_4_tpm

# Run TPM detection script
sudo ./detect_tpm.sh
```

**Expected:** Script reports TPM device found and accessible.

**If TPM not found:**
1. Enter BIOS/UEFI settings
2. Enable TPM/Security Chip
3. Save and reboot
4. Re-run detection script

### Step 3: Backup Phase 3 Configuration

Create backups of your current configuration:

```bash
# Backup SPIRE configurations
sudo cp /opt/spire/conf/server/server.conf /opt/spire/conf/server/server.conf.phase3.backup
sudo cp /opt/spire/conf/agent/agent.conf /opt/spire/conf/agent/agent.conf.phase3.backup

# Backup workload registrations
sudo /opt/spire/bin/spire-server entry show > /tmp/spire-entries-phase3.txt
```

### Step 4: Run Automated TPM Setup

Use the setup script to configure TPM integration:

```bash
cd phase_4_tpm

# Run TPM setup script
sudo ./setup_tpm.sh
```

**What this does:**
- Installs tpm2-tools and tpm2-abrmd if missing
- Backs up existing SPIRE configurations
- Adds TPM node attestor to server.conf
- Adds TPM node attestor to agent.conf
- Verifies configuration updates

**Expected:** Script completes successfully with backup directory created.

### Step 5: Stop Phase 3 SPIRE Components

Stop the existing SPIRE Server and Agent:

```bash
# Stop SPIRE Agent
sudo pkill -f spire-agent

# Stop SPIRE Server
sudo pkill -f spire-server

# Verify processes stopped
pgrep -f spire
```

**Expected:** No SPIRE processes running.

### Step 6: Start Phase 4 SPIRE Components

Start SPIRE with TPM configuration:

```bash
cd phase_4_tpm

# Start SPIRE Server with TPM config
sudo /opt/spire/bin/spire-server run -config /opt/spire/conf/server/server.conf > /opt/spire/server.log 2>&1 &

# Wait for server to start
sleep 5

# Generate join token for agent
JOIN_TOKEN=$(sudo /opt/spire/bin/spire-server token generate -spiffeID spiffe://example.org/agent | grep "Token:" | awk '{print $2}')

# Start SPIRE Agent with TPM config
sudo /opt/spire/bin/spire-agent run -config /opt/spire/conf/agent/agent.conf -joinToken $JOIN_TOKEN > /opt/spire/agent.log 2>&1 &

# Wait for agent to complete TPM attestation
sleep 10
```

**Expected:** Both server and agent start successfully.

### Step 7: Verify TPM Attestation

Confirm that TPM attestation is working:

```bash
cd phase_4_tpm

# Run verification script
sudo ./verify_tpm.sh

# Check agent parent ID
sudo /opt/spire/bin/spire-server agent list

# Check agent logs for TPM messages
tail -50 /opt/spire/agent.log | grep -i tpm
```

**Expected:** 
- Verification script reports "TPM ATTESTATION IS ACTIVE"
- Agent list shows SPIFFE ID with "tpm" in path
- Agent logs contain TPM initialization messages

### Step 8: Re-register Workloads

Update workload registrations with new agent parent ID:

```bash
# Get new TPM agent ID
AGENT_ID=$(sudo /opt/spire/bin/spire-server agent list | grep "SPIFFE ID" | awk '{print $4}')

echo "New Agent ID: $AGENT_ID"

# Delete old Phase 3 registration
sudo /opt/spire/bin/spire-server entry delete -spiffeID spiffe://example.org/k8s-workload

# Create new Phase 4 registration (Docker selectors only)
sudo /opt/spire/bin/spire-server entry create \
  -parentID $AGENT_ID \
  -spiffeID spiffe://example.org/k8s-workload \
  -selector docker:label:io.kubernetes.container.name:mtls-app \
  -selector docker:label:io.kubernetes.pod.namespace:default

# Verify registration
sudo /opt/spire/bin/spire-server entry show -spiffeID spiffe://example.org/k8s-workload
```

**Expected:** New entry created with TPM agent as parent.

### Step 9: Deploy Phase 4 Application

Deploy the updated application:

```bash
cd phase_4_tpm

# Delete Phase 3 deployment
kubectl delete deployment mtls-app

# Apply Phase 4 deployment
kubectl apply -f mtls-app.yaml

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=mtls-demo --timeout=60s

# Check pod logs
POD_NAME=$(kubectl get pods -l app=mtls-demo -o jsonpath="{.items[0].metadata.name}")
kubectl logs $POD_NAME
```

**Expected:** Pod starts successfully and fetches TPM-attested SVID.

### Step 10: Verify End-to-End Functionality

Test the complete system:

```bash
# Check pod is running
kubectl get pods -l app=mtls-demo

# View pod logs
kubectl logs <pod-name>

# Verify SVID fetch succeeded
kubectl logs <pod-name> | grep "Successfully fetched SVIDs"

# Verify mTLS communication
kubectl logs <pod-name> | grep "VERIFIED"

# Run verification script
sudo ./verify_tpm.sh
```

**Expected:** All checks pass, mTLS communication works.

## Rollback Procedure

If migration fails or issues arise, rollback to Phase 3:

### Step 1: Stop Phase 4 Components

```bash
# Stop SPIRE Agent
sudo pkill -f spire-agent

# Stop SPIRE Server
sudo pkill -f spire-server

# Delete Phase 4 deployment
kubectl delete deployment mtls-app
```

### Step 2: Restore Phase 3 Configuration

```bash
# Restore server configuration
sudo cp /opt/spire/conf/server/server.conf.phase3.backup /opt/spire/conf/server/server.conf

# Restore agent configuration
sudo cp /opt/spire/conf/agent/agent.conf.phase3.backup /opt/spire/conf/agent/agent.conf
```

### Step 3: Restart Phase 3 Components

```bash
cd phase_3_k8s

# Run Phase 3 demo
sudo ./run_k8s_demo.sh
```

### Step 4: Verify Phase 3 Functionality

```bash
# Check SPIRE components
pgrep -a spire

# Check pod status
kubectl get pods -l app=mtls-demo

# View pod logs
kubectl logs <pod-name>
```

**Expected:** Phase 3 functionality restored.

## Backward Compatibility Considerations

### Dual Attestation Support

Phase 4 supports both join token and TPM attestation simultaneously:

**Server Configuration:**
```hcl
NodeAttestor "join_token" {
    plugin_data {}
}

NodeAttestor "tpm" {
    plugin_data {
        hash_algorithm = "sha256"
    }
}
```

**Benefits:**
- Allows gradual migration of agents
- Some agents can use TPM, others use join tokens
- No disruption to existing workloads

**Considerations:**
- Mixed security models in same trust domain
- Document which agents use which attestation method
- Plan to deprecate join token after full migration

### Workload Attestation Compatibility

Workloads can use Docker selectors only (Phase 3 style) or add TPM selectors (Phase 4 enhanced):

**Docker Selectors Only (Backward Compatible):**
```bash
-selector docker:label:io.kubernetes.container.name:mtls-app
```

**Docker + TPM Selectors (Enhanced Security):**
```bash
-selector tpm:pcr:0:$PCR_VALUE
-selector docker:label:io.kubernetes.container.name:mtls-app
```

**Benefits:**
- Workloads continue functioning during migration
- Can add TPM selectors incrementally
- No application code changes required

**Considerations:**
- PCR values change with system state
- Must update registrations after system changes
- Document which workloads use TPM selectors

### Application Compatibility

Phase 4 applications are fully compatible with Phase 3:

**No Changes Required:**
- SPIRE Agent Workload API unchanged
- SVID fetch process identical
- mTLS communication unchanged
- Certificate format unchanged

**Optional Enhancements:**
- Log TPM attestation status
- Verify agent parent ID contains "tpm"
- Display TPM-specific information

## Migration Strategies

### Strategy 1: Big Bang Migration (Recommended for Development)

Migrate all components at once:

1. Stop all Phase 3 components
2. Configure TPM on all nodes
3. Update all configurations
4. Start Phase 4 components
5. Re-register all workloads
6. Deploy Phase 4 applications

**Pros:**
- Clean cutover
- Consistent security model
- Simpler to manage

**Cons:**
- Requires downtime
- Higher risk if issues arise
- All-or-nothing approach

### Strategy 2: Gradual Migration (Recommended for Production)

Migrate nodes incrementally:

1. Keep Phase 3 running
2. Add TPM attestor to server (dual mode)
3. Migrate one agent at a time:
   - Configure TPM on node
   - Update agent configuration
   - Restart agent with TPM
   - Re-register workloads for that agent
4. Once all agents migrated, remove join token attestor

**Pros:**
- Minimal downtime
- Lower risk
- Can validate each step

**Cons:**
- More complex
- Mixed security models temporarily
- Longer migration timeline

### Strategy 3: Parallel Deployment

Run Phase 3 and Phase 4 side-by-side:

1. Keep Phase 3 running
2. Deploy Phase 4 on separate nodes/cluster
3. Gradually move workloads to Phase 4
4. Decommission Phase 3 when complete

**Pros:**
- Zero downtime
- Easy rollback
- Thorough testing possible

**Cons:**
- Requires additional resources
- More complex infrastructure
- Separate trust domains

## Common Migration Issues

### Issue 1: Agent Fails to Attest with TPM

**Symptoms:**
- Agent starts but doesn't register with server
- No TPM in agent parent ID

**Diagnosis:**
```bash
tail -100 /opt/spire/agent.log | grep -i tpm
tail -100 /opt/spire/server.log | grep -i tpm
```

**Resolution:**
- Verify TPM device path in agent.conf
- Ensure hash_algorithm matches between server and agent
- Check TPM device is accessible
- Clear TPM if previously used: `sudo tpm2_clear`

### Issue 2: Workload Registration Fails

**Symptoms:**
- Cannot create entry with new agent parent ID
- Error: "parent ID not found"

**Diagnosis:**
```bash
sudo /opt/spire/bin/spire-server agent list
```

**Resolution:**
- Wait for agent to complete attestation (may take 10-30 seconds)
- Verify agent appears in agent list
- Use correct agent SPIFFE ID as parent ID
- Check server logs for attestation errors

### Issue 3: PCR Values Change After Reboot

**Symptoms:**
- Workload cannot fetch SVID after system reboot
- PCR mismatch errors in logs

**Diagnosis:**
```bash
tpm2_pcrread sha256
sudo /opt/spire/bin/spire-server entry show
```

**Resolution:**
- PCR values reflect system state and change with updates/reboots
- For development: Use Docker selectors only (no TPM selectors)
- For production: Document expected PCR values and update after changes
- Re-register workload with current PCR values

### Issue 4: Performance Degradation

**Symptoms:**
- Slower SVID fetch times
- Increased agent CPU usage

**Diagnosis:**
```bash
time /opt/spire/bin/spire-agent api fetch
top -p $(pgrep spire-agent)
```

**Resolution:**
- TPM operations are slower than software (expected)
- Use /dev/tpmrm0 for better concurrency
- Cache SVIDs in application (don't fetch repeatedly)
- Monitor and set appropriate timeouts

## Post-Migration Validation

### Validation Checklist

- [ ] SPIRE Server running with TPM node attestor
- [ ] SPIRE Agent running with TPM node attestor
- [ ] Agent parent ID contains "tpm"
- [ ] Workloads registered with correct parent ID
- [ ] Pods can fetch SVIDs successfully
- [ ] mTLS communication works
- [ ] TPM attestation verified with verify_tpm.sh
- [ ] No errors in SPIRE logs
- [ ] Application logs show successful operation
- [ ] Performance is acceptable

### Validation Commands

```bash
# Check SPIRE processes
pgrep -a spire

# Verify TPM attestation
sudo ./verify_tpm.sh

# Check agent parent ID
sudo /opt/spire/bin/spire-server agent list

# Check workload entries
sudo /opt/spire/bin/spire-server entry show

# Check pod status
kubectl get pods -l app=mtls-demo

# View pod logs
kubectl logs <pod-name>

# Check SPIRE logs
tail -50 /opt/spire/server.log
tail -50 /opt/spire/agent.log

# Read TPM PCR values
tpm2_pcrread sha256
```

## Best Practices

### During Migration

1. **Test in Development First**: Validate migration process in non-production environment
2. **Backup Everything**: Configuration files, workload registrations, certificates
3. **Document Changes**: Keep record of what was changed and when
4. **Monitor Closely**: Watch logs and metrics during and after migration
5. **Have Rollback Plan**: Know how to quickly revert if issues arise

### After Migration

1. **Remove Join Token Attestor**: Once all agents migrated, remove from configuration
2. **Document TPM Configuration**: Record device paths, PCR usage, expected values
3. **Update Runbooks**: Reflect TPM-specific procedures
4. **Train Team**: Ensure team understands TPM attestation and troubleshooting
5. **Monitor Performance**: Track SVID fetch times, agent resource usage

### Security Hardening

1. **Restrict TPM Access**: Limit TPM device permissions to SPIRE Agent only
2. **Use Resource Manager**: Prefer /dev/tpmrm0 over /dev/tpm0
3. **Document PCR Usage**: Clearly document which PCRs are used and why
4. **Regular Audits**: Review TPM access logs and attestation records
5. **Update Procedures**: Document how to handle system updates that change PCRs

## Additional Resources

- [Phase 4 README](README-tpm-phase4.md) - Complete Phase 4 documentation
- [SPIRE TPM Node Attestor Documentation](https://github.com/spiffe/spire/blob/main/doc/plugin_server_nodeattestor_tpm.md)
- [TPM 2.0 Specification](https://trustedcomputinggroup.org/resource/tpm-library-specification/)
- [tpm2-tools Documentation](https://github.com/tpm2-software/tpm2-tools)

## Support

If you encounter issues during migration:

1. Check troubleshooting section in [README-tpm-phase4.md](README-tpm-phase4.md)
2. Review SPIRE logs: `/opt/spire/server.log` and `/opt/spire/agent.log`
3. Run verification script: `sudo ./verify_tpm.sh`
4. Check TPM device: `sudo ./detect_tpm.sh`
5. Consult SPIRE documentation and community resources
