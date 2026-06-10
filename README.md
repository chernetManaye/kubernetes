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
