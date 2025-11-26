#!/bin/bash

# Kill any existing agents
sudo killall spire-agent 2>/dev/null
sleep 2

# Go to SPIRE directory
cd /opt/spire

# Generate a fresh token
echo "Generating join token..."
TOKEN=$(sudo ./bin/spire-server token generate -spiffeID spiffe://example.org/myagent 2>&1 | grep 'Token:' | awk '{print $2}')

if [ -z "$TOKEN" ]; then
    echo "Error: Failed to generate token"
    exit 1
fi

echo "Token generated: $TOKEN"

# Start the agent
echo "Starting SPIRE Agent..."
sudo sh -c "nohup ./bin/spire-agent run -config conf/agent/agent.conf -joinToken $TOKEN > agent.log 2>&1 &"

# Wait for socket to be created
echo "Waiting for socket..."
for i in {1..10}; do
    if [ -S /tmp/spire-agent/public/api.sock ]; then
        echo "✅ SPIRE Agent started successfully!"
        echo "Socket: /tmp/spire-agent/public/api.sock"
        ls -la /tmp/spire-agent/public/api.sock
        exit 0
    fi
    sleep 1
done

echo "❌ Error: Socket not created within timeout"
echo "Checking agent log:"
tail -n 20 agent.log
exit 1
