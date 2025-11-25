#!/bin/bash

# Debug script to verify Docker + SPIRE integration
echo "==========================================="
echo "SPIRE Docker Integration Debug Tool"
echo "==========================================="
echo ""

# 1. Check SPIRE Server
echo "[1] Checking SPIRE Server..."
if pgrep -x spire-server > /dev/null; then
    echo "    ✓ SPIRE Server is running (PID: $(pgrep -x spire-server))"
else
    echo "    ❌ SPIRE Server is NOT running"
fi
echo ""

# 2. Check SPIRE Agent
echo "[2] Checking SPIRE Agent..."
if pgrep -x spire-agent > /dev/null; then
    echo "    ✓ SPIRE Agent is running (PID: $(pgrep -x spire-agent))"
    
    # Check health
    echo "    Checking agent health..."
    if echo "1" | sudo -S /opt/spire/bin/spire-agent healthcheck 2>&1 | grep -q "Agent is healthy"; then
        echo "    ✓ Agent is healthy"
    else
        echo "    ⚠ Agent may not be healthy"
    fi
else
    echo "    ❌ SPIRE Agent is NOT running"
fi
echo ""

# 3. Check socket
echo "[3] Checking SPIRE Agent socket..."
if [ -S /tmp/spire-agent/public/api.sock ]; then
    echo "    ✓ Socket exists: /tmp/spire-agent/public/api.sock"
    ls -la /tmp/spire-agent/public/api.sock
else
    echo "    ❌ Socket NOT found at /tmp/spire-agent/public/api.sock"
fi
echo ""

# 4. Check workload registrations
echo "[4] Checking workload registrations..."
echo "1" | sudo -S /opt/spire/bin/spire-server entry show 2>/dev/null | grep -A 10 "myservice"
echo ""

# 5. Test SVID fetch from host
echo "[5] Testing SVID fetch from host..."
cd /tmp
echo "1" | sudo -S /opt/spire/bin/spire-agent api fetch x509 2>&1 | head -20
echo ""

# 6. Check Docker
echo "[6] Checking Docker..."
if command -v docker &> /dev/null; then
    echo "    ✓ Docker is installed"
    echo "1" | sudo -S docker --version
    
    # Check if Docker daemon is running
    if echo "1" | sudo -S docker info > /dev/null 2>&1; then
        echo "    ✓ Docker daemon is running"
    else
        echo "    ❌ Docker daemon is NOT running"
    fi
else
    echo "    ❌ Docker is NOT installed"
fi
echo ""

# 7. Check Docker image
echo "[7] Checking Docker image..."
if echo "1" | sudo -S docker images | grep -q "mtls-demo-image"; then
    echo "    ✓ mtls-demo-image exists"
    echo "1" | sudo -S docker images | grep "mtls-demo-image"
else
    echo "    ⚠ mtls-demo-image not found (needs to be built)"
fi
echo ""

# 8. Test Docker socket access
echo "[8] Testing Docker socket mount..."
TEST_RESULT=$(echo "1" | sudo -S docker run --rm \
    -v /tmp/spire-agent/public/api.sock:/tmp/spire-agent/public/api.sock \
    python:3.9-slim \
    sh -c "test -S /tmp/spire-agent/public/api.sock && echo 'Socket accessible' || echo 'Socket NOT accessible'" 2>/dev/null)
echo "    Result: $TEST_RESULT"
echo ""

# 9. Test Docker label-based attestation
echo "[9] Testing Docker with workload label..."
if echo "1" | sudo -S docker images | grep -q "mtls-demo-image"; then
    echo "    Starting test container with label app=mtls_demo..."
    echo "1" | sudo -S docker run -d --name test-mtls-label \
        --label app=mtls_demo \
        -v /tmp/spire-agent/public/api.sock:/tmp/spire-agent/public/api.sock \
        -v /opt/spire/bin/spire-agent:/opt/spire/bin/spire-agent:ro \
        mtls-demo-image sleep 30 2>/dev/null
    
    sleep 3
    
    # Try to fetch SVID from inside container
    echo "    Testing SVID fetch from inside container..."
    echo "1" | sudo -S docker exec test-mtls-label /opt/spire/bin/spire-agent api fetch x509 2>&1 | head -10
    
    # Cleanup
    echo "1" | sudo -S docker rm -f test-mtls-label 2>/dev/null
else
    echo "    ⚠ Skipping (image not built)"
fi
echo ""

# 10. Summary
echo "==========================================="
echo "Summary & Recommendations"
echo "==========================================="

ISSUES=0

if ! pgrep -x spire-server > /dev/null; then
    echo "❌ Start SPIRE Server first"
    ISSUES=$((ISSUES+1))
fi

if ! pgrep -x spire-agent > /dev/null; then
    echo "❌ Start SPIRE Agent with Docker support"
    ISSUES=$((ISSUES+1))
fi

if [ ! -S /tmp/spire-agent/public/api.sock ]; then
    echo "❌ Agent socket missing - restart agent"
    ISSUES=$((ISSUES+1))
fi

if ! echo "1" | sudo -S docker info > /dev/null 2>&1; then
    echo "❌ Docker daemon not running - start Docker service"
    ISSUES=$((ISSUES+1))
fi

if [ $ISSUES -eq 0 ]; then
    echo "✅ All checks passed! Ready to run Docker demo."
else
    echo "⚠ Found $ISSUES issue(s) that need to be fixed."
fi

echo "==========================================="
