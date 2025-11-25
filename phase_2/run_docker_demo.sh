#!/bin/bash

# Phase 2: SPIRE with Docker Demo
cd /home/dell/dhanush/phase_2
DEMO_DIR=$(pwd)

echo "=========================================="
echo "   Starting SPIRE Docker Demo"
echo "=========================================="

# 1. Cleanup
echo "[1/7] Cleaning up..."
echo "1" | sudo -S killall spire-server spire-agent 2>/dev/null
echo "1" | sudo -S rm -rf /opt/spire/data/server/*
echo "1" | sudo -S rm -rf /opt/spire/data/agent/*
# Remove existing container if any
echo "1" | sudo -S docker rm -f mtls-app 2>/dev/null
# Clean up old images
echo "1" | sudo -S docker rmi mtls-demo-image 2>/dev/null

# 2. Start Server
echo "[2/7] Starting SPIRE Server..."
cd /opt/spire
echo "1" | sudo -S ./bin/spire-server run -config ./conf/server/server.conf > /dev/null 2>&1 &
sleep 3

# Verify server is running
if ! pgrep -x spire-server > /dev/null; then
    echo "Error: SPIRE Server failed to start"
    exit 1
fi
echo "      ✓ Server is running"

# 3. Start Agent with Docker Support
echo "[3/7] Starting SPIRE Agent (Docker Enabled)..."
AGENT_CONFIG="$DEMO_DIR/agent_docker.conf"

TOKEN=$(echo "1" | sudo -S ./bin/spire-server token generate -spiffeID spiffe://example.org/myagent | awk '/Token/ {print $2}')
echo "      Token: $TOKEN"

echo "1" | sudo -S ./bin/spire-agent run -config "$AGENT_CONFIG" -joinToken $TOKEN > "$DEMO_DIR/agent.log" 2>&1 &
sleep 3

# Check Agent Health
echo "      Checking Agent Health..."
if ! echo "1" | sudo -S ./bin/spire-agent healthcheck; then
    echo "Error: Agent is not healthy."
    exit 1
fi
echo "      ✓ Agent is healthy"

# Verify socket exists
if [ ! -S /tmp/spire-agent/public/api.sock ]; then
    echo "Error: Agent socket not found at /tmp/spire-agent/public/api.sock"
    exit 1
fi
echo "      ✓ Agent socket exists"

# Get the Agent's SPIFFE ID
# We need to wait a moment for the agent to fully attest
sleep 5
# FIX #1: Ensure we grab column 4 (the ID), not column 3 (the colon)
AGENT_ID=$(echo "1" | sudo -S /opt/spire/bin/spire-server agent list | grep "SPIFFE ID" | awk '{print $4}' | head -n 1)

if [ -z "$AGENT_ID" ]; then
    echo "Error: Could not determine Agent SPIFFE ID. Agent might not be attested yet."
    echo "1" | sudo -S /opt/spire/bin/spire-server agent list
    exit 1
fi
echo "      Agent ID: $AGENT_ID"

# 4. Register Workload
echo "[4/7] Registering Workload..."
# Note the selector: docker:label:app=mtls_demo
register_workload() {
    echo "1" | sudo -S /opt/spire/bin/spire-server entry create \
        -parentID "$AGENT_ID" \
        -spiffeID spiffe://example.org/myservice \
        -selector docker:label:app:mtls_demo
}
# Execute registration
register_workload || true

echo "      Waiting for agent to sync..."
sleep 5

# Verify workload is registered
echo "      Verifying workload registration..."
# FIX #2: Use the dynamic $AGENT_ID variable for verification, not the static string
ENTRIES=$(echo "1" | sudo -S /opt/spire/bin/spire-server entry show -parentID "$AGENT_ID")

if echo "$ENTRIES" | grep -q "spiffe://example.org/myservice"; then
    echo "      ✓ Workload registered successfully"
else
    echo "      ⚠ Warning: Workload may not be registered correctly"
    echo "      Debug: Checking entries for Parent ID: $AGENT_ID"
    echo "$ENTRIES"
fi

# 5. Build Docker Image
echo "[5/7] Building Docker Image..."
cd "$DEMO_DIR"
echo "1" | sudo -S docker build -t mtls-demo-image .
if [ $? -ne 0 ]; then
    echo "Error: Docker build failed"
    exit 1
fi
echo "      ✓ Docker image built successfully"

# 6. Verify Docker can access SPIRE Agent
echo "[6/7] Verifying Docker setup..."
# Test that Docker can see the socket by running a simple test
TEST_RESULT=$(echo "1" | sudo -S docker run --rm \
    -v /tmp/spire-agent/public/api.sock:/tmp/spire-agent/public/api.sock \
    python:3.9-slim \
    test -S /tmp/spire-agent/public/api.sock && echo "exists" || echo "missing")

if [ "$TEST_RESULT" != "exists" ]; then
    echo "      ⚠ Warning: Socket may not be accessible from container"
else
    echo "      ✓ Socket is accessible from container"
fi

# 7. Run Docker Container
echo "[7/7] Running Containerized mTLS App..."
echo "------------------------------------------"

# We mount:
# 1. The SPIRE Agent socket so the workload can talk to the agent.
# 2. The spire-agent binary so the python script can call it.
# 3. We set the label app=mtls_demo to match the registration.

# Give the agent a moment to recognize the workload
sleep 2

echo "1" | sudo -S docker run --name mtls-app \
    --label app=mtls_demo \
    -v /tmp/spire-agent/public/api.sock:/tmp/spire-agent/public/api.sock \
    -v /opt/spire/bin/spire-agent:/opt/spire/bin/spire-agent:ro \
    mtls-demo-image

EXIT_CODE=$?

echo "------------------------------------------"
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Demo completed successfully!"
else
    echo "❌ Demo failed with exit code: $EXIT_CODE"
    echo ""
    echo "=========================================="
    echo "DEBUG: SPIRE Agent Logs (Last 50 lines)"
    echo "=========================================="
    if [ -f "$DEMO_DIR/agent.log" ]; then
        tail -n 50 "$DEMO_DIR/agent.log"
    else
        echo "Log file not found."
    fi
    
    echo "=========================================="
    echo "DEBUG: Registered Entries"
    echo "=========================================="
    echo "1" | sudo -S /opt/spire/bin/spire-server entry show
    
    echo "=========================================="
    echo "DEBUG: Attested Agents"
    echo "=========================================="
    echo "1" | sudo -S /opt/spire/bin/spire-server agent list
    
    echo "=========================================="
    echo "DEBUG: Agent Identity from Logs"
    echo "=========================================="
    if [ -f "$DEMO_DIR/agent.log" ]; then
        grep "Agent SVID" "$DEMO_DIR/agent.log" || echo "No Agent SVID log found"
        grep "Renewing SVID" "$DEMO_DIR/agent.log" || echo "No Renewing SVID log found"
    fi
    
    echo "Troubleshooting tips:"
    echo "  1. Check container logs: sudo docker logs mtls-app"
    echo "  2. Verify agent socket: ls -la /tmp/spire-agent/public/api.sock"
    echo "  3. Check workload entries: sudo /opt/spire/bin/spire-server entry show"
    echo "  4. Test socket manually: sudo /opt/spire/bin/spire-agent api fetch x509"
fi

# Cleanup
echo "1" | sudo -S docker rm mtls-app 2>/dev/null

echo "=========================================="