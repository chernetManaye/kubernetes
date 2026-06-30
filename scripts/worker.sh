#!/bin/bash
set -euo pipefail

# Install containerd
sudo apt-get update
sudo apt-get install -y containerd

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# Enable systemd cgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' \
/etc/containerd/config.toml

# Restart and enable containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Disable swap
sudo swapoff -a

# Comment out swap entry in fstab
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Persist IP forwarding
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/k8s.conf
sudo sysctl --system

# Install Prerequisites
sudo apt-get update
sudo apt-get install -y \
apt-transport-https \
ca-certificates \
curl \
gpg

# Add Kubernetes APT repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | \
sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install Kubernetes packages
sudo apt-get update
sudo apt-get install -y \
kubelet \
kubeadm

# Hold Kubernetes packages
sudo apt-mark hold \
kubelet \
kubeadm

# Add this value KUBELET_EXTRA_ARGS="--cloud-provider=external" to /etc/default/kubelet
grep -q '^KUBELET_EXTRA_ARGS=' /etc/default/kubelet 2>/dev/null \
  && sudo sed -i 's|^KUBELET_EXTRA_ARGS=.*|KUBELET_EXTRA_ARGS="--cloud-provider=external"|' /etc/default/kubelet \
  || echo 'KUBELET_EXTRA_ARGS="--cloud-provider=external"' | sudo tee -a /etc/default/kubelet >/dev/null


# Join the Kubernetes cluster as worker node
# sudo kubeadm join 18.185.239.164:6443 --token 774yb5.9phbt6tphz8mjysc \
# 	--discovery-token-ca-cert-hash sha256:5bf2e9829bc6267a1db375a2bae36f3d527ab409c536f4acccc12873e4ab5966 \
# 	--node-name=$(hostname -f)

# Join the Kubernetes cluster as control plane node
# kubeadm join 10.0.0.245:6443 --token 8sst2z.yb2ycwje84g9c9wu \
# 	--discovery-token-ca-cert-hash sha256:991be94561034d9701af51f66f45bfdc5ab0142c85f3fbf3cb7f2197acc0f587 \
# 	--control-plane \
# 	--node-name=$(hostname -f)
