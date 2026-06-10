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

# Check kubectl version
which kubectl
# Check kubectl version (client)
kubectl version --client
# --------------------------------------------------
# 7. Initialize control plane
# --------------------------------------------------

sudo kubeadm init \
--pod-network-cidr=192.168.0.0/16

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


# --------------------------------------------------
# 11. Wait for Calico
# --------------------------------------------------
# kubectl get tigerastatus

sleep 120
# --------------------------------------------------
# 12. Verify cluster health
# --------------------------------------------------
kubectl get nodes

kubectl get pods -A

kubectl cluster-info


kubeadm token create --print-join-command

kubeadm join <CONTROL_PLANE_IP>:6443 \
--token <TOKEN> \
--discovery-token-ca-cert-hash sha256:<HASH>


kubectl get all
kubectl get po    # kubectl get pods
kubectl get deploy # kubectl get deployments
kubectl get rs    # kubectl get replicasets
kubectl get ns    # kubectl get namespaces
kubectl get svc   # kubectl get services

kubectl logs <POD_NAME>
kubectl describe <RESOURCE_TYPE> <RESOURCE_NAME>
kubectl exec -it <POD_NAME> -- <COMMAND>

# CRUD operations
# Create operations
kubectl create <RESOURCE_TYPE> <RESOURCE_NAME> image=<IMAGE_NAME>:<TAG>
# Scalable approaches we write a YAML file and apply it
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
# Read operations
kubectl get <RESOURCE_TYPE> <RESOURCE_NAME>
# Update operations
kubectl edit <RESOURCE_TYPE> <RESOURCE_NAME>
# Delete operations
kubectl delete <RESOURCE_TYPE> <RESOURCE_NAME>


# kubectl logs <POD_NAME> -n <NAMESPACE>
# kubectl describe <RESOURCE_TYPE> <RESOURCE_NAME> -n <NAMESPACE>
# kubectl exec -it <POD_NAME> -n <NAMESPACE> -- <COMMAND>
# If something crashes
# sudo kubeadm init phase control-plane all
# sudo kubeadm init phase control-plane apiserver


# # For HA setup
# sudo kubeadm init \
# --control-plane-endpoint "k8s.example.com:6443"
# # Generate certificates
# kubeadm init phase upload-certs --upload-certs
# # Generate join command
# kubeadm token create --print-join-command
# # Add control-plane flag to join command
# --control-plane
# # Add certificate key to join command
# --certificate-key
# # The final join command for control plane
# kubeadm join LB:6443 \
# --token xxx \
# --discovery-token-ca-cert-hash sha256:xxx \
# --control-plane \
# --certificate-key yyy
# Always follow the odd number rule for control plane 1 > 3 > 5 > ...
#
# --------------------------------------------------
# 9. Generate key + create config
# --------------------------------------------------
# ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

# sudo tee /etc/kubernetes/encryption-config.yaml > /dev/null <<EOF
# apiVersion: apiserver.config.k8s.io/v1
# kind: EncryptionConfiguration
# resources:
#   - resources:
#       - secrets
#     providers:
#       - aescbc:
#           keys:
#             - name: key1
#               secret: ${ENCRYPTION_KEY}
#       - identity: {}
# EOF

# # Backup the kube-apiserver.yaml manifest
# sudo cp \
# /etc/kubernetes/manifests/kube-apiserver.yaml \
# /etc/kubernetes/manifests/kube-apiserver.yaml.bak

# # Add the k8s-config volumeMount to the kube-apiserver manifest
# sudo sed -i '/mountPath: \/etc\/kubernetes\/pki/a\
#     - mountPath: /etc/kubernetes\
#       name: k8s-config\
#       readOnly: true' \
# /etc/kubernetes/manifests/kube-apiserver.yaml

# # Add the k8s-config volume to the kube-apiserver manifest
# sudo sed -i '/name: k8s-certs/a\
#   - hostPath:\
#       path: /etc/kubernetes\
#       type: Directory\
#     name: k8s-config' \
# /etc/kubernetes/manifests/kube-apiserver.yaml

# # Add API server flag
# sudo sed -i '/kube-apiserver/a\    - --encryption-provider-config=/etc/kubernetes/encryption-config.yaml' \
# /etc/kubernetes/manifests/kube-apiserver.yaml

# # Add flag
# grep -q encryption-provider-config \
# /etc/kubernetes/manifests/kube-apiserver.yaml || \
# sudo sed -i '/- kube-apiserver/a\
#     - --encryption-provider-config=/etc/kubernetes/encryption-config.yaml' \
# /etc/kubernetes/manifests/kube-apiserver.yaml

# Worker node

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

# Commands
kubeadm join 172.31.38.208:6443 --token hujm01.fb1lvp4e62vz9hy8 --discovery-token-ca-cert-hash sha256:516bf3dfef3c400804251ce0023c73f09057b52f8b388f3f1a11899b3b81fb5f
# Initialize Kubernetes control plane
kubeadm init
# Create join command for worker nodes
kubeadm token create --print-join-command
# Join worker nodes to the cluster
kubeadm join <CONTROL_PLANE_IP>:6443 \
--token <TOKEN> \
--discovery-token-ca-cert-hash sha256:<HASH>
# Example
kubeadm join 172.31.38.208:6443 \
--token hujm01.fb1lvp4e62vz9hy8 \
--discovery-token-ca-cert-hash sha256:516bf3dfef3c400804251ce0023c73f09057b52f8b388f3f1a11899b3b81fb5f


kubectl get nodes
kubectl get pods
kubectl get pods -A



# get namespaces
kubectl get ns

# get pods in all namespaces
kubectl get pods -A

# get pods in default namespace
kubectl get pods

# get pods in kube-system namespace
kubectl get pods -n kube-system
