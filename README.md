# Zero Trust SPIRE Integration Project

This repository contains a multi-phase project demonstrating the implementation of Zero Trust security principles using **SPIFFE** (Secure Production Identity Framework for Everyone) and **SPIRE** (SPIFFE Runtime Environment).

The project progressively builds a secure identity infrastructure, starting from a basic host-based setup, moving to Docker containers, and finally integrating with Kubernetes.

## Project Phases

### [Phase 1: Host-Based SPIRE Setup](./phase_3_k8s/README-spire-setup.md)
**Goal:** Establish the foundational SPIRE infrastructure on a Linux host.
- Installation of SPIRE Server and Agent.
- Configuration of Unix Workload Attestor.
- Basic workload registration and SVID issuance on the host.
- Verification of Agent-Server communication.

### [Phase 2: Docker Integration](./phase_3_k8s/README-docker-phase2.md)
**Goal:** Extend SPIRE identity to Docker containers.
- Configuration of the **Docker Workload Attestor**.
- Building a custom Docker image for the mTLS demo application.
- Registering workloads based on Docker labels (`docker:label:app=mtls_demo`).
- Mounting the SPIRE Agent socket into containers.
- Demonstrating successful SVID fetching and mTLS communication between a containerized client and server.

### [Phase 3: Kubernetes Integration](./phase_3_k8s/README-k8s-phase3.md)
**Goal:** Implement SPIRE in a Kubernetes environment (Minikube).
- Setting up Minikube with the `none` driver for direct host integration.
- Configuring the **Kubernetes Workload Attestor**.
- Deploying the mTLS application as a Kubernetes Pod.
- Registering workloads using Kubernetes selectors (`k8s:pod:label:app=mtls-demo`).
- Verifying end-to-end mTLS communication within the Kubernetes cluster.

## Repository Structure

All project files are currently consolidated in the `phase_3_k8s` directory for ease of migration and execution.

```
.
├── phase_3_k8s/
│   ├── README-spire-setup.md    # Phase 1 Documentation
│   ├── README-docker-phase2.md  # Phase 2 Documentation
│   ├── README-k8s-phase3.md     # Phase 3 Documentation (Current)
│   ├── run_k8s_demo.sh          # Main script for Phase 3
│   ├── run_docker_demo.sh       # Main script for Phase 2
│   ├── mtls_demo.py             # Python mTLS application (used in all phases)
│   ├── mtls-app.yaml            # Kubernetes deployment manifest
│   ├── Dockerfile               # Container definition
│   └── ... (setup scripts and configs)
└── README.md                    # This file
```

## Quick Start (Phase 3)

To run the latest Kubernetes integration demo:

1. **Navigate to the project directory:**
   ```bash
   cd phase_3_k8s
   ```

2. **Run the automated demo script:**
   ```bash
   sudo ./run_k8s_demo.sh
   ```

3. **Verify the deployment:**
   ```bash
   sudo kubectl get pods
   sudo kubectl logs -l app=mtls-demo
   ```

For detailed instructions on each phase, please refer to their respective README files linked above.

## Prerequisites

- **OS:** Ubuntu 22.04 LTS (or similar Linux distribution)
- **Runtime:** Docker Engine
- **Orchestrator:** Minikube (for Phase 3)
- **Tools:** `kubectl`, `git`, `python3`

## References

- [SPIFFE Project](https://spiffe.io/)
- [SPIRE Documentation](https://spiffe.io/docs/latest/spire/what-is-spire/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
