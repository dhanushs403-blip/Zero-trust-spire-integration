#!/bin/bash

#############################################
# Complete Kubernetes Setup Script
#############################################
# Purpose: Automated setup of Kubernetes cluster with SPIRE integration
# Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 7.1, 7.2
#
# This script performs a complete setup of a Kubernetes cluster using Minikube
# with the 'none' driver, which runs Kubernetes directly on the host without
# VM isolation. This is required for SPIRE integration as it allows pods to
# access the host's SPIRE Agent socket via hostPath volume mounts.
#
# Usage:
#   sudo ./complete_k8s_setup.sh
#
# Prerequisites:
#   - Ubuntu 22.04 LTS
#   - Root/sudo access
#   - Internet connection for downloading CNI plugins
#   - Minikube and kubectl installed
#
# Exit Codes:
#   0 - Success: Cluster is ready with CNI networking
#   1 - Failure: Setup failed at some step (see error messages)
#
# Steps Performed:
#   1. Enhanced cleanup with edge case handling
#   2. Apply kernel security fix for Ubuntu 22.04
#   3. Install prerequisites (conntrack, socat)
#   4. Install CNI plugins with robust download and validation
#   5. Start Minikube with none driver
#   6. Apply Flannel CNI configuration
#   7. Ensure kubectl access is properly configured
#   8. Comprehensive node readiness verification
#############################################

echo "=========================================="
echo "   Complete Minikube 'None' Driver Setup"
echo "=========================================="
echo ""

#############################################
# Step 1: Enhanced Cleanup with Edge Case Handling
# Requirement: 1.1, 7.1
#############################################
# This step ensures a clean slate by:
# - Stopping running Minikube and kubelet processes
# - Deleting existing Minikube clusters
# - Removing all Minikube-related directories
# - Verifying cleanup completed successfully
#
# This prevents conflicts from previous installations
# and ensures the setup starts from a known state.
#############################################
echo "[1/8] Complete cleanup with process checks..."

# Check for running Minikube processes
if pgrep -f "minikube" > /dev/null; then
    echo "  Stopping running Minikube processes..."
    echo "1" | sudo -S minikube stop 2>/dev/null || true
    sleep 2
fi

# Check for running kubelet
if pgrep -f "kubelet" > /dev/null; then
    echo "  Stopping kubelet service..."
    echo "1" | sudo -S systemctl stop kubelet 2>/dev/null || true
    sleep 1
fi

# Delete Minikube cluster
echo "  Deleting Minikube cluster..."
echo "1" | sudo -S minikube delete --all --purge 2>/dev/null || true

# Remove Minikube-related directories
echo "  Removing Minikube directories..."
echo "1" | sudo -S rm -rf ~/.minikube ~/.kube /tmp/juju-* /tmp/minikube* 2>/dev/null || true
echo "1" | sudo -S rm -rf /var/lib/minikube /etc/kubernetes 2>/dev/null || true
echo "1" | sudo -S rm -rf /var/lib/kubelet 2>/dev/null || true

# Verify cleanup completed
CLEANUP_SUCCESS=true
if [ -d "$HOME/.minikube" ] || [ -d "$HOME/.kube" ] || [ -d "/var/lib/minikube" ]; then
    echo "  ⚠️  Warning: Some directories still exist after cleanup"
    CLEANUP_SUCCESS=false
fi

if [ "$CLEANUP_SUCCESS" = true ]; then
    echo "✓ Cleanup complete and verified"
else
    echo "✓ Cleanup complete (with warnings)"
fi

#############################################
# Step 2: Apply Kernel Security Fix
# Requirement: 1.1
#############################################
# Ubuntu 22.04 has a kernel security feature that prevents
# Minikube from working correctly with the 'none' driver.
# This sets fs.protected_regular=0 to allow Minikube to
# create and manage files in shared directories.
#
# Note: This is required for Minikube none driver to function
#############################################
echo ""
echo "[2/8] Applying kernel security fix..."
echo "1" | sudo -S sysctl fs.protected_regular=0
echo "✓ Kernel fix applied"

#############################################
# Step 3: Install Prerequisites
# Requirement: 6.2
#############################################
# Install required packages for Kubernetes networking:
# - conntrack: Connection tracking for iptables (required by kube-proxy)
# - socat: Socket relay utility (required by kubectl port-forward)
#
# These packages are essential for Kubernetes networking to function
#############################################
echo ""
echo "[3/8] Installing prerequisites..."
echo "1" | sudo -S apt-get install -y conntrack socat >/dev/null 2>&1
echo "✓ Prerequisites installed"

#############################################
# Step 4: Install CNI Plugins
# Requirement: 1.2, 1.3, 7.1
#############################################
# CNI (Container Network Interface) plugins are required for
# pod networking in Kubernetes. This step:
# - Downloads CNI plugins from GitHub releases
# - Validates the download (file size and gzip format)
# - Extracts plugins to /opt/cni/bin
# - Verifies all required binaries are present
#
# The robust installation process prevents issues with
# downloading error pages instead of the actual archive.
#############################################
echo ""
echo "[4/8] Installing CNI plugins..."

# Check if fix_cni_manual.sh exists
if [ ! -f "./fix_cni_manual.sh" ]; then
    echo "❌ Error: fix_cni_manual.sh not found in current directory"
    exit 1
fi

# Make the script executable
chmod +x ./fix_cni_manual.sh

# Call the improved CNI download script
if ! ./fix_cni_manual.sh --install-only; then
    echo "❌ Error: CNI installation failed"
    exit 1
fi

# Verify CNI binaries after installation
echo "  Verifying CNI binaries..."
REQUIRED_BINARIES=("bridge" "host-local" "loopback" "portmap" "bandwidth" "tuning" "firewall")
MISSING_BINARIES=()

for binary in "${REQUIRED_BINARIES[@]}"; do
    if [ ! -f "/opt/cni/bin/$binary" ]; then
        MISSING_BINARIES+=("$binary")
    fi
done

if [ ${#MISSING_BINARIES[@]} -gt 0 ]; then
    echo "❌ Error: Missing CNI binaries: ${MISSING_BINARIES[*]}"
    echo "  Installed binaries:"
    ls -la /opt/cni/bin/ 2>/dev/null || echo "  Directory /opt/cni/bin does not exist"
    exit 1
fi

echo "✓ CNI plugins installed and verified (${#REQUIRED_BINARIES[@]} binaries)"

#############################################
# Step 5: Start Minikube with None Driver
# Requirement: 1.1, 2.1
#############################################
# Start Minikube with the 'none' driver, which runs Kubernetes
# directly on the host without VM isolation. This is required
# for SPIRE integration as it allows:
# - Direct host filesystem access for SPIRE socket mounting
# - Docker label-based workload attestation
# - Pods to access host resources via hostPath volumes
#
# The pod network CIDR is set to 10.244.0.0/16 for Flannel CNI.
#############################################
echo ""
echo "[5/8] Starting Minikube (this takes 2-3 minutes)..."
echo "1" | sudo -S minikube start \
    --driver=none \
    --kubernetes-version=stable \
    --extra-config=kubeadm.pod-network-cidr=10.244.0.0/16

if [ $? -ne 0 ]; then
    echo "❌ Error: Minikube failed to start"
    exit 1
fi

# Fix permissions and copy kubeconfig immediately after Minikube starts
echo "  Configuring kubectl access for user $USER..."

# Wait a moment for Minikube to finish writing files
sleep 3

# Remove any existing .minikube directory for clean copy
rm -rf $HOME/.minikube 2>/dev/null || true

# Create .kube directory for user if it doesn't exist
mkdir -p $HOME/.kube

# Copy entire minikube directory structure from root to user
echo "1" | sudo -S cp -r /root/.minikube $HOME/ 2>/dev/null

# Copy kubeconfig from root to user
echo "1" | sudo -S cp -f /root/.kube/config $HOME/.kube/config 2>/dev/null

# Fix ownership of both directories
echo "1" | sudo -S chown -R $USER:$USER $HOME/.kube $HOME/.minikube 2>/dev/null

# Update kubeconfig to use user's home directory instead of /root
sed -i "s|/root/|$HOME/|g" $HOME/.kube/config 2>/dev/null || true

# Wait for control plane pods to start
echo "  Waiting for control plane pods to start..."
CONTROL_PLANE_READY=false
for i in {1..60}; do
    # Check if kube-apiserver container is running
    if echo "1" | sudo -S crictl pods 2>/dev/null | grep -q "kube-apiserver.*Ready"; then
        CONTROL_PLANE_READY=true
        break
    fi
    echo -n "."
    sleep 2
done

echo ""

if [ "$CONTROL_PLANE_READY" = false ]; then
    echo "⚠️  Warning: Control plane pods not ready yet, but continuing..."
fi

#############################################
# Step 6: Apply Flannel CNI Configuration
# Requirement: 1.3, 7.2
#############################################
# Flannel is a simple CNI plugin that provides pod networking.
# This step:
# - Waits for Kubernetes API to be ready
# - Cleans old CNI configurations
# - Applies Flannel manifest with retry logic
# - Verifies Flannel configuration file is created
# - Waits for Flannel pods to start running
#
# Flannel uses VXLAN backend and configures the 10.244.0.0/16
# network for pod-to-pod communication.
#############################################
echo ""
echo "[6/8] Applying Flannel CNI configuration..."

# Wait for kubectl to be fully ready
echo "  Waiting for Kubernetes API to be ready..."
KUBECTL_READY=false
for i in {1..60}; do
    # Try a simple kubectl command
    if kubectl get nodes --request-timeout=5s >/dev/null 2>&1; then
        KUBECTL_READY=true
        break
    fi
    echo -n "."
    sleep 3
done

echo ""

if [ "$KUBECTL_READY" = false ]; then
    echo "❌ Error: Kubernetes API not ready after 180 seconds"
    echo ""
    echo "Diagnostic Information:"
    echo "  Checking kubectl config..."
    ls -la $HOME/.kube/config 2>&1 || echo "    Config file not found"
    echo ""
    echo "  Checking control plane containers..."
    echo "1" | sudo -S crictl pods 2>&1 | grep kube-system || echo "    No control plane pods found"
    echo ""
    echo "  Checking Docker containers..."
    docker ps -a 2>&1 | grep kube || echo "    No kube containers found"
    echo ""
    echo "  Checking kubelet status..."
    echo "1" | sudo -S systemctl status kubelet --no-pager -l 2>&1 | head -20
    echo ""
    echo "  Recent kubelet logs:"
    echo "1" | sudo -S journalctl -u kubelet -n 30 --no-pager 2>&1 | tail -20
    exit 1
fi

# Clean old CNI configs
echo "1" | sudo -S rm -rf /etc/cni/net.d/* 2>/dev/null || true

# Apply Flannel with retry logic
echo "  Applying Flannel manifest..."
FLANNEL_APPLIED=false
MAX_APPLY_RETRIES=5

for i in $(seq 1 $MAX_APPLY_RETRIES); do
    if kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml >/dev/null 2>&1; then
        FLANNEL_APPLIED=true
        echo "  ✓ Flannel manifest applied successfully"
        break
    fi
    echo "  Retry $i/$MAX_APPLY_RETRIES..."
    sleep 5
done

if [ "$FLANNEL_APPLIED" = false ]; then
    echo "❌ Error: Failed to apply Flannel configuration after $MAX_APPLY_RETRIES attempts"
    echo "  Checking kubectl connectivity..."
    kubectl cluster-info 2>&1 || true
    exit 1
fi

# Verify Flannel configuration file is created
echo "  Verifying Flannel CNI configuration..."
FLANNEL_CONFIG_READY=false
for i in {1..30}; do
    if [ -f "/etc/cni/net.d/10-flannel.conflist" ]; then
        FLANNEL_CONFIG_READY=true
        break
    fi
    sleep 2
done

if [ "$FLANNEL_CONFIG_READY" = true ]; then
    echo "  ✓ Flannel CNI configuration file created"
    
    # Validate configuration file content
    if grep -q "flannel" /etc/cni/net.d/10-flannel.conflist 2>/dev/null; then
        echo "  ✓ Flannel configuration content validated"
    else
        echo "  ⚠️  Warning: Flannel configuration file exists but content may be invalid"
    fi
else
    echo "  ⚠️  Warning: Flannel configuration file not found at /etc/cni/net.d/10-flannel.conflist"
    echo "  Listing CNI configuration directory:"
    ls -la /etc/cni/net.d/ 2>/dev/null || echo "    Directory does not exist"
fi

# Wait for Flannel pods with enhanced retry logic
echo "  Waiting for Flannel pods to start..."
FLANNEL_READY=false
MAX_FLANNEL_WAIT=60  # 60 iterations * 2 seconds = 120 seconds

for i in $(seq 1 $MAX_FLANNEL_WAIT); do
    # Check if Flannel pods exist
    FLANNEL_POD_COUNT=$(kubectl get pods -n kube-flannel --no-headers 2>/dev/null | wc -l)
    
    if [ "$FLANNEL_POD_COUNT" -eq 0 ]; then
        # Pods not created yet
        echo -n "."
        sleep 2
        continue
    fi
    
    # Check if any Flannel pods are running
    RUNNING_PODS=$(kubectl get pods -n kube-flannel -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Running" | wc -l)
    
    if [ "$RUNNING_PODS" -gt 0 ]; then
        FLANNEL_READY=true
        echo ""
        echo "  ✓ Flannel pods are running ($RUNNING_PODS pod(s))"
        break
    fi
    
    # Check for pod errors
    FAILED_PODS=$(kubectl get pods -n kube-flannel -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o "Failed" | wc -l)
    if [ "$FAILED_PODS" -gt 0 ]; then
        echo ""
        echo "  ⚠️  Warning: Some Flannel pods are in Failed state"
        kubectl get pods -n kube-flannel 2>/dev/null || true
    fi
    
    echo -n "."
    sleep 2
done

echo ""

if [ "$FLANNEL_READY" = false ]; then
    echo "  ⚠️  Warning: Flannel pods not running after $((MAX_FLANNEL_WAIT * 2)) seconds"
    echo "  Current Flannel pod status:"
    kubectl get pods -n kube-flannel 2>/dev/null || echo "    Failed to get pod status"
    echo "  Continuing with setup, but node may not become Ready..."
fi

echo "✓ Flannel CNI configuration completed"

#############################################
# Step 7: Ensure kubectl Access
# Requirement: 6.4
#############################################
# When Minikube runs with the 'none' driver as root, the
# kubeconfig is created in /root/.kube. This step:
# - Copies .minikube directory from root to user home
# - Copies kubeconfig from root to user home
# - Fixes ownership for the current user
# - Updates paths in kubeconfig to use user's home directory
#
# This allows the non-root user to run kubectl commands.
#############################################
echo ""
echo "[7/8] Ensuring kubectl access..."
# Ensure minikube directory and kubeconfig are copied and accessible
rm -rf $HOME/.minikube 2>/dev/null || true
echo "1" | sudo -S cp -r /root/.minikube $HOME/ 2>/dev/null
echo "1" | sudo -S cp -f /root/.kube/config $HOME/.kube/config 2>/dev/null
echo "1" | sudo -S chown -R $USER:$USER $HOME/.kube $HOME/.minikube 2>/dev/null
# Update kubeconfig paths
sed -i "s|/root/|$HOME/|g" $HOME/.kube/config 2>/dev/null || true
echo "✓ kubectl access configured"

#############################################
# Step 8: Comprehensive Node Readiness Verification
# Requirement: 1.4, 1.5, 7.2
#############################################
# This step verifies the Kubernetes node is fully ready:
# - Polls node status with timeout (120 seconds)
# - Checks for specific NotReady reasons
# - Verifies CNI pods are running
# - Displays node conditions summary
#
# If the node doesn't become Ready within the timeout,
# comprehensive diagnostic information is displayed to
# help troubleshoot the issue.
#############################################
echo ""
echo "[8/8] Verifying node readiness..."

# Polling loop with timeout for node Ready status
NODE_READY=false
TIMEOUT=120
ELAPSED=0
CHECK_INTERVAL=5

echo "  Waiting for node to become Ready (timeout: ${TIMEOUT}s)..."
while [ $ELAPSED -lt $TIMEOUT ]; do
    # Get node Ready status
    NODE_STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    
    if [ "$NODE_STATUS" == "True" ]; then
        NODE_READY=true
        break
    fi
    
    # Check for specific NotReady reasons every 30 seconds
    if [ $((ELAPSED % 30)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        NODE_REASON=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null)
        NODE_MESSAGE=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
        
        if [ -n "$NODE_REASON" ] && [ "$NODE_REASON" != "KubeletReady" ]; then
            echo ""
            echo "  Node not ready: $NODE_REASON"
            if [ -n "$NODE_MESSAGE" ]; then
                echo "  Message: $NODE_MESSAGE"
            fi
            echo -n "  Continuing to wait..."
        fi
    fi
    
    echo -n "."
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

echo ""

if [ "$NODE_READY" = true ]; then
    echo "✓ Node is Ready"
    
    # Verify CNI pods are running before declaring success
    echo "  Verifying CNI pods are running..."
    CNI_PODS_RUNNING=0
    CNI_PODS_TOTAL=0
    
    # Get CNI pod counts
    if kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep -q .; then
        CNI_PODS_TOTAL=$(kubectl get pods -n kube-flannel --no-headers 2>/dev/null | wc -l)
        CNI_PODS_RUNNING=$(kubectl get pods -n kube-flannel --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    fi
    
    if [ "$CNI_PODS_RUNNING" -gt 0 ]; then
        echo "✓ CNI pods are running ($CNI_PODS_RUNNING/$CNI_PODS_TOTAL pod(s))"
        
        # Additional check: verify all CNI pods are ready
        CNI_PODS_READY=$(kubectl get pods -n kube-flannel -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -c "True" || echo "0")
        
        if [ "$CNI_PODS_READY" -eq "$CNI_PODS_RUNNING" ]; then
            echo "✓ All CNI pods are ready"
        else
            echo "⚠️  Warning: Some CNI pods are running but not ready ($CNI_PODS_READY/$CNI_PODS_RUNNING ready)"
        fi
    else
        echo "⚠️  Warning: No CNI pods in Running state (found $CNI_PODS_TOTAL pod(s))"
        echo "  CNI pod status:"
        kubectl get pods -n kube-flannel 2>/dev/null || echo "    Failed to get pod status"
    fi
    
    # Display final node status
    echo ""
    echo "Final Node Status:"
    kubectl get nodes -o wide 2>/dev/null || kubectl get nodes 2>/dev/null
    
    # Display node conditions summary
    echo ""
    echo "Node Conditions Summary:"
    kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.conditions[*]}  {.type}={.status} ({.reason}){"\n"}{end}{end}' 2>/dev/null || echo "  Failed to get node conditions"
    
    echo ""
    echo "=========================================="
    echo "   ✅ Setup Complete!"
    echo "=========================================="
    echo "Kubernetes cluster is ready with CNI networking"
    echo "Now run: ./run_k8s_demo.sh"
    exit 0
else
    echo "❌ Node failed to become Ready within ${TIMEOUT} seconds"
    echo ""
    echo "=========================================="
    echo "   Diagnostic Information"
    echo "=========================================="
    
    # Display node status
    echo ""
    echo "1. Node Status:"
    echo "   ------------"
    kubectl get nodes -o wide 2>/dev/null || kubectl get nodes 2>/dev/null || echo "   Failed to get node status"
    
    # Display detailed node conditions
    echo ""
    echo "2. Node Conditions (detailed):"
    echo "   ---------------------------"
    kubectl describe nodes 2>/dev/null | grep -A 15 "Conditions:" || echo "   Failed to get node conditions"
    
    # Check kubelet logs for errors
    echo ""
    echo "3. Kubelet Logs (last 30 lines with errors):"
    echo "   -----------------------------------------"
    if echo "1" | sudo -S journalctl -u kubelet -n 50 --no-pager 2>/dev/null | grep -i "error\|fail\|fatal" | tail -30 | grep -q .; then
        echo "1" | sudo -S journalctl -u kubelet -n 50 --no-pager 2>/dev/null | grep -i "error\|fail\|fatal" | tail -30
    else
        echo "   No recent errors found in kubelet logs"
        echo ""
        echo "   Last 20 kubelet log lines:"
        echo "1" | sudo -S journalctl -u kubelet -n 20 --no-pager 2>/dev/null || echo "   Failed to get kubelet logs"
    fi
    
    # Check CNI pods status
    echo ""
    echo "4. CNI Pod Status:"
    echo "   ---------------"
    if kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep -q .; then
        kubectl get pods -n kube-flannel -o wide 2>/dev/null
        
        # Show events for failed/pending CNI pods
        echo ""
        echo "   CNI Pod Events:"
        for pod in $(kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep -v "Running" | awk '{print $1}'); do
            echo ""
            echo "   Events for pod: $pod"
            kubectl describe pod "$pod" -n kube-flannel 2>/dev/null | grep -A 20 "Events:" || echo "     No events found"
        done
    else
        echo "   No CNI pods found in kube-flannel namespace"
    fi
    
    # Check CNI configuration
    echo ""
    echo "5. CNI Configuration:"
    echo "   ------------------"
    if [ -d "/etc/cni/net.d" ]; then
        echo "   CNI config files:"
        ls -la /etc/cni/net.d/ 2>/dev/null || echo "   Failed to list CNI config directory"
        
        if [ -f "/etc/cni/net.d/10-flannel.conflist" ]; then
            echo ""
            echo "   Flannel config content (first 10 lines):"
            head -10 /etc/cni/net.d/10-flannel.conflist 2>/dev/null || echo "   Failed to read Flannel config"
        fi
    else
        echo "   CNI config directory /etc/cni/net.d does not exist"
    fi
    
    # Check CNI binaries
    echo ""
    echo "6. CNI Binaries:"
    echo "   -------------"
    if [ -d "/opt/cni/bin" ]; then
        echo "   Installed CNI binaries:"
        ls -lh /opt/cni/bin/ 2>/dev/null | head -15 || echo "   Failed to list CNI binaries"
    else
        echo "   CNI binary directory /opt/cni/bin does not exist"
    fi
    
    # Check kubelet configuration
    echo ""
    echo "7. Kubelet Configuration:"
    echo "   ----------------------"
    echo "   Kubelet service status:"
    echo "1" | sudo -S systemctl status kubelet --no-pager -l 2>/dev/null | head -15 || echo "   Failed to get kubelet status"
    
    echo ""
    echo "=========================================="
    echo "   ❌ Setup Failed"
    echo "=========================================="
    echo ""
    echo "Troubleshooting Steps:"
    echo "  1. Check kubelet logs for NetworkPluginNotReady errors"
    echo "  2. Verify CNI binaries exist in /opt/cni/bin"
    echo "  3. Verify Flannel configuration in /etc/cni/net.d"
    echo "  4. Check if Flannel pods are running: kubectl get pods -n kube-flannel"
    echo "  5. Restart kubelet: sudo systemctl restart kubelet"
    echo "  6. Re-run this setup script to retry"
    echo ""
    exit 1
fi
