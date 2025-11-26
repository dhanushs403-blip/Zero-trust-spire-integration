# Kubernetes SPIRE Integration Operations Runbook

## Overview

This runbook provides operational procedures for managing, monitoring, and troubleshooting the Kubernetes SPIRE integration. It covers verification of successful deployments, manual testing commands, recovery procedures for common failures, and monitoring guidance.

**Requirements Covered:** 7.1, 7.2, 7.3, 7.4, 7.5

---

## Table of Contents

1. [Verification Procedures](#verification-procedures)
2. [Manual Testing Commands](#manual-testing-commands)
3. [Recovery Procedures](#recovery-procedures)
4. [Monitoring and Logging](#monitoring-and-logging)
5. [Maintenance Operations](#maintenance-operations)
6. [Emergency Procedures](#emergency-procedures)

---

## Verification Procedures

### 1. Verify Successful Cluster Setup

After running `complete_k8s_setup.sh`, verify the cluster is ready:

```bash
# Check Minikube status
minikube status

# Expected output:
# host: Running
# kubelet: Running
# apiserver: Running
# kubeconfig: Configured
```

```bash
# Check node status
kubectl get nodes

# Expected output:
# NAME   STATUS   ROLES           AGE   VERSION
# vso    Ready    control-plane   Xm    vX.XX.X
```

```bash
# Verify node conditions
kubectl describe nodes | grep -A 10 "Conditions:"

# All conditions should show status=True for:
# - Ready
# - MemoryPressure=False
# - DiskPressure=False
# - PIDPressure=False
# - NetworkReady (or no NetworkPluginNotReady)
```

```bash
# Check CNI plugins installed
ls -la /opt/cni/bin/

# Should contain at least:
# - bridge
# - host-local
# - loopback
# - portmap
# - bandwidth
# - tuning
# - firewall
```

```bash
# Check Flannel pods
kubectl get pods -n kube-flannel

# All pods should be Running
# NAME                    READY   STATUS    RESTARTS   AGE
# kube-flannel-ds-xxxxx   1/1     Running   0          Xm
```

**Success Criteria:**
- ✅ Node status is "Ready"
- ✅ All CNI binaries present in /opt/cni/bin
- ✅ Flannel pods are Running
- ✅ No NetworkPluginNotReady errors in kubelet logs

### 2. Verify SPIRE Integration

Before deploying applications, verify SPIRE is properly configured:

```bash
# Check SPIRE Server process
pgrep -a spire-server

# Should show: <PID> /opt/spire/bin/spire-server run -config ...
```

```bash
# Check SPIRE Agent process
pgrep -a spire-agent

# Should show: <PID> /opt/spire/bin/spire-agent run -config ...
```

```bash
# Verify SPIRE Agent socket exists
ls -la /tmp/spire-agent/public/api.sock

# Should show: srwxr-xr-x ... /tmp/spire-agent/public/api.sock
```

```bash
# Test socket connectivity
sudo /opt/spire/bin/spire-agent api fetch x509 -socketPath /tmp/spire-agent/public/api.sock

# Should return SPIFFE ID information (may show "no identity issued" if no workload registered yet)
```

```bash
# List SPIRE Agent registrations
sudo /opt/spire/bin/spire-server agent list

# Should show at least one agent with SPIFFE ID
```

```bash
# List workload registrations
sudo /opt/spire/bin/spire-server entry show

# Should show registered workloads with selectors
```

**Success Criteria:**
- ✅ SPIRE Server and Agent processes running
- ✅ Socket exists and is accessible
- ✅ Agent is registered with SPIRE Server
- ✅ Workload entries exist with Kubernetes selectors

### 3. Verify Application Deployment

After running `run_k8s_demo.sh`, verify the application is working:

```bash
# Check deployment status
kubectl get deployment mtls-app

# Expected output:
# NAME       READY   UP-TO-DATE   AVAILABLE   AGE
# mtls-app   1/1     1            1           Xm
```

```bash
# Check pod status
kubectl get pods -l app=mtls-demo

# Expected output:
# NAME                        READY   STATUS    RESTARTS   AGE
# mtls-app-xxxxxxxxxx-xxxxx   1/1     Running   0          Xm
```

```bash
# Verify pod is on correct node
kubectl get pods -l app=mtls-demo -o wide

# Should show node name (typically "vso" for Minikube none driver)
```

```bash
# Check pod logs for SVID fetch success
kubectl logs -l app=mtls-demo | grep -E "Successfully ran fetch command|SVID files found|mTLS Server listening"

# Should show:
# ✅ Successfully ran fetch command
# ✅ SVID files found on disk: svid.0.pem, svid.0.key, bundle.0.pem
# [Server] Secure mTLS Server listening on 9999
```

```bash
# Verify volume mounts
kubectl describe pod -l app=mtls-demo | grep -A 5 "Mounts:"

# Should show:
# - /tmp/spire-agent/public/api.sock (socket)
# - /opt/spire/bin/spire-agent (binary, read-only)
```

**Success Criteria:**
- ✅ Deployment shows 1/1 ready
- ✅ Pod is in Running state
- ✅ Pod logs show successful SVID fetch
- ✅ mTLS server started on port 9999
- ✅ No errors in pod logs

---

## Manual Testing Commands

### Test SVID Fetch from Pod

```bash
# Get pod name
POD_NAME=$(kubectl get pods -l app=mtls-demo -o jsonpath='{.items[0].metadata.name}')

# Exec into pod
kubectl exec -it $POD_NAME -- /bin/bash

# Inside pod: Manually fetch SVID
/opt/spire/bin/spire-agent api fetch x509 -write /tmp/test -socketPath /tmp/spire-agent/public/api.sock

# Verify files created
ls -la /tmp/test/
# Should show: svid.0.pem, svid.0.key, bundle.0.pem

# Check certificate details
openssl x509 -in /tmp/test/svid.0.pem -text -noout | grep -A 2 "Subject Alternative Name"
# Should show: URI:spiffe://example.org/k8s-workload

# Exit pod
exit
```

### Test Workload Attestation

```bash
# Check SPIRE Agent logs for attestation events
sudo journalctl -u spire-agent -n 100 --no-pager | grep -i "attest"

# Should show attestation attempts and successes for the pod
```

```bash
# Verify workload registration matches pod
sudo /opt/spire/bin/spire-server entry show -spiffeID spiffe://example.org/k8s-workload

# Check selectors match pod labels:
# - docker:label:io.kubernetes.container.name=mtls-app
# - docker:label:io.kubernetes.pod.namespace=default
```

### Test Pod Network Connectivity

```bash
# Check pod IP address
kubectl get pods -l app=mtls-demo -o wide

# Test connectivity from host to pod
POD_IP=$(kubectl get pods -l app=mtls-demo -o jsonpath='{.items[0].status.podIP}')
ping -c 3 $POD_IP

# Should receive responses
```

```bash
# Test DNS resolution from pod
kubectl exec -l app=mtls-demo -- nslookup kubernetes.default

# Should resolve to cluster IP
```

### Test mTLS Server

```bash
# Port-forward to access mTLS server
kubectl port-forward -l app=mtls-demo 9999:9999 &

# Test connection (will fail without client cert, but verifies server is listening)
curl -k https://localhost:9999
# Expected: SSL error (no client certificate)

# Stop port-forward
kill %1
```

### Verify Certificate Rotation

```bash
# Check current certificate expiration
kubectl exec -l app=mtls-demo -- openssl x509 -in /app/svid.0.pem -noout -enddate

# Wait for rotation period (default: 1 hour)
# Re-check expiration - should show new certificate
```

---

## Recovery Procedures

### Recovery Procedure 1: Node NotReady

**Symptoms:**
- `kubectl get nodes` shows NotReady
- Kubelet logs show "NetworkPluginNotReady"

**Diagnosis:**
```bash
# Check node status
kubectl get nodes
kubectl describe nodes | grep -A 10 "Conditions:"

# Check kubelet logs
sudo journalctl -u kubelet -n 50 --no-pager | grep -i "error\|network"

# Check CNI installation
ls -la /opt/cni/bin/
ls -la /etc/cni/net.d/

# Check Flannel pods
kubectl get pods -n kube-flannel
```

**Recovery Steps:**
1. Verify CNI plugins are installed:
   ```bash
   ls /opt/cni/bin/ | wc -l
   # Should be > 10
   ```

2. If CNI plugins missing, reinstall:
   ```bash
   sudo ./fix_cni_manual.sh
   ```

3. If Flannel pods not running, reapply:
   ```bash
   kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
   ```

4. Restart kubelet:
   ```bash
   sudo systemctl restart kubelet
   ```

5. Wait for node to become Ready (up to 120 seconds):
   ```bash
   kubectl get nodes -w
   ```

**Verification:**
```bash
kubectl get nodes
# Should show: Ready

kubectl get pods -n kube-flannel
# All pods should be Running
```

### Recovery Procedure 2: SPIRE Socket Inaccessible

**Symptoms:**
- Pod logs show "socket not found" or permission errors
- SVID fetch fails

**Diagnosis:**
```bash
# Check socket exists
ls -la /tmp/spire-agent/public/api.sock

# Check SPIRE Agent process
pgrep -a spire-agent

# Check socket permissions
stat /tmp/spire-agent/public/api.sock

# Test socket from host
sudo /opt/spire/bin/spire-agent api fetch x509 -socketPath /tmp/spire-agent/public/api.sock
```

**Recovery Steps:**
1. If socket doesn't exist, check SPIRE Agent is running:
   ```bash
   pgrep spire-agent || echo "SPIRE Agent not running"
   ```

2. If SPIRE Agent not running, start it:
   ```bash
   cd /opt/spire
   sudo ./bin/spire-agent run -config conf/agent/agent.conf &
   ```

3. Wait for socket to be created:
   ```bash
   for i in {1..30}; do
     [ -S /tmp/spire-agent/public/api.sock ] && break
     sleep 1
   done
   ```

4. If socket exists but not accessible, check permissions:
   ```bash
   sudo chmod 777 /tmp/spire-agent/public/api.sock
   ```

5. Restart pod to retry:
   ```bash
   kubectl delete pod -l app=mtls-demo
   # Deployment will recreate pod automatically
   ```

**Verification:**
```bash
# Check socket exists and is accessible
ls -la /tmp/spire-agent/public/api.sock

# Check new pod logs
kubectl logs -l app=mtls-demo --tail=20
# Should show successful SVID fetch
```

### Recovery Procedure 3: Pod Stuck in Pending/ContainerCreating

**Symptoms:**
- Pod doesn't reach Running state
- `kubectl get pods` shows Pending or ContainerCreating

**Diagnosis:**
```bash
# Check pod status
kubectl get pods -l app=mtls-demo

# Check pod events
kubectl describe pod -l app=mtls-demo | grep -A 20 "Events:"

# Check node resources
kubectl describe nodes | grep -A 5 "Allocated resources:"

# Check if image is loaded
minikube image ls | grep mtls-demo-image
```

**Recovery Steps:**
1. If image not found:
   ```bash
   # Build image
   docker build -t mtls-demo-image:latest .
   
   # Load into Minikube
   minikube image load mtls-demo-image:latest
   ```

2. If volume mount issues:
   ```bash
   # Verify host paths exist
   ls -la /tmp/spire-agent/public/api.sock
   ls -la /opt/spire/bin/spire-agent
   ```

3. If node not ready:
   ```bash
   # Follow "Node NotReady" recovery procedure above
   ```

4. Delete and recreate pod:
   ```bash
   kubectl delete pod -l app=mtls-demo
   # Wait for new pod
   kubectl wait --for=condition=ready pod -l app=mtls-demo --timeout=120s
   ```

**Verification:**
```bash
kubectl get pods -l app=mtls-demo
# Should show: Running

kubectl logs -l app=mtls-demo
# Should show successful startup
```

### Recovery Procedure 4: SVID Fetch Fails in Pod

**Symptoms:**
- Pod logs show SVID fetch errors
- Certificate files not created

**Diagnosis:**
```bash
# Check pod logs
kubectl logs -l app=mtls-demo

# Check workload registration
sudo /opt/spire/bin/spire-server entry show -spiffeID spiffe://example.org/k8s-workload

# Check SPIRE Agent logs
sudo journalctl -u spire-agent -n 50 --no-pager

# Exec into pod to debug
kubectl exec -it -l app=mtls-demo -- /bin/bash
ls -la /tmp/spire-agent/public/
ls -la /opt/spire/bin/
```

**Recovery Steps:**
1. Verify workload is registered:
   ```bash
   sudo /opt/spire/bin/spire-server entry show
   ```

2. If registration missing or incorrect, re-register:
   ```bash
   # Delete old registration
   sudo /opt/spire/bin/spire-server entry delete -spiffeID spiffe://example.org/k8s-workload
   
   # Get agent ID
   AGENT_ID=$(sudo /opt/spire/bin/spire-server agent list | grep "SPIFFE ID" | awk '{print $4}' | head -n 1)
   
   # Create new registration
   sudo /opt/spire/bin/spire-server entry create \
     -parentID "$AGENT_ID" \
     -spiffeID spiffe://example.org/k8s-workload \
     -selector docker:label:io.kubernetes.container.name=mtls-app \
     -selector docker:label:io.kubernetes.pod.namespace=default
   ```

3. Verify pod labels match selectors:
   ```bash
   kubectl get pod -l app=mtls-demo -o jsonpath='{.items[0].metadata.labels}'
   # Should include: app=mtls-demo
   ```

4. Restart pod to retry SVID fetch:
   ```bash
   kubectl delete pod -l app=mtls-demo
   ```

**Verification:**
```bash
# Check new pod logs
kubectl logs -l app=mtls-demo | grep "SVID"
# Should show: ✅ Successfully ran fetch command
#              ✅ SVID files found on disk
```

### Recovery Procedure 5: Complete Cluster Reset

**When to Use:**
- Multiple components failing
- Cluster in inconsistent state
- After major configuration changes

**Steps:**
1. Stop all running processes:
   ```bash
   sudo minikube stop
   sudo systemctl stop kubelet
   ```

2. Clean up completely:
   ```bash
   sudo minikube delete --all --purge
   sudo rm -rf ~/.minikube ~/.kube /var/lib/minikube /etc/kubernetes
   ```

3. Re-run complete setup:
   ```bash
   sudo ./complete_k8s_setup.sh
   ```

4. Verify cluster is ready:
   ```bash
   kubectl get nodes
   # Should show: Ready
   ```

5. Re-deploy application:
   ```bash
   sudo ./run_k8s_demo.sh
   ```

**Verification:**
```bash
# Run diagnostic script
sudo ./diagnose_k8s_spire.sh
# Should report: No issues found
```

---

## Monitoring and Logging

### Cluster Monitoring

**Check Cluster Health:**
```bash
# Overall cluster status
kubectl cluster-info

# Node status
kubectl get nodes -o wide

# System pods
kubectl get pods -n kube-system

# Resource usage
kubectl top nodes
kubectl top pods -A
```

**Monitor Kubelet:**
```bash
# Kubelet status
sudo systemctl status kubelet

# Kubelet logs (live)
sudo journalctl -u kubelet -f

# Kubelet logs (last 100 lines)
sudo journalctl -u kubelet -n 100 --no-pager

# Filter for errors
sudo journalctl -u kubelet -n 200 --no-pager | grep -i "error\|fail"
```

**Monitor CNI:**
```bash
# Flannel pod logs
kubectl logs -n kube-flannel -l app=flannel --tail=50

# Flannel pod status
kubectl get pods -n kube-flannel -o wide

# CNI configuration
cat /etc/cni/net.d/10-flannel.conflist
```

### SPIRE Monitoring

**Monitor SPIRE Server:**
```bash
# SPIRE Server process
pgrep -a spire-server

# SPIRE Server logs (if running as systemd service)
sudo journalctl -u spire-server -f

# SPIRE Server logs (if running in background)
# Check the log file specified in server.conf

# List agents
sudo /opt/spire/bin/spire-server agent list

# List entries
sudo /opt/spire/bin/spire-server entry show

# Server health check
sudo /opt/spire/bin/spire-server healthcheck
```

**Monitor SPIRE Agent:**
```bash
# SPIRE Agent process
pgrep -a spire-agent

# SPIRE Agent logs (if running as systemd service)
sudo journalctl -u spire-agent -f

# SPIRE Agent logs (if running in background)
# Check the log file specified in agent.conf

# Agent health check
sudo /opt/spire/bin/spire-agent healthcheck -socketPath /tmp/spire-agent/public/api.sock
```

**Monitor Workload Attestation:**
```bash
# Watch SPIRE Agent logs for attestation events
sudo journalctl -u spire-agent -f | grep -i "attest"

# Check for attestation errors
sudo journalctl -u spire-agent -n 200 --no-pager | grep -i "attest.*error"
```

### Application Monitoring

**Monitor Pod Status:**
```bash
# Watch pod status
kubectl get pods -l app=mtls-demo -w

# Pod events
kubectl get events --field-selector involvedObject.name=<pod-name> --sort-by='.lastTimestamp'

# Pod resource usage
kubectl top pod -l app=mtls-demo
```

**Monitor Application Logs:**
```bash
# Follow pod logs
kubectl logs -l app=mtls-demo -f

# Last 100 lines
kubectl logs -l app=mtls-demo --tail=100

# Logs from previous container (if pod restarted)
kubectl logs -l app=mtls-demo --previous

# Filter for errors
kubectl logs -l app=mtls-demo --tail=200 | grep -i "error\|fail\|exception"
```

**Monitor SVID Operations:**
```bash
# Check for SVID fetch in logs
kubectl logs -l app=mtls-demo | grep -i "svid\|fetch"

# Monitor certificate expiration
kubectl exec -l app=mtls-demo -- openssl x509 -in /app/svid.0.pem -noout -enddate

# Check for rotation events
kubectl logs -l app=mtls-demo | grep -i "rotat"
```

### Diagnostic Script

**Run Comprehensive Diagnostics:**
```bash
# Run diagnostic script
sudo ./diagnose_k8s_spire.sh

# Save diagnostic output to file
sudo ./diagnose_k8s_spire.sh > diagnostics-$(date +%Y%m%d-%H%M%S).log 2>&1
```

**Automated Monitoring:**
```bash
# Create monitoring script
cat > monitor.sh << 'EOF'
#!/bin/bash
while true; do
  echo "=== $(date) ==="
  echo "Node Status:"
  kubectl get nodes
  echo ""
  echo "Pod Status:"
  kubectl get pods -l app=mtls-demo
  echo ""
  echo "SPIRE Processes:"
  pgrep -a spire-server | head -1
  pgrep -a spire-agent | head -1
  echo ""
  sleep 60
done
EOF

chmod +x monitor.sh

# Run monitoring
./monitor.sh
```

### Log Retention and Rotation

**Kubelet Logs:**
```bash
# Configure journald retention (edit /etc/systemd/journald.conf)
sudo nano /etc/systemd/journald.conf
# Set: SystemMaxUse=1G
#      MaxRetentionSec=7day

# Restart journald
sudo systemctl restart systemd-journald
```

**Application Logs:**
```bash
# Kubernetes automatically rotates pod logs
# Default: 10MB per file, 5 files retained

# View log rotation settings
kubectl describe node | grep -A 5 "Container Runtime"
```

---

## Maintenance Operations

### Routine Maintenance

**Daily Checks:**
```bash
# Check cluster health
kubectl get nodes
kubectl get pods -A

# Check SPIRE processes
pgrep spire-server && echo "SPIRE Server: OK" || echo "SPIRE Server: DOWN"
pgrep spire-agent && echo "SPIRE Agent: OK" || echo "SPIRE Agent: DOWN"

# Check application
kubectl get pods -l app=mtls-demo
```

**Weekly Maintenance:**
```bash
# Review logs for errors
sudo journalctl -u kubelet --since "7 days ago" | grep -i "error" | wc -l
sudo journalctl -u spire-agent --since "7 days ago" | grep -i "error" | wc -l

# Check disk space
df -h /var/lib/kubelet
df -h /var/lib/minikube

# Review workload registrations
sudo /opt/spire/bin/spire-server entry show | grep "Entry ID" | wc -l
```

### Update Procedures

**Update CNI Plugins:**
```bash
# Update CNI_VERSION in fix_cni_manual.sh
nano fix_cni_manual.sh
# Change: CNI_VERSION="v1.4.0"

# Run installation
sudo ./fix_cni_manual.sh --install-only

# Restart kubelet
sudo systemctl restart kubelet

# Verify
kubectl get nodes
```

**Update Flannel:**
```bash
# Apply latest Flannel manifest
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait for rollout
kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel

# Verify
kubectl get pods -n kube-flannel
```

**Update Application:**
```bash
# Build new image
docker build -t mtls-demo-image:latest .

# Load into Minikube
minikube image load mtls-demo-image:latest

# Restart deployment
kubectl rollout restart deployment mtls-app

# Monitor rollout
kubectl rollout status deployment mtls-app

# Verify
kubectl logs -l app=mtls-demo --tail=50
```

### Backup Procedures

**Backup SPIRE Configuration:**
```bash
# Create backup directory
mkdir -p ~/spire-backups/$(date +%Y%m%d)

# Backup SPIRE Server config
sudo cp -r /opt/spire/conf/server ~/spire-backups/$(date +%Y%m%d)/

# Backup SPIRE Agent config
sudo cp -r /opt/spire/conf/agent ~/spire-backups/$(date +%Y%m%d)/

# Backup workload registrations
sudo /opt/spire/bin/spire-server entry show > ~/spire-backups/$(date +%Y%m%d)/entries.txt

# Backup agent list
sudo /opt/spire/bin/spire-server agent list > ~/spire-backups/$(date +%Y%m%d)/agents.txt
```

**Backup Kubernetes Configuration:**
```bash
# Backup deployment manifests
cp mtls-app.yaml ~/k8s-backups/$(date +%Y%m%d)/

# Export current deployment
kubectl get deployment mtls-app -o yaml > ~/k8s-backups/$(date +%Y%m%d)/mtls-app-current.yaml

# Backup kubeconfig
cp ~/.kube/config ~/k8s-backups/$(date +%Y%m%d)/kubeconfig
```

---

## Emergency Procedures

### Emergency Contact Information

**Escalation Path:**
1. Check this runbook for recovery procedures
2. Run diagnostic script: `sudo ./diagnose_k8s_spire.sh`
3. Review logs for error messages
4. Consult README-k8s-phase3.md troubleshooting section
5. If unresolved, escalate to senior engineer

### Critical Failure Scenarios

**Scenario 1: Complete Cluster Failure**

**Immediate Actions:**
1. Check if Minikube is running: `minikube status`
2. Check if kubelet is running: `sudo systemctl status kubelet`
3. If both down, run complete reset: `sudo ./complete_k8s_setup.sh`

**Scenario 2: SPIRE Server Failure**

**Immediate Actions:**
1. Check process: `pgrep spire-server`
2. If down, restart: `cd /opt/spire && sudo ./bin/spire-server run -config conf/server/server.conf &`
3. Verify: `sudo /opt/spire/bin/spire-server healthcheck`
4. Re-register workloads if needed

**Scenario 3: Data Loss**

**Immediate Actions:**
1. Stop all services
2. Restore from latest backup
3. Restart services in order: SPIRE Server → SPIRE Agent → Kubernetes → Application
4. Verify all components

### Post-Incident Procedures

**After Resolving an Incident:**

1. Document what happened:
   ```bash
   # Create incident report
   cat > incident-$(date +%Y%m%d-%H%M%S).md << EOF
   # Incident Report
   
   ## Date/Time: $(date)
   
   ## Symptoms:
   [Describe what was observed]
   
   ## Root Cause:
   [What caused the issue]
   
   ## Resolution:
   [Steps taken to resolve]
   
   ## Prevention:
   [How to prevent in future]
   EOF
   ```

2. Review logs for root cause
3. Update runbook if new issue discovered
4. Implement preventive measures
5. Test recovery procedure

---

## Quick Reference

### Essential Commands

```bash
# Cluster Status
kubectl get nodes
kubectl get pods -A
minikube status

# SPIRE Status
pgrep -a spire-server
pgrep -a spire-agent
ls -la /tmp/spire-agent/public/api.sock

# Application Status
kubectl get pods -l app=mtls-demo
kubectl logs -l app=mtls-demo --tail=20

# Diagnostics
sudo ./diagnose_k8s_spire.sh

# Recovery
sudo ./complete_k8s_setup.sh  # Full cluster reset
sudo ./run_k8s_demo.sh        # Redeploy application
```

### Common Issues Quick Fix

| Issue | Quick Fix |
|-------|-----------|
| Node NotReady | `sudo ./fix_cni_manual.sh` |
| SPIRE socket missing | Restart SPIRE Agent |
| Pod pending | `minikube image load mtls-demo-image:latest` |
| SVID fetch fails | Re-register workload |
| Cluster unresponsive | `sudo ./complete_k8s_setup.sh` |

---

## Appendix

### Log Locations

- **Kubelet logs:** `sudo journalctl -u kubelet`
- **SPIRE Server logs:** `sudo journalctl -u spire-server` or check server.conf log_file
- **SPIRE Agent logs:** `sudo journalctl -u spire-agent` or check agent.conf log_file
- **Pod logs:** `kubectl logs <pod-name>`
- **Flannel logs:** `kubectl logs -n kube-flannel -l app=flannel`

### Configuration Files

- **Minikube config:** `~/.minikube/`
- **Kubeconfig:** `~/.kube/config`
- **CNI config:** `/etc/cni/net.d/`
- **CNI binaries:** `/opt/cni/bin/`
- **SPIRE Server config:** `/opt/spire/conf/server/`
- **SPIRE Agent config:** `/opt/spire/conf/agent/`
- **Deployment manifest:** `mtls-app.yaml`

### Useful kubectl Commands

```bash
# Get all resources
kubectl get all -A

# Describe resource
kubectl describe <resource-type> <resource-name>

# Get resource YAML
kubectl get <resource-type> <resource-name> -o yaml

# Edit resource
kubectl edit <resource-type> <resource-name>

# Delete resource
kubectl delete <resource-type> <resource-name>

# Force delete pod
kubectl delete pod <pod-name> --force --grace-period=0

# Get events
kubectl get events --sort-by='.lastTimestamp'

# Port forward
kubectl port-forward <pod-name> <local-port>:<pod-port>

# Exec into pod
kubectl exec -it <pod-name> -- /bin/bash

# Copy files to/from pod
kubectl cp <pod-name>:/path/to/file ./local-file
kubectl cp ./local-file <pod-name>:/path/to/file
```

---

**Document Version:** 1.0  
**Last Updated:** $(date)  
**Maintained By:** DevOps Team
