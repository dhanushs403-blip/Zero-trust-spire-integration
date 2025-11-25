# SPIRE Docker Integration - Phase 2

## Overview
This directory contains the files needed to run the SPIRE mTLS demo inside a Docker container with workload attestation.

## Files

### Core Application
- **mtls_demo.py** - Python mTLS demo that fetches SVIDs from SPIRE Agent before running
- **Dockerfile** - Container definition for the mTLS demo app

### Configuration
- **agent_docker.conf** - SPIRE Agent configuration with Docker workload attestor enabled

### Scripts
- **run_docker_demo.sh** - Main script to run the complete Docker-based demo
- **debug_docker_setup.sh** - Diagnostic tool to verify SPIRE + Docker integration

## Key Changes from Phase 1

### 1. Enhanced Python Script
The `mtls_demo.py` now includes a `fetch_svids()` function that:
- Calls the SPIRE Agent API to fetch X.509 SVIDs
- Parses the output to extract certificates and keys
- Saves them to files before running the mTLS demo
- Provides clear error messages if fetching fails

### 2. Docker Configuration
- The Dockerfile creates necessary mount points for the SPIRE socket and agent binary
- The container runs with the label `app=mtls_demo` for attestation
- Two volumes are mounted:
  - SPIRE Agent socket: `/tmp/spire-agent/public/api.sock`
  - SPIRE Agent binary: `/opt/spire/bin/spire-agent` (read-only)

### 3. Agent Configuration
- Added `WorkloadAttestor "docker"` plugin to enable Docker-based attestation
- Agent uses `docker:label:app=mtls_demo` as the selector

## How It Works

1. **SPIRE Server & Agent Start**: The server and agent start with Docker support enabled
2. **Workload Registration**: A workload entry is created with selector `docker:label:app=mtls_demo`
3. **Docker Image Build**: The mTLS demo is packaged into a Docker image
4. **Container Launch**: The container starts with:
   - The workload label matching the registration
   - Mounted SPIRE socket for API communication
   - Mounted spire-agent binary for fetching SVIDs
5. **SVID Fetch**: The Python app calls the SPIRE Agent API to fetch SVIDs
6. **mTLS Demo**: Once SVIDs are obtained, the mTLS communication proceeds

## Usage

### Quick Start
```bash
cd /home/dell/dhanush/phase_2
chmod +x run_docker_demo.sh
./run_docker_demo.sh
```

### Debugging
If the demo fails, run the diagnostic tool:
```bash
chmod +x debug_docker_setup.sh
./debug_docker_setup.sh
```

This will check:
- SPIRE Server/Agent status
- Socket accessibility
- Workload registrations
- Docker configuration
- Container-to-Agent communication

### Manual Testing
To manually test SVID fetching from inside a container:

```bash
# Start a test container
sudo docker run -it --rm \
  --label app=mtls_demo \
  -v /tmp/spire-agent/public/api.sock:/tmp/spire-agent/public/api.sock \
  -v /opt/spire/bin/spire-agent:/opt/spire/bin/spire-agent:ro \
  mtls-demo-image \
  /bin/bash

# Inside container, test SVID fetch
/opt/spire/bin/spire-agent api fetch x509
```

## Common Issues & Solutions

### Issue: "SVID files not found"
**Cause**: The container can't fetch SVIDs from the Agent
**Solutions**:
1. Verify agent socket is mounted: `ls -la /tmp/spire-agent/public/api.sock`
2. Check agent health: `sudo /opt/spire/bin/spire-agent healthcheck`
3. Verify workload is registered: `sudo /opt/spire/bin/spire-server entry show`
4. Ensure container has the correct label: `docker:label:app=mtls_demo`

### Issue: "Agent socket not found"
**Cause**: SPIRE Agent not running or socket path incorrect
**Solutions**:
1. Restart the agent with Docker-enabled config
2. Verify socket exists: `ls /tmp/spire-agent/public/api.sock`
3. Check agent is running: `pgrep spire-agent`

### Issue: "Permission denied" when accessing socket
**Cause**: Socket permissions may not allow container access
**Solutions**:
1. Run container with appropriate user permissions
2. Check socket permissions: `ls -la /tmp/spire-agent/public/api.sock`
3. Ensure Docker daemon has access to the socket

### Issue: "Docker build failed"
**Cause**: Missing files or incorrect Dockerfile
**Solutions**:
1. Ensure `mtls_demo.py` exists in the current directory
2. Check Dockerfile syntax
3. Verify Docker daemon is running: `sudo docker info`

## Architecture

```
┌─────────────────────────────────────────────┐
│           SPIRE Server                      │
│   (Manages identities & attestation)       │
└────────────────┬────────────────────────────┘
                 │
                 │ (Registration)
                 │
┌────────────────▼────────────────────────────┐
│           SPIRE Agent                       │
│   (Docker workload attestor enabled)       │
│   Socket: /tmp/spire-agent/public/api.sock │
└────────────────┬────────────────────────────┘
                 │
                 │ (Socket + Binary mounted)
                 │
┌────────────────▼────────────────────────────┐
│        Docker Container                     │
│   Label: app=mtls_demo                     │
│                                             │
│   ┌─────────────────────────────────────┐  │
│   │  mtls_demo.py                       │  │
│   │  1. Fetch SVIDs via Agent API       │  │
│   │  2. Save certs to files             │  │
│   │  3. Run mTLS demo                   │  │
│   └─────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

## Next Steps

- **Auto-rotation**: Implement SVID rotation for long-running containers
- **Multi-container**: Extend to multiple containers communicating via mTLS
- **Kubernetes**: Migrate to Kubernetes with SPIRE integration
- **Production hardening**: Add proper error handling, logging, and monitoring

## References

- [SPIRE Docker Workload Attestor](https://spiffe.io/docs/latest/deploying/configuring/#docker-workload-attestor)
- [SPIRE Agent API](https://spiffe.io/docs/latest/deploying/spire_agent/)
- [Docker Labels](https://docs.docker.com/config/labels-custom-metadata/)
