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
