## Encryption at Rest

```bash
# Create the encryption config directory
sudo mkdir -p /etc/kubernetes/encryption

# Generate the encryption key
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

# Create the encryption config file
sudo tee /etc/kubernetes/encryption/encryption-config.yaml > /dev/null <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration

resources:
- resources:
  - secrets

  providers:
  - aescbc:
      keys:
      - name: key1
        secret: ${ENCRYPTION_KEY}

  - identity: {}
EOF

# Set root read and write permissions
sudo chmod 600 /etc/kubernetes/encryption/encryption-config.yaml

# Create the kubeadm config directory
sudo mkdir -p /home/ubuntu/kubeadm

# Create the kubeadm config file
sudo tee /home/ubuntu/kubeadm/kubeadm-config.yaml > /dev/null <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration

clusterName: kubernetes
kubernetesVersion: v1.34.0

apiServer:
  extraArgs:
    - name: encryption-provider-config
      value: /etc/kubernetes/encryption-config.yaml
    - name: service-account-issuer
      value: https://oidc.example.com
    - name: service-account-issuer
      value: https://kubernetes.default.svc.cluster.local
    - name: service-account-jwks-uri
      value: https://oidc.example.com/openid/v1/jwks

  extraVolumes:
    - name: encryption-config
      hostPath: /etc/kubernetes/encryption-config.yaml
      mountPath: /etc/kubernetes/encryption-config.yaml
      readOnly: true
      pathType: File
EOF
sudo tee /home/ubuntu/kubeadm/kubeadm-config.yaml > /dev/null <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration

clusterName: kubernetes
kubernetesVersion: v1.34.0

EOF

sudo kubeadm init phase control-plane apiserver \
  --config /home/ubuntu/kubeadm/kubeadm-config.yaml

# Initialize control plane
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --skip-phases=addon/kube-proxy \
  --node-name=$(hostname -f) \
  --apiserver-cert-extra-sans="$(curl -s ifconfig.me)"

# make sure on the next commands 
# sudo systemctl enable containerd
# sudo systemctl start containerd
# sudo systemctl enable kubelet
# sudo systemctl start kubelet

kubectl create secret generic demo-secret \
    --from-literal=username=admin \
    --from-literal=password=supersecret123


sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
    
```
