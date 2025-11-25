#!/bin/bash

# Install Docker
echo "Installing Docker..."
echo "1" | sudo -S apt-get update
echo "1" | sudo -S apt-get install -y docker.io

# Start and Enable Docker
echo "Starting Docker..."
echo "1" | sudo -S systemctl start docker
echo "1" | sudo -S systemctl enable docker

# Add user to docker group
echo "Adding user to docker group..."
echo "1" | sudo -S usermod -aG docker dell

echo "Docker installation complete."
docker --version
