#!/bin/bash

echo "=========================================="
echo "   Phase 3: Kubernetes Setup Check"
echo "=========================================="

# 1. Check for kubectl
if command -v kubectl &> /dev/null; then
    echo "✅ kubectl is installed"
    kubectl version --client
else
    echo "❌ kubectl is NOT installed"
    echo "   Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    echo "   kubectl installed!"
fi

# 2. Check for a running cluster
if kubectl cluster-info &> /dev/null; then
    echo "✅ Kubernetes cluster is running"
else
    echo "❌ No active Kubernetes cluster found"
    echo "   Checking for Minikube..."
    
    if command -v minikube &> /dev/null; then
        echo "   Minikube found."
        
        # Check if running with docker driver and delete if so
        if minikube status | grep -q "driver: docker"; then
            echo "   Detected Docker driver. Switching to 'none' driver for SPIRE socket access..."
            minikube delete
        fi

        # Install dependencies for none driver
        if ! command -v conntrack &> /dev/null; then
            echo "   Installing conntrack (required for none driver)..."
            apt-get update && apt-get install -y conntrack socat
        fi
        
        echo "   Starting Minikube with --driver=none..."
        # We use none driver to allow access to host SPIRE socket
        # Minikube warns when running as root, but it is required for --driver=none in this context
        minikube start --driver=none
        
        # Fix permissions for kubeconfig
        chown -R $USER:$USER $HOME/.kube $HOME/.minikube
    else
        echo "   Minikube not found."
        echo "   Installing Minikube..."
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        install minikube-linux-amd64 /usr/local/bin/minikube
        
        # Install dependencies
        apt-get update && apt-get install -y conntrack socat
        
        echo "   Starting Minikube..."
        minikube start --driver=none
        
        # Fix permissions
        chown -R $USER:$USER $HOME/.kube $HOME/.minikube
    fi
fi

# 3. Load image into Minikube (if using Minikube)
if command -v minikube &> /dev/null; then
    echo "-> Loading Docker image into Minikube..."
    # If the image exists locally
    if docker images | grep -q mtls-demo-image; then
        minikube image load mtls-demo-image:latest
        echo "   Image loaded!"
    else
        echo "   Warning: mtls-demo-image not found locally. Build it first!"
    fi
fi

echo ""
echo "Setup complete. Ready to apply manifests."
