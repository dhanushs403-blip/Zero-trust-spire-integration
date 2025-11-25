#!/bin/bash

# spire_demo.sh
# Automates the SPIRE setup and verification demo

echo "=========================================="
echo "   Starting SPIRE Demo"
echo "=========================================="

# 1. Cleanup
echo "[1/5] Cleaning up previous SPIRE processes and data..."
# Capture the directory where the script is running (where dummy_app.py lives)
DEMO_DIR=$(pwd)
sudo killall spire-server spire-agent 2>/dev/null
# Clean up data directories (both in /opt/spire and current dir if any)
sudo rm -rf /opt/spire/data/server/*
sudo rm -rf /opt/spire/data/agent/*
rm -rf data/
sleep 2

# 2. Start Server
echo "[2/5] Starting SPIRE Server..."
# Navigate to /opt/spire so relative config paths work correctly
cd /opt/spire
sudo ./bin/spire-server run -config ./conf/server/server.conf > /dev/null 2>&1 &
SERVER_PID=$!
sleep 3

# 3. Start Agent
echo "[3/5] Generating Token and Starting Agent..."
TOKEN=$(sudo ./bin/spire-server token generate -spiffeID spiffe://example.org/myagent | grep Token | awk '{print $2}')
echo "      Token: $TOKEN"

sudo ./bin/spire-agent run -config ./conf/agent/agent.conf -joinToken $TOKEN > /dev/null 2>&1 &
AGENT_PID=$!
sleep 3

# Check Health
echo "      Checking Agent Health..."
sudo ./bin/spire-agent healthcheck
if [ $? -ne 0 ]; then
    echo "Error: Agent is not healthy."
    exit 1
fi

# 4. Register Workload
echo "[4/5] Registering Workload..."
USER_ID=$(id -u)
# Note: We use -socketPath if needed, but defaults usually work.
# We ignore errors if entry already exists (or we could delete it first)
sudo ./bin/spire-server entry create \
    -parentID spiffe://example.org/myagent \
    -spiffeID spiffe://example.org/myservice \
    -selector unix:uid:$USER_ID

# Wait for agent to sync the new entry (increased to 10 seconds)
echo "      Waiting for agent to sync..."
sleep 10

# 5. Run Real mTLS App
echo "[5/5] Running Real Custom mTLS App..."
echo "------------------------------------------"
echo "Fetching SVIDs to local files for the app..."
sudo ./bin/spire-agent api fetch x509 -write . -socketPath /tmp/spire-agent/public/api.sock

echo "Starting mTLS Client/Server Demo..."
# Run the mTLS demo app using the captured path
python3 "$DEMO_DIR/mtls_demo.py"

echo "Cleaning up SVID files..."
rm svid.0.pem svid.0.key bundle.0.pem
echo "------------------------------------------"
echo "Demo Complete!"
