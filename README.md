# Kubernetes Cluster Setup Overview

Learning Kubernetes with Minikube is useful for understanding concepts, but it can hide many of the steps involved in setting up a real cluster. Working with actual virtual machines provides a better understanding of how Kubernetes is deployed in production environments.

## Scenario

For this demonstration, we use Amazon EC2 instances to build a Kubernetes cluster.

### Cluster Components

- 1 Control Plane Node
- 1 or more Worker Nodes

### Setup Process

1. Provision EC2 instances for the control plane and worker nodes.
2. Install the required Kubernetes components on all nodes:
   - containerd (container runtime)
   - kubeadm
   - kubelet
   - kubectl (typically installed on the control plane)
3. Initialize the Kubernetes cluster on the control plane node:

   ```bash
   kubeadm init



# Deploying Applications in Kubernetes

There are two common ways to create a Deployment in Kubernetes:

1. Imperative Approach (Commands)
2. Declarative Approach (YAML Files)

The imperative approach is useful for learning and quick testing, while the declarative approach is the standard method used in production environments.

---

# Imperative Approach

The simplest way to create a Deployment is by using a command.

## Create a Deployment

```bash
kubectl create deployment nginx --image=nginx:latest
```

## Verify the Deployment

```bash
kubectl get deployments
kubectl get pods
```

## Scale the Deployment

```bash
kubectl scale deployment nginx --replicas=3
```

## Expose the Deployment as a Service

```bash
kubectl expose deployment nginx \
  --type=NodePort \
  --port=80
```

## Limitations

As applications become more complex, additional configuration is required:

- Multiple replicas
- Labels and selectors
- Resource requests and limits
- Environment variables
- Volumes
- Health checks
- Service configuration

Managing all of these options through commands becomes difficult and hard to maintain.

---

# Declarative Approach (Recommended)

Instead of passing many command-line options, Kubernetes resources are defined in YAML files.

## Create deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment

metadata:
  name: nginx

spec:
  replicas: 3

  selector:
    matchLabels:
      app: nginx

  template:
    metadata:
      labels:
        app: nginx

    spec:
      containers:
      - name: nginx
        image: nginx:latest

        ports:
        - containerPort: 80
```

## Apply the Configuration

```bash
kubectl apply -f deployment.yaml
```

## Verify the Deployment

```bash
kubectl get deployments
kubectl get pods
```

## View Detailed Information

```bash
kubectl describe deployment nginx
```

---

# Updating the Deployment

Modify the deployment.yaml file.

For example:

```yaml
spec:
  replicas: 5
```

Apply the changes:

```bash
kubectl apply -f deployment.yaml
```

Verify the update:

```bash
kubectl get deployments
```

---

# Deleting the Deployment

Delete using the YAML file:

```bash
kubectl delete -f deployment.yaml
```

Or delete directly:

```bash
kubectl delete deployment nginx
```

---

# Why YAML Files Are Preferred

YAML files provide several advantages:

- Easy to read and maintain
- Can be stored in Git repositories
- Supports version control
- Easy collaboration among team members
- Reproducible deployments
- Works well with CI/CD pipelines
- Industry-standard approach for Kubernetes deployments

For small experiments, imperative commands are sufficient. For real-world Kubernetes environments, YAML files are the preferred approach because they are maintainable, reusable, and version controlled.



## Kubernetes Cheat Sheet

## Cluster Information

### Show all nodes

```bash
kubectl get nodes
```

### Show cluster information

```bash
kubectl cluster-info
```

### Show all resources in the current namespace

```bash
kubectl get all
```

---

## Namespace Commands

### List all namespaces

```bash
kubectl get ns
```

### List pods in all namespaces

```bash
kubectl get pods -A
```

### List pods in current namespace

```bash
kubectl get pods
```

### List pods in a specific namespace

```bash
kubectl get pods -n kube-system
```

---

## Join Worker Nodes

### Generate a join command

```bash
kubeadm token create --print-join-command
```

### Join a worker node

```bash
kubeadm join <CONTROL_PLANE_IP>:6443 \
--token <TOKEN> \
--discovery-token-ca-cert-hash sha256:<HASH>
```

---

## Common Resource Commands

### Get resources

```bash
kubectl get pods
kubectl get deployments
kubectl get replicasets
kubectl get services
```

### Resource short names

```bash
kubectl get po      # Pods
kubectl get deploy  # Deployments
kubectl get rs      # ReplicaSets
kubectl get ns      # Namespaces
kubectl get svc     # Services
```

---

## Pod Troubleshooting

### View logs

```bash
kubectl logs <POD_NAME>
```

### Describe a resource

```bash
kubectl describe <RESOURCE_TYPE> <RESOURCE_NAME>
```

### Execute a command inside a container

```bash
kubectl exec -it <POD_NAME> -- <COMMAND>
```

Example:

```bash
kubectl exec -it nginx-pod -- /bin/bash
```

---

## Working with Namespaces

### View logs

```bash
kubectl logs <POD_NAME> -n <NAMESPACE>
```

### Describe a resource

```bash
kubectl describe <RESOURCE_TYPE> <RESOURCE_NAME> -n <NAMESPACE>
```

### Execute commands in a namespace

```bash
kubectl exec -it <POD_NAME> -n <NAMESPACE> -- <COMMAND>
```

---

## CRUD Operations

### Create a resource

```bash
kubectl create <RESOURCE_TYPE> <RESOURCE_NAME> --image=<IMAGE_NAME>:<TAG>
```

Example:

```bash
kubectl create deployment nginx --image=nginx:latest
```

### Create resources from YAML

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
```

### Read resources

```bash
kubectl get <RESOURCE_TYPE>
kubectl get <RESOURCE_TYPE> <RESOURCE_NAME>
```

### Update a resource

```bash
kubectl edit <RESOURCE_TYPE> <RESOURCE_NAME>
```

Example:

```bash
kubectl edit deployment nginx
```

### Update using YAML

```bash
kubectl apply -f deployment.yaml
```

### Delete a resource

```bash
kubectl delete <RESOURCE_TYPE> <RESOURCE_NAME>
```

Example:

```bash
kubectl delete deployment nginx
```

---

## Control Plane Recovery

### Recreate all control plane components

```bash
sudo kubeadm init phase control-plane all
```

### Recreate only the API Server

```bash
sudo kubeadm init phase control-plane apiserver
```

---

## High Availability (HA)

### Initialize using a load balancer

```bash
sudo kubeadm init \
--control-plane-endpoint "k8s.example.com:6443"
```

### Upload certificates

```bash
kubeadm init phase upload-certs --upload-certs
```

### Generate a join command

```bash
kubeadm token create --print-join-command
```

### Join an additional control plane

```bash
kubeadm join <LOAD_BALANCER>:6443 \
--token <TOKEN> \
--discovery-token-ca-cert-hash sha256:<HASH> \
--control-plane \
--certificate-key <CERTIFICATE_KEY>
```


## For HA setup
```bash

sudo kubeadm init \
--control-plane-endpoint "k8s.example.com:6443"

# Generate certificates
kubeadm init phase upload-certs --upload-certs
# Generate join command
kubeadm token create --print-join-command
# Add control-plane flag to join command
--control-plane
# Add certificate key to join command
--certificate-key
# The final join command for control plane
kubeadm join LB:6443 \
--token xxx \
--discovery-token-ca-cert-hash sha256:xxx \
--control-plane \
--certificate-key yyy
```

Always use an odd number of control plane nodes to maintain etcd quorum.

```text
1 → 3 → 5 → 7
```
---

## Secret Encryption at Rest

### Generate encryption key

```bash
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
```

### Create encryption configuration

```bash
sudo tee /etc/kubernetes/encryption-config.yaml > /dev/null <<EOF
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
```
---

### Add encryption provider config to kube-apiserver

```bash
# Backup the kube-apiserver.yaml manifest
sudo cp \
/etc/kubernetes/manifests/kube-apiserver.yaml \
/etc/kubernetes/manifests/kube-apiserver.yaml.bak

# Add the k8s-config volumeMount to the kube-apiserver manifest
sudo sed -i '/mountPath: \/etc\/kubernetes\/pki/a\
    - mountPath: /etc/kubernetes\
      name: k8s-config\
      readOnly: true' \
/etc/kubernetes/manifests/kube-apiserver.yaml

# Add the k8s-config volume to the kube-apiserver manifest
sudo sed -i '/name: k8s-certs/a\
  - hostPath:\
      path: /etc/kubernetes\
      type: Directory\
    name: k8s-config' \
/etc/kubernetes/manifests/kube-apiserver.yaml

# Add API server flag
sudo sed -i '/kube-apiserver/a\    - --encryption-provider-config=/etc/kubernetes/encryption-config.yaml' \
/etc/kubernetes/manifests/kube-apiserver.yaml

# Add flag
grep -q encryption-provider-config \
/etc/kubernetes/manifests/kube-apiserver.yaml || \
sudo sed -i '/- kube-apiserver/a\
    - --encryption-provider-config=/etc/kubernetes/encryption-config.yaml' \
/etc/kubernetes/manifests/kube-apiserver.yaml

```
### Restart kube-apiserver after updating the manifest

The kubelet will automatically restart the static pod when the manifest changes.
