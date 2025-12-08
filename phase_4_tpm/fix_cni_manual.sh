#!/bin/bash

echo "=========================================="
echo "   Fixing CNI Plugins Manually"
echo "=========================================="

# 1. Install CNI Plugins
echo "[1/3] Installing CNI binaries to /opt/cni/bin..."
CNI_VERSION="v1.3.0"
echo "1" | sudo -S mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" | echo "1" | sudo -S tar -C /opt/cni/bin -xz

# 2. Clean old CNI configs
echo "[2/3] Cleaning old CNI configs..."
echo "1" | sudo -S rm -rf /etc/cni/net.d/*

# 3. Re-apply Flannel
echo "[3/3] Re-applying Flannel..."
kubectl delete -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml 2>/dev/null || true
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# 4. Restart Kubelet
echo "Restarting Kubelet..."
echo "1" | sudo -S systemctl restart kubelet

echo ""
echo "Waiting for node to become Ready..."
for i in {1..60}; do
    STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
    if [ "$STATUS" == "True" ]; then
        echo "✅ Node is Ready!"
        kubectl get nodes
        exit 0
    fi
    echo -n "."
    sleep 2
done

echo "❌ Node still NotReady. Check logs."
exit 1
