#!/bin/bash

# wrapper to run spire_demo.sh with sudo password
cd /home/dell/dhanush/spire_demo

echo "=========================================="
echo "   Starting SPIRE Demo (TPM Machine)"
echo "=========================================="

# Run with sudo password piped
echo "1" | sudo -S killall spire-server spire-agent 2>/dev/null
echo "1" | sudo -S rm -rf /opt/spire/data/server/*
echo "1" | sudo -S rm -rf /opt/spire/data/agent/*

DEMO_DIR=$(pwd)

# 2. Start Server
echo "[2/5] Starting SPIRE Server..."
cd /opt/spire
echo "1" | sudo -S ./bin/spire-server run -config ./conf/server/server.conf > /dev/null 2>&1 &
sleep 3

# 3. Start Agent
echo "[3/5] Generating Token and Starting Agent..."
TOKEN=$(echo "1" | sudo -S ./bin/spire-server token generate -spiffeID spiffe://example.org/myagent | grep Token | awk '{print $2}')
echo "      Token: $TOKEN"

echo "1" | sudo -S ./bin/spire-agent run -config ./conf/agent/agent.conf -joinToken $TOKEN > /dev/null 2>&1 &
sleep 3

# Check Health
echo "      Checking Agent Health..."
echo "1" | sudo -S ./bin/spire-agent healthcheck
if [ $? -ne 0 ]; then
    echo "Error: Agent is not healthy."
    exit 1
fi

# 4. Register Workload
echo "[4/5] Registering Workload..."
USER_ID=$(id -u)
echo "1" | sudo -S ./bin/spire-server entry create \
    -parentID spiffe://example.org/myagent \
    -spiffeID spiffe://example.org/myservice \
    -selector unix:uid:$USER_ID

echo "      Waiting for agent to sync..."
sleep 10

# 5. Run Real mTLS App
echo "[5/5] Running Real Custom mTLS App..."
echo "------------------------------------------"
echo "Fetching SVIDs to local files for the app..."
# Run without sudo to match the UID selector (1000)
# Change to demo directory where we have write permissions
cd "$DEMO_DIR"
/opt/spire/bin/spire-agent api fetch x509 -write . -socketPath /tmp/spire-agent/public/api.sock

echo "Starting mTLS Client/Server Demo..."
python3 "$DEMO_DIR/mtls_demo.py"

echo "Cleaning up SVID files..."
rm svid.0.pem svid.0.key bundle.0.pem 2>/dev/null
echo "------------------------------------------"
echo "Demo Complete!"
