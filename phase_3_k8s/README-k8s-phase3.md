# Phase 3: Kubernetes SPIRE Integration

## Overview

Phase 3 demonstrates SPIFFE identity integration in a Kubernetes environment. This phase migrates the working Docker-based SPIRE mTLS demonstration to Kubernetes, enabling pods to obtain SPIFFE identities from the host's SPIRE Agent and perform mutual TLS authentication.

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Host Machine (Ubuntu 22.04)              │
│                                                             │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              SPIRE Server                            │  │
│  │  - Manages identity registrations                    │  │
│  │  - Issues SVIDs to attested workloads               │  │
│  └──────────────────┬───────────────────────────────────┘  │
│                     │                                       │
│  ┌──────────────────▼───────────────────────────────────┐  │
│  │              SPIRE Agent                             │  │
│  │  - Docker workload attestor enabled                  │  │
│  │  - Socket: /tmp/spire-agent/public/api.sock         │  │
│  │  - Binary: /opt/spire/bin/spire-agent               │  │
│  └──────────────────┬───────────────────────────────────┘  │
│                     │                                       │
│  ┌──────────────────▼───────────────────────────────────┐  │
│  │         Minikube (--driver=none)                     │  │
│  │  - Runs K8s directly on host (no VM)                │  │
│  │  - CNI: Flannel (10.244.0.0/16)                     │  │
│  │  - Allows hostPath mounts to host filesystem        │  │
│  │                                                      │  │
│  │  ┌────────────────────────────────────────────────┐ │  │
│  │  │         Kubernetes Pod                         │ │  │
│  │  │  Name: mtls-app-xxxxx                         │ │  │
│  │  │  Labels: app=mtls-demo                        │ │  │
│  │  │                                                │ │  │
│  │  │  Volumes Mounted:                             │ │  │
│  │  │  - /tmp/spire-agent/public/api.sock (socket)  │ │  │
│  │  │  - /opt/spire/bin/spire-agent (binary, ro)    │ │  │
│  │  │                                                │ │  │
│  │  │  ┌──────────────────────────────────────────┐ │ │  │
│  │  │  │  Container: mtls-app                     │ │ │  │
│  │  │  │  Image: mtls-demo-image:latest          │ │ │  │
│  │  │  │                                          │ │ │  │
│  │  │  │  1. Fetch SVID via Agent API            │ │ │  │
│  │  │  │  2. Save certs to /app                  │ │ │  │
│  │  │  │  3. Run mTLS server on port 9999        │ │ │  │
│  │  │  └──────────────────────────────────────────┘ │ │  │
│  │  └────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

1. **Minikube with --driver=none**: Runs Kubernetes directly on the host without VM isolation, enabling direct access to the host's SPIRE Agent socket via hostPath volume mounts.

2. **Flannel CNI**: Provides pod networking with minimal configuration, reliable operation with Minikube's none driver.

3. **hostPath Volumes**: Simple approach for single-node setup that allows pods to access the SPIRE Agent socket and binary from the host filesystem.

4. **Docker Label Attestation**: SPIRE Agent uses Docker labels (io.kubernetes.container.name, io.kubernetes.pod.namespace) to identify and attest Kubernetes workloads.

## Prerequisites

- Ubuntu 22.04 LTS
- Root/sudo access
- SPIRE Server and Agent installed and running (from Phase 1/2)
- Docker installed
- Internet connection for downloading CNI plugins and Kubernetes components

## Setup Instructions

### Step 1: Prepare the Environment

Ensure SPIRE Server and Agent are running:

```bash
# Check SPIRE Server status
pgrep -a spire-server

# Check SPIRE Agent status
pgrep -a spire-agent

# Verify SPIRE Agent socket exists
ls -la /tmp/spire-agent/public/api.sock
```

### Step 2: Build the Docker Image

Build the mTLS demo Docker image:

```bash
# Build the image
sudo docker build -t mtls-demo-image:latest .

# Verify the image exists
sudo docker images | grep mtls-demo-image
```

### Step 3: Run Complete Kubernetes Setup

Execute the automated setup script:

```bash
sudo ./complete_k8s_setup.sh
```

This script performs the following operations:
1. Cleans up any existing Minikube installation
2. Applies Ubuntu 22.04 kernel security fixes
3. Installs prerequisites (conntrack, socat)
4. Downloads and installs CNI plugins
5. Starts Minikube with --driver=none
6. Applies Flannel CNI configuration
7. Fixes file permissions for kubectl access
8. Verifies node readiness (waits up to 120 seconds)

**Expected Output:**
```
✅ Cleanup completed
✅ Kernel fixes applied
✅ Prerequisites installed
✅ CNI plugins installed
✅ Minikube started
✅ Flannel applied
✅ Permissions fixed
✅ Node is Ready
```

### Step 4: Deploy the mTLS Demo Application

Run the Kubernetes demo script:

```bash
sudo ./run_k8s_demo.sh
```

This script performs:
1. Verifies SPIRE socket exists on host
2. Loads Docker image into Minikube
3. Registers workload with SPIRE Server using Kubernetes selectors
4. Deploys the application to Kubernetes
5. Waits for pod to reach Running state
6. Displays pod logs

**Expected Output:**
```
✅ SPIRE socket found
✅ Docker image loaded
✅ Workload registered
✅ Deployment applied
✅ Pod is running

Pod logs:
[SVID Fetch] Calling SPIRE Agent API...
✅ Successfully ran fetch command
✅ SVID files found on disk: svid.0.pem, svid.0.key, bundle.0.pem
[Server] Secure mTLS Server listening on 9999
```

### Step 5: Verify the Deployment

Check pod status and logs:

```bash
# View pod status
kubectl get pods

# View pod details
kubectl describe pod <pod-name>

# View pod logs
kubectl logs <pod-name>

# Check SPIRE registration
/opt/spire/bin/spire-server entry show
```

## Testing and Verification

### Pre-Deployment Verification

Before running the demo, verify SPIRE components are running:

```bash
# Check SPIRE Server and Agent processes
ps aux | grep spire

# Expected output should show:
# - spire-server run -config conf/server/server.conf
# - spire-agent run -config conf/agent/agent.conf

# Verify SPIRE Agent socket exists
ls -la /tmp/spire-agent/public/api.sock

# Expected output:
# srwxrwxrwx 1 root root 0 Nov 26 14:39 /tmp/spire-agent/public/api.sock
```

**If SPIRE is not running:**
```bash
cd /home/dell/dhanush/phase_3_k8s/
sudo ./start_spire_agent.sh
```

### Post-Deployment Testing

After running `sudo ./run_k8s_demo.sh`, perform these tests:

#### 1. Check Pod Status

```bash
# List all pods
sudo kubectl get pods -l app=mtls-demo

# Expected output:
# NAME                       READY   STATUS    RESTARTS   AGE
# mtls-app-xxxxxxxxx-xxxxx   1/1     Running   0          2m
```

#### 2. View Pod Logs

```bash
# View logs (replace with your pod name)
sudo kubectl logs mtls-app-7699857877-87mzx

# Expected output should show:
# ✅ Successfully fetched SVIDs!
# [Server] Secure mTLS Server listening on 0.0.0.0:9999...
# [Client] ✅ VERIFIED SERVER IDENTITY
# [Server] ✅ VERIFIED CLIENT IDENTITY
```

#### 3. Access the Pod

```bash
# Execute into the running pod
sudo kubectl exec -it mtls-app-7699857877-87mzx -- /bin/bash

# You should now be inside the pod:
# root@mtls-app-xxxxxxxxx-xxxxx:/app#
```

#### 4. Inspect SPIRE Certificates (Inside Pod)

Once inside the pod:

```bash
# List certificate files
ls -la /app/*.pem /app/*.key

# Expected output:
# -rw------- 1 root root XXXX Nov 26 09:09 /app/bundle.0.pem
# -rw------- 1 root root XXXX Nov 26 09:09 /app/svid.0.key
# -rw------- 1 root root XXXX Nov 26 09:09 /app/svid.0.pem

# View the SVID certificate
cat /app/svid.0.pem

# View certificate details
openssl x509 -in /app/svid.0.pem -text -noout | grep -A 5 "Subject:"

# View the trust bundle
cat /app/bundle.0.pem
```

#### 5. Verify SPIRE Agent Binary Mount

```bash
# Check that the SPIRE agent binary is accessible
ls -la /opt/spire/bin/spire-agent

# Expected output:
# -rwxr-xr-x 1 root root XXXXXXXX Nov XX XX:XX /opt/spire/bin/spire-agent

# Verify the socket is mounted
ls -la /tmp/spire-agent/public/api.sock

# Expected output:
# srwxrwxrwx 1 root root 0 Nov 26 14:39 /tmp/spire-agent/public/api.sock
```

#### 6. Test mTLS Connection Manually

The server is running in the background on port 9999. Test the mTLS client:

```bash
# Run the client to connect to the mTLS server
python3 mtls_demo.py client

# Expected output:
# ==================================================
# SPIRE Docker mTLS Demo
# ==================================================
# [SPIRE] Fetching SVIDs from SPIRE Agent...
# Received 1 svid after XXms
#
# SPIFFE ID:              spiffe://example.org/k8s-workload
# ...
# ✅ Successfully fetched SVIDs!
#
# [Client] Connecting to server...
# [Client] ✅ VERIFIED SERVER IDENTITY:
#          Subject: ((('countryName', 'US'),), (('organiz ationName', 'SPIRE'),))
#          Issuer:  ((('countryName', 'US'),), ...)
# [Client] Connected! Sending message...
# [Client] Server Replied: Secure Hello from SPIRE Server!
```

#### 7. Verify SPIRE Registration

Exit the pod (`exit` or Ctrl+D), then check the SPIRE registration:

```bash
# Show all registered workloads
sudo /opt/spire/bin/spire-server entry show

# Look for the Kubernetes workload entry:
# Entry ID         : XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
# SPIFFE ID        : spiffe://example.org/k8s-workload
# Parent ID        : spiffe://example.org/spire/agent/...
# Selectors:
#   docker:label:io.kubernetes.container.name:mtls-app
#   docker:label:io.kubernetes.pod.namespace:default
```

### kubectl Permission Issues

If you encounter certificate verification errors with `kubectl`:

```bash
# Error: "tls: failed to verify certificate: x509: certificate signed by unknown authority"

# Solution: Use sudo with kubectl commands
sudo kubectl get pods
sudo kubectl logs <pod-name>
sudo kubectl exec -it <pod-name> -- /bin/bash

# OR copy the kubeconfig (not recommended as cert paths reference /root/)
sudo cp /root/.kube/config ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```

### Complete Testing Checklist

- [ ] SPIRE Server is running (`ps aux | grep spire-server`)
- [ ] SPIRE Agent is running and socket exists  
- [ ] Demo script completed successfully
- [ ] Pod is in Running state
- [ ] Pod logs show successful SVID fetch
- [ ] Pod logs show mTLS server started
- [ ] Can exec into the pod
- [ ] Certificate files exist in /app directory
- [ ] Manual client test succeeds
- [ ] SPIRE registration exists for k8s-workload
- [ ] Both client and server verified each other's identity

### Cleanup

When finished testing:

```bash
# Delete the deployment
sudo kubectl delete deployment mtls-app

# Stop Minikube (optional)
sudo minikube stop

# Stop SPIRE (optional, if done with all demos)
sudo killall spire-agent spire-server
```

## Troubleshooting Guide

### Issue 1: Node Status Shows "NotReady"

**Symptoms:**
- `kubectl get nodes` shows NotReady status
- Kubelet logs show "NetworkPluginNotReady" errors

**Diagnosis:**
```bash
# Check node status
kubectl get nodes

# Check kubelet logs
sudo journalctl -u kubelet -n 50

# Check CNI binaries
ls -la /opt/cni/bin/

# Check CNI configuration
ls -la /etc/cni/net.d/

# Check Flannel pods
kubectl get pods -n kube-flannel
```

**Resolution:**
1. Verify CNI plugins are installed in /opt/cni/bin
2. Ensure Flannel configuration exists in /etc/cni/net.d
3. Check Flannel pods are running
4. Restart kubelet: `sudo systemctl restart kubelet`
5. Re-run setup script if CNI installation failed

### Issue 2: CNI Plugin Download Fails

**Symptoms:**
- Setup script reports CNI download error
- File size is very small (~5KB instead of ~43MB)
- Error message: "Downloaded file too small"

**Diagnosis:**
```bash
# Check if CNI binaries exist
ls -la /opt/cni/bin/

# Check downloaded file
ls -lh /tmp/cni-plugins.tgz
```

**Resolution:**
1. Check internet connectivity: `ping github.com`
2. Try manual download: `curl -L https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz -o /tmp/cni-test.tgz`
3. Verify file is valid gzip: `gzip -t /tmp/cni-test.tgz`
4. Re-run setup script
5. If persistent, download CNI plugins manually and extract to /opt/cni/bin

### Issue 3: Pod Cannot Access SPIRE Socket

**Symptoms:**
- Pod logs show "socket not found" or permission errors
- SVID fetch fails

**Diagnosis:**
```bash
# Check socket exists on host
ls -la /tmp/spire-agent/public/api.sock

# Check SPIRE Agent is running
pgrep -a spire-agent

# Check pod volume mounts
kubectl describe pod <pod-name> | grep -A 10 "Mounts:"

# Check pod events
kubectl describe pod <pod-name> | grep -A 20 "Events:"
```

**Resolution:**
1. Verify SPIRE Agent is running: `sudo systemctl status spire-agent` or check process
2. Ensure socket exists: `ls -la /tmp/spire-agent/public/api.sock`
3. Check socket permissions allow access
4. Verify hostPath mount in mtls-app.yaml is correct
5. Restart SPIRE Agent if necessary
6. Redeploy pod: `kubectl delete pod <pod-name>`

### Issue 4: Pod Stuck in Pending or ContainerCreating

**Symptoms:**
- `kubectl get pods` shows Pending or ContainerCreating status
- Pod doesn't start after several minutes

**Diagnosis:**
```bash
# Check pod status
kubectl get pods

# Check pod events
kubectl describe pod <pod-name>

# Check node conditions
kubectl describe node vso

# Check if image is available
minikube image ls | grep mtls-demo-image

# Check node resources
kubectl top node
```

**Resolution:**
1. Ensure Docker image is loaded: `minikube image load mtls-demo-image:latest`
2. Verify node is Ready: `kubectl get nodes`
3. Check for resource constraints in pod events
4. Verify volume mounts are valid (socket and binary exist on host)
5. Check for scheduling issues in pod events
6. Delete and recreate deployment: `kubectl delete -f mtls-app.yaml && kubectl apply -f mtls-app.yaml`

### Issue 5: SVID Fetch Fails in Pod

**Symptoms:**
- Pod logs show SVID fetch errors
- Certificate files not created

**Diagnosis:**
```bash
# Check pod logs
kubectl logs <pod-name>

# Check SPIRE registration
/opt/spire/bin/spire-server entry show

# Check SPIRE Agent logs
sudo journalctl -u spire-agent -n 50

# Exec into pod to debug
kubectl exec -it <pod-name> -- /bin/sh
ls -la /tmp/spire-agent/public/
ls -la /opt/spire/bin/
```

**Resolution:**
1. Verify workload is registered: `/opt/spire/bin/spire-server entry show`
2. Check registration selectors match pod labels
3. Ensure SPIRE Agent can attest the workload
4. Verify pod has correct labels (app=mtls-demo)
5. Check SPIRE Agent logs for attestation errors
6. Re-register workload with correct selectors
7. Restart pod to retry SVID fetch

### Issue 6: Minikube Fails to Start

**Symptoms:**
- `minikube start` command fails
- Error messages about driver or permissions

**Diagnosis:**
```bash
# Check Minikube status
minikube status

# Check Minikube logs
minikube logs

# Check system resources
df -h
free -h

# Check for conflicting processes
pgrep -a kubelet
pgrep -a dockerd
```

**Resolution:**
1. Clean up existing Minikube: `minikube delete --all --purge`
2. Remove Minikube directories: `sudo rm -rf ~/.minikube /etc/kubernetes`
3. Ensure sufficient disk space (at least 10GB free)
4. Verify Docker is running: `sudo systemctl status docker`
5. Check kernel parameters: `sysctl fs.protected_regular`
6. Re-run complete setup script

### Issue 7: Permission Denied Errors with kubectl

**Symptoms:**
- kubectl commands fail with permission errors
- Cannot access kubeconfig file

**Diagnosis:**
```bash
# Check kubeconfig permissions
ls -la ~/.kube/config

# Check .kube directory ownership
ls -la ~/.kube/

# Check current user
whoami
```

**Resolution:**
1. Fix ownership: `sudo chown -R $USER:$USER ~/.kube ~/.minikube`
2. Fix permissions: `chmod 600 ~/.kube/config`
3. Verify KUBECONFIG environment variable: `echo $KUBECONFIG`
4. Re-run setup script which includes permission fixes

## Diagnostic Script

For comprehensive diagnostics, use the provided diagnostic script:

```bash
sudo ./diagnose_k8s_spire.sh
```

This script checks:
- Minikube status and configuration
- Node status and conditions
- CNI plugin installation
- Flannel pod status
- SPIRE Server and Agent processes
- SPIRE socket accessibility
- Docker image availability
- Pod deployment status
- Volume mounts
- Pod logs

## Component Interaction Flow

1. **Cluster Initialization**: Minikube starts with --driver=none, running Kubernetes directly on host
2. **CNI Setup**: Flannel CNI plugin provides pod networking (10.244.0.0/16)
3. **Workload Registration**: SPIRE Server registers workload with Kubernetes Docker label selectors
4. **Pod Deployment**: Kubernetes creates pod with hostPath volumes for SPIRE socket and binary
5. **Workload Attestation**: SPIRE Agent identifies pod via Docker labels (io.kubernetes.container.name, io.kubernetes.pod.namespace)
6. **SVID Issuance**: Pod calls SPIRE Agent API, receives SVID matching registered spiffeID
7. **mTLS Execution**: Pod uses SVID certificates to establish mutual TLS server on port 9999

## Key Files

- `complete_k8s_setup.sh` - Main setup orchestration script
- `fix_cni_manual.sh` - CNI plugin installation and configuration
- `run_k8s_demo.sh` - Demo deployment and orchestration
- `mtls-app.yaml` - Kubernetes deployment manifest
- `mtls_demo.py` - Python mTLS demonstration application
- `diagnose_k8s_spire.sh` - Comprehensive diagnostic script
- `Dockerfile` - Container image definition

## Security Considerations

1. **Host Filesystem Access**: Pods have access to host SPIRE socket via hostPath - acceptable for demo, use DaemonSet pattern in production
2. **Sudo Requirements**: Scripts require sudo for Minikube none driver and system configuration
3. **Image Pull Policy**: Using imagePullPolicy=Never prevents accidental external image pulls
4. **Read-Only Mounts**: SPIRE Agent binary mounted read-only to prevent tampering
5. **Network Isolation**: Flannel provides basic pod network isolation
6. **Certificate Validation**: mTLS demo enforces mutual certificate verification

## Performance Notes

- **Cluster Startup**: 2-3 minutes for Minikube with none driver
- **Pod Scheduling**: Near-instant on single-node cluster
- **SVID Fetch**: < 1 second for initial fetch
- **Network Overhead**: Minimal with Flannel VXLAN on single node

## Next Steps

1. **Multi-Pod Communication**: Deploy client and server pods for pod-to-pod mTLS
2. **SVID Rotation**: Implement automatic certificate rotation for long-running pods
3. **SPIRE Controller Manager**: Migrate to Kubernetes-native SPIRE integration
4. **Multi-Node Support**: Extend to multi-node cluster with SPIRE Agent DaemonSet
5. **Monitoring**: Add Prometheus metrics for SPIRE operations

## References

- [SPIRE Documentation](https://spiffe.io/docs/latest/spire/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Flannel CNI](https://github.com/flannel-io/flannel)
- [CNI Plugins](https://github.com/containernetworking/plugins)
