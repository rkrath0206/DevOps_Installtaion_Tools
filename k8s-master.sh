#!/bin/bash

set -e

MASTER_IP=$(hostname -I | awk '{print $1}')

echo "======================================"
echo " Kubernetes Master Installation"
echo " Master IP: $MASTER_IP"
echo "======================================"

# -----------------------------
# 1. Update system
# -----------------------------
apt-get update -y
apt-get upgrade -y

# -----------------------------
# 2. Disable swap
# -----------------------------
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# -----------------------------
# 3. Kernel modules
# -----------------------------
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# -----------------------------
# 4. Kubernetes networking
# -----------------------------
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# -----------------------------
# 5. Install containerd
# -----------------------------
apt-get install -y containerd

mkdir -p /etc/containerd

containerd config default > /etc/containerd/config.toml

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
    /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# -----------------------------
# 6. Install Kubernetes repository
# -----------------------------
apt-get install -y ca-certificates curl gpg

install -m 0755 -d /etc/apt/keyrings

curl -fsSL \
https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
| gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
> /etc/apt/sources.list.d/kubernetes.list

apt-get update -y

# -----------------------------
# 7. Install Kubernetes
# -----------------------------
apt-get install -y kubelet kubeadm kubectl

apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

# -----------------------------
# 8. Initialize Kubernetes
# -----------------------------
echo ""
echo "Initializing Kubernetes..."
echo ""

kubeadm init \
    --apiserver-advertise-address="$MASTER_IP" \
    --pod-network-cidr=192.168.0.0/16

# -----------------------------
# 9. Configure kubectl
# -----------------------------
mkdir -p /root/.kube

cp -i /etc/kubernetes/admin.conf /root/.kube/config

chown root:root /root/.kube/config

# -----------------------------
# 10. Install Calico CNI
# -----------------------------
echo ""
echo "Installing Calico network..."
echo ""

kubectl apply -f \
https://raw.githubusercontent.com/projectcalico/calico/v3.30.3/manifests/calico.yaml

# -----------------------------
# 11. Generate worker join command
# -----------------------------
echo ""
echo "======================================"
echo " WORKER JOIN COMMAND"
echo "======================================"
echo ""

kubeadm token create --print-join-command

echo ""
echo "======================================"
echo " Kubernetes Master Setup Completed"
echo "======================================"
echo ""

echo "Check master:"
echo "kubectl get nodes"

echo ""
echo "Check pods:"
echo "kubectl get pods -A"
