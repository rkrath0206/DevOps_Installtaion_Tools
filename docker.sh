#!/bin/bash

echo "=============================="
echo " Installing Git and Docker"
echo "=============================="

# Update packages
sudo apt update -y

# Install Git
echo "Installing Git..."
sudo apt install git -y

# Install Docker
echo "Installing Docker..."
sudo apt install docker.io -y

# Start Docker
sudo systemctl start docker

# Enable Docker at boot
sudo systemctl enable docker

# Add current user to Docker group
sudo usermod -aG docker $USER

echo ""
echo "=============================="
echo " Installation Completed!"
echo "=============================="

echo "Git version:"
git --version

echo "Docker version:"
docker --version

echo ""
echo "IMPORTANT:"
echo "Logout and login again for Docker group permission."
echo "Then run: docker run hello-world"
