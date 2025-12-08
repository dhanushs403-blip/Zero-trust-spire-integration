#!/bin/bash

# Sync updated files to remote machine
# Usage: ./sync_to_remote.sh

REMOTE_USER="dell"
REMOTE_HOST="172.26.1.77"
REMOTE_PATH="/home/dell/dhanush/phase_4_tpm/"

echo "=========================================="
echo "Syncing Updated Files to Remote Machine"
echo "=========================================="
echo ""
echo "Remote: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
echo ""

# Files that were updated
FILES_TO_SYNC=(
    "server.conf.tpm"
    "agent.conf.tpm"
    "run_tpm_demo.sh"
    "mtls_demo.py"
    "run_demo_without_tpm_plugin.sh"
)

echo "Files to sync:"
for file in "${FILES_TO_SYNC[@]}"; do
    echo "  - $file"
done
echo ""

read -p "Proceed with sync? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Sync cancelled"
    exit 0
fi

echo "Syncing files..."
echo ""

for file in "${FILES_TO_SYNC[@]}"; do
    echo "Copying $file..."
    scp "$file" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}${file}"
    
    if [ $? -eq 0 ]; then
        echo "✓ $file synced successfully"
    else
        echo "✗ Failed to sync $file"
        exit 1
    fi
done

echo ""
echo "=========================================="
echo "Sync Complete!"
echo "=========================================="
echo ""
echo "Next steps on remote machine:"
echo "  1. SSH to remote: ssh ${REMOTE_USER}@${REMOTE_HOST}"
echo "  2. Navigate to: cd ${REMOTE_PATH}"
echo "  3. Make scripts executable: chmod +x *.sh"
echo "  4. Run demo: sudo ./run_tpm_demo.sh"
echo ""
