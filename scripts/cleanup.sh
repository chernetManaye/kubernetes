#!/bin/bash
set -euxo pipefail

export KUBECONFIG=/etc/kubernetes/admin.conf

echo "===== Cleaning Kubernetes cluster ====="

#
# Delete workloads first
#
kubectl delete mongodbcommunity --all --all-namespaces --ignore-not-found || true
kubectl delete pvc --all --all-namespaces --ignore-not-found || true
kubectl delete pv --all --ignore-not-found || true

#
# Remove Karpenter resources
#
kubectl delete nodepool --all --ignore-not-found || true
kubectl delete ec2nodeclass --all --ignore-not-found || true

#
# Remove ingress services (this deletes AWS NLBs)
#
kubectl delete svc --all -A \
  --field-selector spec.type=LoadBalancer \
  --ignore-not-found || true

#
# Remove ExternalDNS
#
helm uninstall external-dns -n kube-system || true

#
# Remove NGINX Ingress
#
helm uninstall nginx-ingress -n kube-system || true

#
# Remove Karpenter
#
helm uninstall karpenter -n karpenter || true

#
# Remove AWS EBS CSI Driver
#
helm uninstall aws-ebs-csi-driver -n kube-system || true

#
# Remove AWS Cloud Controller Manager
#
helm uninstall aws-cloud-controller-manager -n kube-system || true

#
# Remove Cilium
#
helm uninstall cilium -n kube-system || true

#
# Wait until all LoadBalancers disappear
#
echo "Waiting for LoadBalancer Services to be deleted..."

while kubectl get svc -A --field-selector spec.type=LoadBalancer \
      --no-headers 2>/dev/null | grep -q .; do
    sleep 10
done

echo "Waiting for all PVCs..."

while kubectl get pvc -A --no-headers 2>/dev/null | grep -q .; do
    sleep 10
done

#
# Drain worker nodes
#
for node in $(kubectl get nodes -o name | grep -v control-plane || true); do
    kubectl drain "${node#node/}" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --force || true
done

#
# Reset workers if they still exist
#
for ip in $(kubectl get nodes -o wide --no-headers | awk '!/control-plane/{print $6}'); do
    ssh -o StrictHostKeyChecking=no ubuntu@$ip \
        "sudo kubeadm reset -f || true"
done

#
# Reset control plane
#
sudo kubeadm reset -f || true

#
# Remove Kubernetes configuration
#
rm -rf /etc/kubernetes
rm -rf ~/.kube
rm -rf /home/ubuntu/.kube

echo "===== Cleanup complete ====="
