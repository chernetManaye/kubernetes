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

# Public IP of the node
PUBLIC_IP=$(curl -s ifconfig.me)
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Create the kubeadm config file
sudo tee /home/ubuntu/kubeadm/kubeadm-config.yaml > /dev/null <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration

clusterName: kubernetes
kubernetesVersion: v1.34.0

networking:
  podSubnet: 192.168.0.0/16

apiServer:
  certSANs:
    - ${PUBLIC_IP}    # public IP
    - ${PRIVATE_IP}   # private IP

  extraArgs:
    - name: encryption-provider-config
      value: /etc/kubernetes/encryption/encryption-config.yaml
    - name: service-account-issuer
      value: https://oidc.shadoshops.com
    - name: service-account-issuer
      value: https://kubernetes.default.svc.cluster.local
    - name: service-account-jwks-uri
      value: https://oidc.shadoshops.com/openid/v1/jwks

  extraVolumes:
    - name: encryption-config
      hostPath: /etc/kubernetes/encryption
      mountPath: /etc/kubernetes/encryption
      readOnly: true
      pathType: DirectoryOrCreate
EOF


# Initialize control plane
sudo kubeadm init \
  --config /home/ubuntu/kubeadm/kubeadm-config.yaml \
  --skip-phases=addon/kube-proxy \
  --node-name=$(hostname -f) 
# sudo systemctl enable containerd
# sudo systemctl start containerd
# sudo systemctl enable kubelet
# sudo systemctl start kubelet

kubectl create secret generic demo-secret \
    --from-literal=username=admin \
    --from-literal=password=supersecret123

kubectl create secret generic demo \
  --from-literal=password=supersecret

sudo crictl ps | grep etcd

sudo crictl exec -it c356fb874a84a \
etcdctl \
--cacert=/etc/kubernetes/pki/etcd/ca.crt \
--cert=/etc/kubernetes/pki/etcd/server.crt \
--key=/etc/kubernetes/pki/etcd/server.key \
get /registry/secrets/default/demo

sudo ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
    
```

## Cleanup tools

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes/manifests
sudo rm -rf /var/lib/etcd
sudo rm -rf /etc/cni/net.d
sudo systemctl restart kubelet
sudo ss -ltnp | egrep '2379|2380|10250|10257|10259|6443'
```
