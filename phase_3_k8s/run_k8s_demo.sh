#!/bin/bash

#############################################
# Kubernetes SPIRE Demo Orchestration Script
#############################################
# Purpose: Deploy and verify SPIRE mTLS demo application in Kubernetes
# Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5,
#               4.1, 4.2, 4.3, 4.4, 4.5, 5.1, 5.2, 5.3, 5.4, 5.5,
#               7.3, 7.4, 7.5
#
# This script orchestrates the complete deployment of the mTLS demo
# application to Kubernetes with SPIRE integration. It performs:
# - Pre-deployment validation checks
# - SPIRE Agent socket accessibility verification
# - Workload registration with Kubernetes selectors
# - Volume mount path validation
# - Application deployment with error handling
# - Pod log monitoring and verification
#
# Usage:
#   sudo ./run_k8s_demo.sh
#
# Prerequisites:
#   - Kubernetes cluster running and Ready (run complete_k8s_setup.sh first)
#   - SPIRE Server and Agent running on host
#   - Docker image mtls-demo-image:latest built
#   - SPIRE Agent socket at /tmp/spire-agent/public/api.sock
#
# Exit Codes:
#   0 - Success: Application deployed and verified
#   1 - Failure: Pre-deployment checks, deployment, or verification failed
#############################################

echo "=========================================="
echo "   Phase 3: SPIRE Kubernetes Demo"
echo "=========================================="

#############################################
# Setup Kubernetes Environment
#############################################
# Call setup_k8s.sh to verify environment and load Docker image
./setup_k8s.sh

# ========================================
# PRE-DEPLOYMENT VALIDATION CHECKS (Task 5.1)
# ========================================

echo "=========================================="
echo "Running pre-deployment validation checks..."
echo "=========================================="

# Check 1: Verify Kubernetes cluster is running and Ready
echo ""
echo "[1/5] Verifying Kubernetes cluster status..."
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ ERROR: Kubernetes cluster is not running"
    echo "Please ensure Minikube is started with: minikube start --driver=none"
    exit 1
fi
echo "✅ Kubernetes cluster is running"

# Check node status
NODE_STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$NODE_STATUS" != "True" ]; then
    echo "❌ ERROR: Kubernetes node is not Ready"
    echo "Current node status:"
    kubectl get nodes
    echo ""
    echo "Node conditions:"
    kubectl describe nodes | grep -A 10 "Conditions:"
    exit 1
fi
echo "✅ Kubernetes node is Ready"

# Check 2: Check SPIRE socket exists on host
echo ""
echo "[2/5] Checking SPIRE Agent socket..."
if [ ! -S /tmp/spire-agent/public/api.sock ]; then
    echo "❌ ERROR: SPIRE socket not found at /tmp/spire-agent/public/api.sock"
    echo "Make sure the SPIRE Agent is running on the host!"
    echo ""
    echo "To start SPIRE Agent, run:"
    echo "  cd /opt/spire && sudo ./bin/spire-agent run -config conf/agent/agent.conf &"
    exit 1
fi
echo "✅ SPIRE Agent socket exists"

# Check 3: Verify Docker image is loaded in Minikube
echo ""
echo "[3/5] Verifying Docker image is loaded in Minikube..."
if ! echo "1" | sudo -S minikube image ls 2>/dev/null | grep -q "mtls-demo-image:latest"; then
    echo "❌ ERROR: Docker image 'mtls-demo-image:latest' not found in Minikube"
    echo ""
    echo "To load the image, run:"
    echo "  sudo minikube image load mtls-demo-image:latest"
    echo ""
    echo "Or build and load it:"
    echo "  docker build -t mtls-demo-image:latest ."
    echo "  sudo minikube image load mtls-demo-image:latest"
    exit 1
fi
echo "✅ Docker image 'mtls-demo-image:latest' is loaded in Minikube"

# Check 4: Confirm SPIRE Server is healthy
echo ""
echo "[4/5] Checking SPIRE Server health..."
if ! pgrep -f "spire-server" > /dev/null; then
    echo "❌ ERROR: SPIRE Server process is not running"
    echo ""
    echo "To start SPIRE Server, run:"
    echo "  cd /opt/spire && sudo ./bin/spire-server run -config conf/server/server.conf &"
    exit 1
fi
echo "✅ SPIRE Server process is running"

# Verify SPIRE Server is responding
if ! echo "1" | sudo -S /opt/spire/bin/spire-server agent list &>/dev/null; then
    echo "❌ ERROR: SPIRE Server is not responding to commands"
    echo "The process is running but may not be healthy"
    exit 1
fi
echo "✅ SPIRE Server is responding to commands"

# Check 5: Confirm SPIRE Agent is healthy
echo ""
echo "[5/5] Checking SPIRE Agent health..."
if ! pgrep -f "spire-agent" > /dev/null; then
    echo "❌ ERROR: SPIRE Agent process is not running"
    echo ""
    echo "To start SPIRE Agent, run:"
    echo "  cd /opt/spire && sudo ./bin/spire-agent run -config conf/agent/agent.conf &"
    exit 1
fi
echo "✅ SPIRE Agent process is running"

# Test socket connectivity
if ! /opt/spire/bin/spire-agent healthcheck -socketPath /tmp/spire-agent/public/api.sock >/dev/null 2>&1; then
    echo "❌ ERROR: Cannot communicate with SPIRE Agent through socket"
    echo "The socket exists but the SPIRE Agent is not responding properly"
    exit 1
fi
echo "✅ SPIRE Agent is responding through socket"

echo ""
echo "=========================================="
echo "✅ All pre-deployment validation checks passed!"
echo "=========================================="

#############################################
# Verify SPIRE Agent Socket Accessibility
# Requirement: 2.1, 2.4, 7.3 (Subtask 3.3)
#############################################
# This section verifies that the SPIRE Agent socket:
# - Exists at the expected path
# - Has correct permissions
# - Is accessible and responding to API calls
#
# The socket must be accessible from the host for pods to
# use it via hostPath volume mounts.
#############################################
echo "=========================================="
echo "Verifying SPIRE Agent socket accessibility..."
echo "=========================================="

# Check socket exists
if [ ! -S /tmp/spire-agent/public/api.sock ]; then
    echo "❌ ERROR: SPIRE socket not found at /tmp/spire-agent/public/api.sock"
    echo "Make sure the SPIRE Agent is running on the host!"
    echo ""
    echo "To start SPIRE Agent, run:"
    echo "  cd /opt/spire && sudo ./bin/spire-agent run -config conf/agent/agent.conf &"
    exit 1
fi
echo "✅ SPIRE socket exists at /tmp/spire-agent/public/api.sock"

# Verify socket has correct permissions
SOCKET_PERMS=$(stat -c "%a" /tmp/spire-agent/public/api.sock 2>/dev/null || stat -f "%Lp" /tmp/spire-agent/public/api.sock 2>/dev/null)
echo "Socket permissions: $SOCKET_PERMS"

# Test socket connectivity by checking if SPIRE Agent is responding
echo "Testing socket connectivity..."
if ! /opt/spire/bin/spire-agent healthcheck -socketPath /tmp/spire-agent/public/api.sock >/dev/null 2>&1; then
    echo "❌ ERROR: Cannot communicate with SPIRE Agent through socket"
    echo "The socket exists but the SPIRE Agent is not responding properly"
    echo ""
    echo "Check SPIRE Agent status:"
    echo "  ps aux | grep spire-agent"
    echo "  sudo journalctl -u spire-agent -n 50"
    exit 1
fi
echo "✅ SPIRE Agent socket is accessible and responding"

#############################################
# Register Workload with Kubernetes Selectors
# Requirement: 3.1, 3.2, 3.4, 3.5 (Subtask 3.1, 3.2)
#############################################
# This section registers the Kubernetes workload with SPIRE Server:
# - Retrieves SPIRE Agent ID dynamically
# - Checks for and deletes duplicate registrations
# - Creates new registration with Kubernetes Docker label selectors
# - Validates registration was created successfully
#
# The selectors used are:
# - docker:label:io.kubernetes.container.name=mtls-app
# - docker:label:io.kubernetes.pod.namespace=default
#
# These selectors allow SPIRE Agent to identify and attest
# Kubernetes pods based on their Docker container labels.
#############################################
echo "=========================================="
echo "Registering workload with SPIRE Server..."
echo "=========================================="

# Retrieve SPIRE Agent ID dynamically (Subtask 3.1)
echo "Retrieving SPIRE Agent ID..."
AGENT_ID=$(echo "1" | sudo -S /opt/spire/bin/spire-server agent list | grep "SPIFFE ID" | awk '{print $4}' | head -n 1)

if [ -z "$AGENT_ID" ]; then
    echo "❌ ERROR: Could not retrieve SPIRE Agent ID"
    echo "Make sure the SPIRE Server is running and the agent is registered"
    exit 1
fi
echo "✅ Agent ID retrieved: $AGENT_ID"

# Add duplicate registration cleanup (Subtask 3.2)
SPIFFE_ID="spiffe://example.org/k8s-workload"
echo ""
echo "Checking for existing registrations with spiffeID: $SPIFFE_ID"

# List existing entries and check if our spiffeID exists
EXISTING_ENTRIES=$(echo "1" | sudo -S /opt/spire/bin/spire-server entry show -spiffeID "$SPIFFE_ID" 2>/dev/null)

if [ -n "$EXISTING_ENTRIES" ]; then
    echo "Found existing registration(s) for $SPIFFE_ID"
    echo "Deleting old entries..."
    
    # Delete the old entry
    if echo "1" | sudo -S /opt/spire/bin/spire-server entry delete -spiffeID "$SPIFFE_ID" 2>&1; then
        echo "✅ Successfully deleted old registration"
    else
        echo "⚠️  Warning: Could not delete old registration (may not exist)"
    fi
else
    echo "No existing registrations found for $SPIFFE_ID"
fi

# Create registration entry with Kubernetes selectors (Subtask 3.1)
echo ""
echo "Creating new workload registration with Kubernetes selectors..."
REGISTRATION_OUTPUT=$(echo "1" | sudo -S /opt/spire/bin/spire-server entry create \
    -parentID "$AGENT_ID" \
    -spiffeID "$SPIFFE_ID" \
    -selector docker:label:io.kubernetes.container.name:mtls-app \
    -selector docker:label:io.kubernetes.pod.namespace:default 2>&1)

# Add validation that registration was created successfully (Subtask 3.1)
if echo "$REGISTRATION_OUTPUT" | grep -q "Entry ID"; then
    ENTRY_ID=$(echo "$REGISTRATION_OUTPUT" | grep "Entry ID" | awk '{print $4}')
    echo "✅ Workload registration created successfully"
    echo "   Entry ID: $ENTRY_ID"
    echo "   SPIFFE ID: $SPIFFE_ID"
    echo "   Parent ID: $AGENT_ID"
    echo "   Selectors:"
    echo "     - docker:label:io.kubernetes.container.name:mtls-app"
    echo "     - docker:label:io.kubernetes.pod.namespace:default"
else
    echo "❌ ERROR: Failed to create workload registration"
    echo "Output: $REGISTRATION_OUTPUT"
    exit 1
fi

# Verify the registration exists
echo ""
echo "Verifying registration..."
if echo "1" | sudo -S /opt/spire/bin/spire-server entry show -spiffeID "$SPIFFE_ID" | grep -q "$SPIFFE_ID"; then
    echo "✅ Registration verified in SPIRE Server"
else
    echo "❌ ERROR: Registration not found in SPIRE Server after creation"
    exit 1
fi

#############################################
# Validate Volume Mount Paths Before Deployment
# Requirement: 2.2, 2.3, 4.4
#############################################
# This section validates that all required host paths exist
# before attempting deployment:
# - SPIRE Agent socket (/tmp/spire-agent/public/api.sock)
# - SPIRE Agent binary (/opt/spire/bin/spire-agent)
# - Deployment manifest has correct volume configuration
#
# This prevents deployment failures due to missing host paths.
#############################################
echo "=========================================="
echo "Validating volume mount paths..."
echo "=========================================="

# Verify SPIRE Agent socket exists on host
if [ ! -S /tmp/spire-agent/public/api.sock ]; then
    echo "❌ ERROR: SPIRE Agent socket not found at /tmp/spire-agent/public/api.sock"
    echo "Cannot proceed with deployment - socket path does not exist on host"
    exit 1
fi
echo "✅ SPIRE Agent socket verified at /tmp/spire-agent/public/api.sock"

# Verify SPIRE Agent binary exists on host
if [ ! -f /opt/spire/bin/spire-agent ]; then
    echo "❌ ERROR: SPIRE Agent binary not found at /opt/spire/bin/spire-agent"
    echo "Cannot proceed with deployment - binary path does not exist on host"
    exit 1
fi
echo "✅ SPIRE Agent binary verified at /opt/spire/bin/spire-agent"

# Verify the manifest has correct volume mount configuration
echo "Validating deployment manifest configuration..."
if ! grep -q "type: Socket" mtls-app.yaml; then
    echo "❌ ERROR: Deployment manifest missing 'type: Socket' for SPIRE Agent socket"
    exit 1
fi
if ! grep -q "type: File" mtls-app.yaml; then
    echo "❌ ERROR: Deployment manifest missing 'type: File' for SPIRE Agent binary"
    exit 1
fi
if ! grep -q "readOnly: true" mtls-app.yaml; then
    echo "❌ ERROR: Deployment manifest missing 'readOnly: true' for SPIRE Agent binary mount"
    exit 1
fi
echo "✅ Deployment manifest volume configuration validated"

# ========================================
# DEPLOYMENT WITH PROPER ERROR HANDLING (Task 5.2)
# ========================================

echo ""
echo "=========================================="
echo "Deploying application to Kubernetes..."
echo "=========================================="

# Delete existing deployment if present
echo ""
echo "Checking for existing deployment..."
if kubectl get deployment mtls-app &>/dev/null; then
    echo "Found existing deployment 'mtls-app', deleting..."
    if kubectl delete deployment mtls-app --timeout=30s; then
        echo "✅ Successfully deleted existing deployment"
        # Wait for pods to be fully terminated
        echo "Waiting for pods to terminate..."
        kubectl wait --for=delete pod -l app=mtls-demo --timeout=30s 2>/dev/null || true
        sleep 2
    else
        echo "❌ ERROR: Failed to delete existing deployment"
        echo "You may need to manually delete it with: kubectl delete deployment mtls-app --force --grace-period=0"
        exit 1
    fi
else
    echo "No existing deployment found"
fi

# Apply deployment manifest with kubectl
echo ""
echo "Applying deployment manifest..."
if ! kubectl apply -f mtls-app.yaml; then
    echo "❌ ERROR: Failed to apply deployment manifest"
    echo ""
    echo "Checking manifest syntax..."
    kubectl apply -f mtls-app.yaml --dry-run=client
    exit 1
fi
echo "✅ Deployment manifest applied successfully"

# Wait for pod to reach Running state with timeout
echo ""
echo "Waiting for pod to reach Running state (timeout: 120s)..."
TIMEOUT=120
ELAPSED=0
POD_RUNNING=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    POD_STATUS=$(kubectl get pods -l app=mtls-demo -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    
    if [ "$POD_STATUS" = "Running" ]; then
        POD_RUNNING=true
        echo "✅ Pod is Running"
        break
    elif [ "$POD_STATUS" = "Failed" ] || [ "$POD_STATUS" = "CrashLoopBackOff" ]; then
        echo "❌ ERROR: Pod entered failed state: $POD_STATUS"
        break
    else
        echo "Pod status: $POD_STATUS (waiting...)"
        sleep 5
        ELAPSED=$((ELAPSED + 5))
    fi
done

# Display pod events if deployment fails
if [ "$POD_RUNNING" = false ]; then
    echo ""
    echo "❌ ERROR: Pod failed to reach Running state within timeout"
    echo ""
    echo "=== Pod Status ==="
    kubectl get pods -l app=mtls-demo
    echo ""
    echo "=== Pod Description ==="
    POD_NAME=$(kubectl get pods -l app=mtls-demo -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    if [ -n "$POD_NAME" ]; then
        kubectl describe pod "$POD_NAME"
    fi
    echo ""
    echo "=== Pod Events ==="
    kubectl get events --sort-by='.lastTimestamp' | grep -i "$POD_NAME" || echo "No events found"
    echo ""
    echo "=== Recent Cluster Events ==="
    kubectl get events --sort-by='.lastTimestamp' | tail -20
    exit 1
fi

# Wait for pod to be fully ready (all containers ready)
echo ""
echo "Waiting for pod to be fully ready (all containers)..."
if ! kubectl wait --for=condition=ready pod -l app=mtls-demo --timeout=60s; then
    echo "❌ ERROR: Pod did not become ready within timeout"
    echo ""
    echo "=== Pod Status ==="
    kubectl get pods -l app=mtls-demo
    echo ""
    POD_NAME=$(kubectl get pods -l app=mtls-demo -o jsonpath="{.items[0].metadata.name}" 2>/dev/null)
    if [ -n "$POD_NAME" ]; then
        echo "=== Container Status ==="
        kubectl get pod "$POD_NAME" -o jsonpath='{.status.containerStatuses[*]}' | jq '.'
        echo ""
        echo "=== Pod Events ==="
        kubectl describe pod "$POD_NAME" | grep -A 20 "Events:"
    fi
    exit 1
fi
echo "✅ Pod is fully ready"

# ========================================
# POD LOG MONITORING AND VERIFICATION (Task 5.3)
# ========================================

echo ""
echo "=========================================="
echo "Monitoring pod logs and verifying functionality..."
echo "=========================================="

# Get pod name
POD_NAME=$(kubectl get pods -l app=mtls-demo -o jsonpath="{.items[0].metadata.name}")
echo "Pod name: $POD_NAME"

# Wait for application to initialize and generate logs
echo ""
echo "Waiting for application to initialize..."
MAX_RETRIES=30
LOGS_READY=false
for i in $(seq 1 $MAX_RETRIES); do
    if kubectl logs "$POD_NAME" 2>&1 | grep -q "Successfully fetched SVIDs"; then
        echo "Application initialized!"
        LOGS_READY=true
        break
    fi
    echo "Waiting for logs... ($i/$MAX_RETRIES)"
    sleep 2
done

if [ "$LOGS_READY" = false ]; then
    echo "⚠️  Warning: Timed out waiting for expected logs. Proceeding with verification..."
fi

# Display pod logs with clear formatting
echo ""
echo "=== Pod Logs ==="
echo "----------------------------------------"
POD_LOGS=$(kubectl logs "$POD_NAME" 2>&1)
echo "$POD_LOGS"
echo "----------------------------------------"

# Check logs for SVID fetch success indicators
echo ""
echo "Verifying SVID fetch success..."
SVID_FETCH_SUCCESS=false
if echo "$POD_LOGS" | grep -q "Successfully fetched SVIDs" || \
   echo "$POD_LOGS" | grep -q "Received .* svid after"; then
    echo "✅ SVID fetch command executed successfully"
    SVID_FETCH_SUCCESS=true
else
    echo "❌ SVID fetch command did not complete successfully"
fi

# Check for SVID files on disk
SVID_FILES_FOUND=false
if echo "$POD_LOGS" | grep -q "Writing SVID .* to file" || \
   echo "$POD_LOGS" | grep -q "Writing key .* to file" || \
   echo "$POD_LOGS" | grep -q "svid.0.pem.*svid.0.key.*bundle.0.pem"; then
    echo "✅ SVID files were created on disk"
    SVID_FILES_FOUND=true
else
    echo "❌ SVID files were not found on disk"
fi

# Verify mTLS server startup messages
echo ""
echo "Verifying mTLS server startup..."
MTLS_SERVER_STARTED=false
if echo "$POD_LOGS" | grep -q "Server.*listening on.*9999" || \
   echo "$POD_LOGS" | grep -q "mTLS Server listening" || \
   echo "$POD_LOGS" | grep -q "Secure mTLS Server"; then
    echo "✅ mTLS server started successfully on port 9999"
    MTLS_SERVER_STARTED=true
else
    echo "❌ mTLS server did not start successfully"
fi

# Check for any error messages
echo ""
echo "Checking for errors in logs..."
ERROR_FOUND=false
if echo "$POD_LOGS" | grep -qi "error\|failed\|exception\|traceback"; then
    echo "⚠️  Warning: Error messages detected in logs"
    echo ""
    echo "Error details:"
    echo "$POD_LOGS" | grep -i "error\|failed\|exception" | head -10
    ERROR_FOUND=true
else
    echo "✅ No error messages detected"
fi

# Report success or failure based on log content
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo "SVID Fetch Success:    $([ "$SVID_FETCH_SUCCESS" = true ] && echo "✅ PASS" || echo "❌ FAIL")"
echo "SVID Files Created:    $([ "$SVID_FILES_FOUND" = true ] && echo "✅ PASS" || echo "❌ FAIL")"
echo "mTLS Server Started:   $([ "$MTLS_SERVER_STARTED" = true ] && echo "✅ PASS" || echo "❌ FAIL")"
echo "No Errors Detected:    $([ "$ERROR_FOUND" = false ] && echo "✅ PASS" || echo "⚠️  WARN")"
echo "=========================================="

# Determine overall success
if [ "$SVID_FETCH_SUCCESS" = true ] && [ "$SVID_FILES_FOUND" = true ] && [ "$MTLS_SERVER_STARTED" = true ]; then
    echo ""
    echo "🎉 SUCCESS! The Kubernetes SPIRE integration is working correctly!"
    echo ""
    echo "The pod successfully:"
    echo "  1. Fetched SVID from SPIRE Agent"
    echo "  2. Saved certificate files to disk"
    echo "  3. Started mTLS server on port 9999"
    echo ""
    echo "You can monitor the pod with:"
    echo "  kubectl logs -f $POD_NAME"
    echo ""
    echo "To test mTLS connections, you can exec into the pod:"
    echo "  kubectl exec -it $POD_NAME -- /bin/bash"
    echo ""
else
    echo ""
    echo "❌ FAILURE: The deployment did not complete successfully"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check pod logs: kubectl logs $POD_NAME"
    echo "  2. Check pod events: kubectl describe pod $POD_NAME"
    echo "  3. Verify SPIRE Agent is running: ps aux | grep spire-agent"
    echo "  4. Check socket permissions: ls -la /tmp/spire-agent/public/api.sock"
    echo "  5. Verify workload registration: sudo /opt/spire/bin/spire-server entry show"
    echo ""
    exit 1
fi

echo "=========================================="
echo "   Demo Complete"
echo "=========================================="
