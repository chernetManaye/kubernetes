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
gpg \
jq \
wget

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

# Add the aws ebs csi driver repository
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

# Install the aws ebs csi driver
helm install aws-ebs-csi-driver \
  aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system

mkdir -p /home/ubuntu/manifests

# create a storage class and apply it to the cluster
cat > /home/ubuntu/manifests/storageclass.yaml <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
  csi.storage.k8s.io/fstype: ext4
  encrypted: "true"
EOF

kubectl apply -f /home/ubuntu/manifests/storageclass.yaml

# Add Karpenter here
CLUSTER_ENDPOINT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.13.0 \
  --namespace karpenter \
  --create-namespace \
  --set replicas=1 \
  --set controller.env[0].name=AWS_REGION \
  --set controller.env[0].value=eu-central-1 \
  --set settings.clusterName=kubernetes \
  --set settings.clusterEndpoint=$CLUSTER_ENDPOINT \
  --set settings.eksControlPlane=false \
  --set settings.interruptionQueue="" \
  --set serviceAccount.create=true \
  --set 'nodeSelector.node-role\.kubernetes\.io/control-plane=' \
  --set tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set tolerations[0].operator=Exists \
  --set tolerations[0].effect=NoSchedule \
  --set controller.resources.requests.cpu=200m \
  --set controller.resources.requests.memory=200Mi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait


# Generate the join command
export JOIN_COMMAND="$(kubeadm token create --print-join-command)"
# Prepend sudo and append node name substitution
export JOIN_COMMAND="sudo ${JOIN_COMMAND} --node-name=\$(hostname -f)"

echo "$JOIN_COMMAND"

cat > /home/ubuntu/manifests/ec2nodeclass.yaml <<'EOF'
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: Custom

  amiSelectorTerms:
    - id: ami-08ea642491f096f83

  role: worker-role

  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: kubernetes

  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: kubernetes


  tags:
    karpenter.sh/discovery: kubernetes
    Name: karpenter-node

  metadataOptions:
    httpEndpoint: enabled
    httpTokens: required
    httpPutResponseHopLimit: 4

  blockDeviceMappings:
    - deviceName: /dev/sda1
      ebs:
        volumeSize: 25Gi
        volumeType: gp3
        encrypted: true

  userData: |
    #!/bin/bash
    exec > >(tee /var/log/master-bootstrap.log | logger -t master-bootstrap) 2>&1
    set -euxo pipefail

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

    ${JOIN_COMMAND}
EOF


envsubst '${JOIN_COMMAND}' \
  < /home/ubuntu/manifests/ec2nodeclass.yaml \
  | kubectl apply -f -

cat > /home/ubuntu/manifests/nodepool.yaml <<'EOF'
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels:
        node-type: karpenter

    spec:
      startupTaints:
        - key: node.cilium.io/agent-not-ready
          effect: NoSchedule
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default

      expireAfter: 720h

      requirements:
        - key: kubernetes.io/arch
          operator: In
          values:
            - amd64

        - key: kubernetes.io/os
          operator: In
          values:
            - linux

        - key: karpenter.sh/capacity-type
          operator: In
          values:
            - on-demand

        - key: node.kubernetes.io/instance-type
          operator: In
          values:
            - t3.small
            - t3.micro
            - c7i-flex.large
            - m7i-flex.large

  limits:
    cpu: 100
    memory: 100Gi

  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m

  weight: 10
EOF

kubectl apply -f /home/ubuntu/manifests/nodepool.yaml

# Install NGINX Ingress Controller
helm install nginx-ingress oci://ghcr.io/nginx/charts/nginx-ingress --version 2.6.1 \
  --namespace kube-system \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type"="instance" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"="internet-facing"


# Add the external-dns repository
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update

# Install external-dns
helm install external-dns external-dns/external-dns \
  -n kube-system \
  --set provider.name=aws \
  --set policy=sync \
  --set registry=txt \
  --set txtOwnerId=mycluster \
  --set domainFilters[0]=shadoshops.com \
  --set env[0].name=AWS_DEFAULT_REGION \
  --set env[0].value=eu-central-1


# add the snashot controller repository
helm repo add piraeus https://piraeus.io/helm-charts/
helm repo update

# install the snapshot controller
helm install snapshot-controller piraeus/snapshot-controller -n kube-system

# create the volume snapshot class
cat > /home/ubuntu/manifests/volumesnapshotclass.yaml <<'EOF'
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ebs-snapshot-class
driver: ebs.csi.aws.com
deletionPolicy: Delete
EOF

# apply the volume snapshot class
kubectl apply -f /home/ubuntu/manifests/volumesnapshotclass.yaml
