# --------------------------------------------------
# 1. Install containerd
# --------------------------------------------------
sudo apt-get update
sudo apt-get install -y containerd

# Generate default config
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# Use systemd cgroups (recommended by Kubernetes)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Start and enable containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# --------------------------------------------------
# 2. Disable swap
# --------------------------------------------------

# Disable current swap
sudo swapoff -a

# Disable swap permanently (if swap exists in fstab)
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# --------------------------------------------------
# 3. Enable kernel forwarding
# --------------------------------------------------

# Enable immediately
sudo sysctl -w net.ipv4.ip_forward=1

# Make persistent
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/k8s.conf
sudo sysctl --system


# --------------------------------------------------
# 4. Install prerequisites
# --------------------------------------------------
sudo apt-get update
sudo apt-get install -y \
apt-transport-https \
ca-certificates \
curl \
gpg


# --------------------------------------------------
# 5. Add Kubernetes repository
# --------------------------------------------------

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | \
sudo tee /etc/apt/sources.list.d/kubernetes.list


# --------------------------------------------------
# 6. Install Kubernetes tools
# --------------------------------------------------
sudo apt-get update

sudo apt-get install -y \
kubelet \
kubeadm \
kubectl

# Prevent automatic upgrades
sudo apt-mark hold \
kubelet \
kubeadm \
kubectl

# --------------------------------------------------
# 7. Initialize control plane
# --------------------------------------------------

sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --apiserver-cert-extra-sans="$(curl -s ifconfig.me)"

# --------------------------------------------------
# 8. Configure kubectl for current user
# --------------------------------------------------
mkdir -p $HOME/.kube

sudo cp /etc/kubernetes/admin.conf \
$HOME/.kube/config

sudo chown $(id -u):$(id -g) \
$HOME/.kube/config

# --------------------------------------------------
# 10. Install Calico (stable operator install)
# --------------------------------------------------
kubectl create -f \
https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/v1_crd_projectcalico_org.yaml

kubectl create -f \
https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/tigera-operator.yaml

kubectl create -f \
https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/custom-resources.yaml
