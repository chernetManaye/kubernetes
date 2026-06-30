#!/bin/bash
exec > >(tee /var/log/master-bootstrap.log | logger -t master-bootstrap) 2>&1
set -euxo pipefail

# Install containerd
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

# Disable current swap
sudo swapoff -a

# Disable swap permanently (if swap exists in fstab)
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Enable kernel forwarding immediately
sudo sysctl -w net.ipv4.ip_forward=1

# Make kernel forwarding persistent
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/k8s.conf
sudo sysctl --system

# Install prerequisites
sudo apt-get update
sudo apt-get install -y \
apt-transport-https \
ca-certificates \
curl \
gpg

# Create directory for apt keyrings
sudo mkdir -p /etc/apt/keyrings

# Add Kubernetes repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | \
sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install Kubernetes tools
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

# Add this value KUBELET_EXTRA_ARGS="--cloud-provider=external" to /etc/default/kubelet
grep -q '^KUBELET_EXTRA_ARGS=' /etc/default/kubelet 2>/dev/null \
  && sudo sed -i 's|^KUBELET_EXTRA_ARGS=.*|KUBELET_EXTRA_ARGS="--cloud-provider=external"|' /etc/default/kubelet \
  || echo 'KUBELET_EXTRA_ARGS="--cloud-provider=external"' | sudo tee -a /etc/default/kubelet >/dev/null


# Helm installation prerequisites
HELM_KEY_ID="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"
TMP_KEY="${TMPDIR:-/tmp}/helm.gpg"

# Download the Helm GPG key
curl -fsSL \
  https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
  > "$TMP_KEY"

# Verify the key fingerprint
ACTUAL_KEY_ID=$(
  gpg --show-keys --with-colons "$TMP_KEY" \
    | awk -F: '$1 == "fpr" {print $10}' \
    | head -n 1
)

if [ "$ACTUAL_KEY_ID" != "$HELM_KEY_ID" ]; then
  echo "ERROR: Unexpected Helm APT key ID."
  exit 1
fi

# Install the key
gpg --dearmor < "$TMP_KEY" \
  | sudo tee /usr/share/keyrings/helm.gpg > /dev/null

# Add the Helm repository
echo \
  "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
  | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

# Install Helm
sudo apt-get update
sudo apt-get install -y helm

# Install container runtime interface CLI
sudo apt update
sudo apt install -y cri-tools

# Configure crictl
sudo tee /etc/crictl.yaml > /dev/null <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# Initialize control plane
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --skip-phases=addon/kube-proxy \
  --node-name=$(hostname -f) \
  --apiserver-cert-extra-sans="$(curl -s ifconfig.me)"

export KUBECONFIG=/home/ubuntu/.kube/config

# Configure kubectl for current user
echo "Finished kubeadm init"

mkdir -p /home/ubuntu/.kube
echo "Created .kube directory"

cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
echo "Copied kubeconfig"

chown ubuntu:ubuntu /home/ubuntu/.kube/config
echo "Changed ownership"

echo "About to install Cilium"

# Wait for control plane to be ready
until kubectl get nodes >/dev/null 2>&1; do
    sleep 5
done

# Install Cilium CNI
helm install cilium oci://quay.io/cilium/charts/cilium \
  --version 1.19.2 \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="$(hostname -I | awk '{print $1}')" \
  --set k8sServicePort=6443

# Wait for Cilium to be ready
# kubectl rollout status ds/cilium -n kube-system --timeout=10m

# Add AWS CCM repository
helm repo add aws-cloud-controller-manager https://kubernetes.github.io/cloud-provider-aws
helm repo update

# Install AWS CCM
helm install aws-cloud-controller-manager \
  aws-cloud-controller-manager/aws-cloud-controller-manager \
  --namespace kube-system \
  --set env[0].name=CLUSTER_NAME \
  --set env[0].value=kubernetes \
  --set env[1].name=AWS_REGION \
  --set env[1].value=eu-central-1 \
  --set args[0]=--v=2 \
  --set args[1]=--cloud-provider=aws \
  --set args[2]=--configure-cloud-routes=false

# Wait for AWS CCM to be ready
# kubectl rollout status deployment/aws-cloud-controller-manager -n kube-system --timeout=10m

# Install NGINX Ingress Controller
helm install nginx-ingress oci://ghcr.io/nginx/charts/nginx-ingress --version 2.6.1 \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type"="instance" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing"

# Add the aws ebs csi driver repository
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

# Install the aws ebs csi driver
helm install aws-ebs-csi-driver \
  aws-ebs-csi-driver/aws-ebs-csi-driver -n kube-system


# # Install the Kubernetes Dashboard
# helm repo add kubernetes-dashboard https://kubernetes-retired.github.io/dashboard/
# helm repo update
# helm upgrade --install kubernetes-dashboard \
#   kubernetes-dashboard/kubernetes-dashboard \
#   --namespace kubernetes-dashboard \
#   --create-namespace


# # Install container resource monitoring tools: Metrics Server, for real systems use grafana and prometheus
# helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
# helm repo update
# helm install metrics-server metrics-server/metrics-server \
#   -n kube-system


# # Install cluster level logging tools: Loki, Fluent-Bit, and Grafana
# helm repo add grafana https://grafana.github.io/helm-charts
# helm repo update

# helm install loki grafana/loki -n monitoring --create-namespace
# helm install fluent-bit grafana/fluent-bit -n monitoring
# helm install grafana grafana/grafana -n monitoring

# # Fluent Bit installation
# # resource: https://docs.fluentbit.io/manual/installation/downloads/kubernetes
# helm repo add fluent https://fluent.github.io/helm-charts
# helm upgrade --install fluent-bit fluent/fluent-bit
