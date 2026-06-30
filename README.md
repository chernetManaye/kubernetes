# Setting up kuberenetes cluster in aws 

## 1, Ensure each EC2 instance resolves its own FQDN correctly (hostname -f) using AWS internal DNS, and explicitly pass that FQDN to kubeadm with --node-name=$(hostname -f) during both kubeadm init and kubeadm join. This guarantees that kubelet registers the node with a consistent and resolvable name, avoiding hostname-related issues in the cluster.

### Node FQDN and DNS Configuration

Kubernetes relies on each node having a unique and resolvable hostname. In AWS, every EC2 instance should resolve its Fully Qualified Domain Name (FQDN) using:

```bash
hostname -f
```
The expected output should resemble:
```bash 
ip-10-0-0-15.eu-central-1.compute.internal
```
not:
```bash
ip-10-0-0-15
```
To ensure this works, the AWS networking infrastructure must be configured to provide internal DNS resolution.

### VPC
Enable both DNS resolution and DNS hostnames:

```hcl
enable_dns_support   = true
enable_dns_hostnames = true
```
### Subnet
Ensure newly launched instances receive DNS A-records:

```hcl
enable_resource_name_dns_a_record_on_launch = true
```

### EC2 Instance

Configure the instance to use the AWS IP-based hostname format and register a DNS A-record:

```hcl
private_dns_name_options {
  hostname_type                     = "ip-name"
  enable_resource_name_dns_a_record = true
}
```
After provisioning, verify that the instance resolves its own FQDN correctly:

```bash
hostname -f
```
If the command does not return the expected AWS internal FQDN, fix the DNS configuration before initializing the Kubernetes cluster.

Finally, explicitly register the node with its FQDN during cluster creation:

```bash
kubeadm init \
  --node-name=$(hostname -f)
```
and when joining additional nodes:

```bash
kubeadm join ... \
  --node-name=$(hostname -f)
```
Using the node's FQDN ensures that kubelet registers each node with a consistent and resolvable name, avoiding hostname-related issues within the cluster.

## 2, Configure EC2 instances to use IMDSv2 by enabling the metadata endpoint and requiring session tokens. In this deployment, the default metadata hop limit was insufficient for Kubernetes components running inside containers to access the Instance Metadata Service. Setting http_put_response_hop_limit = 4 allowed AWS-integrated components (such as the EBS CSI Driver) to retrieve instance metadata successfully. Lower values (1 and 2) did not work in this environment.

Terraform configuration:

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required" # Use IMDSv2
  http_put_response_hop_limit = 4          # Required in this cluster
}
```

## 3, Tag AWS resources with the cluster identifier. Tag EC2 instances, subnets, security groups, and any other AWS resources that Kubernetes integrations depend on using:

```hcl
kubernetes.io/cluster/<cluster-name> = "owned"
# Public subnet
kubernetes.io/role/elb            = "1"
# Private subnet
kubernetes.io/role/internal-elb   = "1"
```
(or shared for resources managed outside the cluster). These tags allow AWS-integrated Kubernetes components to discover and associate the correct infrastructure with the cluster. Public and private subnets should also be tagged with the appropriate ELB role tags (kubernetes.io/role/elb or kubernetes.io/role/internal-elb) so AWS load balancers can be provisioned in the correct subnets.

## 4, Configure IAM Roles and Permissions

Each EC2 instance must be associated with an IAM role that grants the permissions required by the AWS components running on that node.

In this cluster:

The control plane uses an IAM role with permissions required by the AWS Cloud Controller Manager (CCM), including EC2, Auto Scaling, Elastic Load Balancing, and other infrastructure APIs.
Both the control plane and worker nodes are attached to the managed AWS policy:
```
AmazonEBSCSIDriverPolicyV2
```
This policy allows the AWS EBS CSI Driver to create, attach, detach, modify, and delete Amazon EBS volumes on behalf of Kubernetes.

Without the appropriate IAM roles, AWS-integrated Kubernetes components will fail to communicate with AWS APIs, resulting in errors when provisioning storage or managing cloud resources.

## Steps 

1, Provision with Terraform

```powershell
cd terraform
terraform init
terraform plan
terraform apply --auto-approve
```
2, SSH into the control plane node

3, Get the userdata logs saved in /var/log/master-bootstrap.log
sudo kubeadm join 10.0.0.59:6443 --token ut60zn.lyuh6p8xn6egzomv \
	--discovery-token-ca-cert-hash sha256:44e9b3ceb956ed3c58c8b8b3fdfe32376dd5f50448df13ad894a272e02ad9368 \
	--node-name=$(hostname -f)
```bash
sudo cat /var/log/master-bootstrap.log
```
then get the generated join token and copy it to the clipboard
```bash
kubeadm join 18.185.239.164:6443 --token 774yb5.9phbt6tphz8mjysc \
	--discovery-token-ca-cert-hash sha256:5bf2e9829bc6267a1db375a2bae36f3d527ab409c536f4acccc12873e4ab5966 
```
and modify it to add the `--node-name` flag and sudo at the start and put it somewhere safe

```bash
sudo kubeadm join 18.185.239.164:6443 --token 774yb5.9phbt6tphz8mjysc \
	--discovery-token-ca-cert-hash sha256:5bf2e9829bc6267a1db375a2bae36f3d527ab409c536f4acccc12873e4ab5966 \
	--node-name=$(hostname -f)
```
2, SSH into the worker node and run the join command

```bash
sudo kubeadm join 18.185.239.164:6443 --token 774yb5.9phbt6tphz8mjysc \
	--discovery-token-ca-cert-hash sha256:5bf2e9829bc6267a1db375a2bae36f3d527ab409c536f4acccc12873e4ab5966 \
	--node-name=$(hostname -f)
```
Then when you ssh again in the control plane and the next commands you will see these

```bash
ubuntu@ip-10-0-0-59:~$ kubectl get nodes
NAME                                          STATUS     ROLES           AGE     VERSION
ip-10-0-0-239.eu-central-1.compute.internal   NotReady   <none>          19s     v1.34.9
ip-10-0-0-59.eu-central-1.compute.internal    Ready      control-plane   2m54s   v1.34.9
ubuntu@ip-10-0-0-59:~$ kubectl get pods -A
NAMESPACE       NAME                                                                 READY   STATUS              RESTARTS   AGE
ingress-nginx   nginx-ingress-controller-5f5dc54899-wtcnb                            0/1     Pending             0          2m52s
kube-system     aws-cloud-controller-manager-6zs8z                                   1/1     Running             0          2m17s
kube-system     cilium-envoy-jfvqs                                                   0/1     Running             0          27s
kube-system     cilium-envoy-jmpks                                                   1/1     Running             0          2m54s
kube-system     cilium-operator-754db45cb7-7x4pp                                     1/1     Running             0          2m54s
kube-system     cilium-operator-754db45cb7-cj9g6                                     1/1     Running             0          2m54s
kube-system     cilium-prhdg                                                         1/1     Running             0          2m54s
kube-system     cilium-vphvm                                                         0/1     Running             0          27s
kube-system     coredns-66bc5c9577-hqrnj                                             1/1     Running             0          2m54s
kube-system     coredns-66bc5c9577-qcwxs                                             1/1     Running             0          2m54s
kube-system     ebs-csi-controller-767c89688b-8wkp2                                  0/5     Pending             0          2m50s
kube-system     ebs-csi-controller-767c89688b-mr67z                                  0/5     Pending             0          2m50s
kube-system     ebs-csi-node-d8h2c                                                   0/3     ContainerCreating   0          27s
kube-system     ebs-csi-node-nsgvr                                                   3/3     Running             0          2m50s
kube-system     etcd-ip-10-0-0-59.eu-central-1.compute.internal                      1/1     Running             0          2m58s
kube-system     kube-apiserver-ip-10-0-0-59.eu-central-1.compute.internal            1/1     Running             0          2m58s
kube-system     kube-controller-manager-ip-10-0-0-59.eu-central-1.compute.internal   1/1     Running             0          2m58s
kube-system     kube-scheduler-ip-10-0-0-59.eu-central-1.compute.internal            1/1     Running             0          2m58s
ubuntu@ip-10-0-0-59:~$
```
#### eventually pending will become running and notReady becomes Ready, Now you can host any kind of application wheather it is a statefull or stateless application and the cluster can manage it safely and efficiently.


# Kubernetes
to deeply understand kuberenetes we should focus on 3 main lessons 
1, kubernetes architecture
2, kubernetes components
3, kuberenetes objects

## 2, kubernetes components
## Control Plane Components vs Node Components

When Kubernetes documentation refers to **control plane components** and **node components**, it is classifying them based on **their responsibility**, **not the machine they run on**.

### Control Plane Components

Control plane components are responsible for **managing the entire Kubernetes cluster**. They make cluster-wide decisions, maintain the desired state, schedule workloads, and coordinate resources across all nodes.

Examples:
- kube-apiserver
- kube-scheduler
- etcd
- kube-controller-manager
- cloud-controller-manager

### Node Components

Node components are responsible for **managing a single node**. They ensure that Pods and containers run correctly and that networking and runtime functionality work on that specific machine.

Examples:
- kubelet
- kube-proxy
- container runtime (e.g., containerd)

## Important Note

The terms **control plane component** and **node component** describe **what the component does**, **not where it runs**.

A node component can run on a control plane machine and still be a **node component** because its responsibility is limited to that single node.

For example, `kube-proxy` and `kubelet` often run on control plane nodes. They are **not** considered control plane components because they do not manage the cluster as a whole. Instead, they manage the operation of the individual node on which they are running.

In short:

- **Control plane components → manage the entire cluster.**
- **Node components → manage an individual node.**

#### kube-proxy
This component uses the Linux kernel's iptables or IPVS to manage network traffic. and falls back to nftables if iptables is not available. and even falls back to it's own internal load balancing mechanism if pocket-forwarding feature are not available in the os.
- **iptables**: The default networking tool for Linux.
- **IPVS**: A more advanced networking tool that supports load balancing and high availability.
- **nftables**: A newer networking tool that replaces iptables.
kube-proxy is deployed as a DaemonSet

#### cloud-controller-manager
In-Tree vs Out-of-Tree Cloud Providers
Older versions of Kubernetes included **in-tree** cloud providers, where cloud-specific code (such as AWS integration) was built directly into Kubernetes.

Modern Kubernetes uses **out-of-tree** cloud providers, where cloud functionality is handled by an external component called the **Cloud Controller Manager (CCM)**. This keeps Kubernetes modular and allows cloud integrations to be updated independently.

To use an external cloud provider, the kubelet must be started with:

```bash
--cloud-provider=external
```

This flag disables the legacy in-tree cloud provider and tells Kubernetes to rely on the external Cloud Controller Manager for cloud-specific operations such as node initialization and provisioning `LoadBalancer` services.

There are requirements for the aws CCM to function correctly:

1, The AWS ec2 instances must be configured with the correct AWS credentials and permissions.
2, aws resources must be tagged with the correct labels and annotations.
3, for IMDSv2 we have to set the hop limit to 4

Note: Karpenter
- **Karpenter is an open-source Kubernetes node provisioning system developed by Amazon Web Services (AWS).**

## Cluster-Level Logging

The simplest and most widely adopted logging approach for containerized applications is to write logs to **standard output (`stdout`)** and **standard error (`stderr`)**.

In Kubernetes, logs should have a storage location and lifecycle that are **independent of Pods, containers, and nodes**. This concept is known as **cluster-level logging**.

### How logging works in Kubernetes

1. The application writes logs to `stdout` and `stderr`.
2. The container runtime captures these streams and stores them as log files on the node.
3. The kubelet exposes these logs through the Kubernetes API.
4. `kubectl logs` retrieves the logs from the kubelet.

> **Note:** By default, Kubernetes retains logs for the **currently running container** and **one previous terminated instance**. If a Pod is deleted or evicted from a node, its local logs are typically removed unless a cluster-level logging solution has already collected them.

### Using `kubectl logs`

```bash
# Show logs from a Pod with a single container
kubectl logs <pod-name>

# Show logs from the previous instance of a restarted container
kubectl logs <pod-name> --previous

# Stream logs from a running container in real time
kubectl logs -f <pod-name>

# Stream logs from a specific container in a multi-container Pod
kubectl logs -f <pod-name> -c <container-name>

# Show logs from a specific container in a multi-container Pod
kubectl logs <pod-name> -c <container-name>

# Show logs from the previous instance of a specific container
kubectl logs <pod-name> -c <container-name> --previous
```

> **Note:** `--previous` cannot be combined with `-f` because a terminated container no longer produces log output to follow.

### Kubelet log rotation

The kubelet manages container log rotation using settings such as:

```yaml
containerLogMaxSize: 10Mi
containerLogMaxFiles: 5
containerLogMaxWorkers: 1
containerLogMonitorInterval: 10s
```

These settings are configured on each node in the kubelet configuration file:

```text
/var/lib/kubelet/config.yaml
```

By default, container logs are stored on the node under:

```text
/var/log/pods/
```

`kubectl logs` ultimately reads from these kubelet-managed log files.

### Common cluster-level logging architectures

There are three common approaches to implementing cluster-level logging:

1. **Node-level logging agent**
   - A logging agent runs on every node (typically as a DaemonSet).
   - It reads container log files from the node and forwards them to a centralized logging backend.

2. **Sidecar logging container**
   - A dedicated sidecar container runs alongside the application container.
   - It collects or forwards logs generated by that specific Pod.

3. **Application-managed logging**
   - The application itself pushes logs directly to a logging backend or external service.

In this project, we will focus only on the **node-level logging agent** approach.

### Logging stack used in this project

We will use the following components:

1. **Fluent Bit**
   - Runs as a DaemonSet on every Kubernetes node.
   - Reads container log files from the node (typically from `/var/log/pods/`).
   - Forwards the collected logs to Grafana Loki.

2. **Grafana Loki**
   - Acts as the centralized log aggregation system.
   - Receives logs from Fluent Bit and stores them efficiently for querying.

3. **Grafana**
   - Connects to Loki as a data source.
   - Provides a web interface for searching, filtering, and visualizing logs.

### Architecture

```
Application
      │
      ▼
stdout / stderr
      │
      ▼
Container Runtime
      │
      ▼
/var/log/pods/
      │
      ▼
Fluent Bit (DaemonSet)
      │
      ▼
Grafana Loki
      │
      ▼
Grafana
      │
      ▼
Search, dashboards, and log exploration
```

## 3, kuberenetes objects
The official definition: Kubernetes objects are persistent entities in the Kubernetes system. Kubernetes uses these entities to represent the state of your cluster.

kubernetes have more than 70+ types of objects. the most basics ones are:
1.Pod
2.Deployment
3.ReplicaSet

``` bash
# Stream logs in real time
kubectl logs -f <pod-name> -c <container-name>

# Show logs from the previous instance of a restarted container
kubectl logs --previous <pod-name> -c <container-name>

# Show logs if the pod has only one container
kubectl logs <pod-name> 
```
4.StatefulSet
5.DaemonSet
# 6. Service

A **Service** in Kubernetes provides:

1. A **stable virtual IP address** (**ClusterIP**)
2. A **stable DNS name** (**Service DNS**)
3. **Load balancing** across multiple Pods

## Types of Services

### 1. ClusterIP
- Default Service type.
- Provides one stable virtual IP.
- Accessible only from within the Kubernetes cluster.
- Load-balances traffic across the matching Pods. This behavior will be overridden by the Ingress controller. when we add ingress controller and configure it with ingress rules, the ingress controller will use the service to discover the endpoints (Pod IPs) and route traffic to them. this will remove the additional load balancing layer provided by the Service and make the traffic flow directly to the Pods.

### 2. NodePort
- Exposes the Service on a fixed port on every Kubernetes node.
- Can be accessed externally using:
  ```
  <NodeIP>:<NodePort>
  ```
- Commonly used for development, testing, or environments without a cloud load balancer.
- 30000–32767 the default range for NodePort.

### 3. LoadBalancer
- Creates an external load balancer through the cloud provider.
- Makes the Service accessible from outside the cluster using a public IP or DNS name.
- Routes incoming traffic to the underlying Pods.

### 4. ExternalName
- Does not expose Pods.
- Creates a DNS alias that maps the Service name to an external hostname.
- Useful for accessing services that are outside the Kubernetes cluster.

### 5. Headless Service
- Configured with:
  ```yaml
  clusterIP: None
  ```
- Does not create a virtual IP.
- Does not perform load balancing.
- DNS queries return the individual IP addresses of the backing Pods directly.
- Commonly used with StatefulSets and distributed applications.

## 7. Ingress

It is a Kubernetes resource that manages external access to services within a cluster.

                Internet
                    │
                    ▼
          +-------------------+
          | Ingress Controller |
          +-------------------+
              │            │
              │            │
              ▼            ▼
          frontend-svc    api-svc
              │            │
              ▼            ▼
          Frontend      Backend Pods
          
8.ConfigMap
9.Secret
10.PersistentVolume (PV)
11.PersistentVolumeClaim (PVC)
12.StorageClass
13.Namespace
14.Job
15.CronJob

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
```
### kubeadm
- it is an open-source tool for bootstrapping Kubernetes clusters(it is an automation tool)
- mainly it has two main components:
  - `kubeadm init`: initializes the control plane
  - `kubeadm join`: joins worker nodes to the cluster
linux machine ----> kubeadm init ----> a kubernetes control plane

#### workflow of kubeadm init 
1, preflight checks
2, Generate certificates (PKI) or Public key infrastructure: When you run kubeadm init, it automatically creates a self-signed CA (ca.crt and ca.key) in /etc/kubernetes/pki by default.
3, Generate kubeconfig files: kubeadm starts to create kubeconfig file in /etc/kubernetes
4, Generate static Pod manifests: in /etc/kubernetes/manifests, kubelet starts to create the static Pods based on these manifests.
5, Apply labels and taints to the control plane node: kubeadm adds labels and taints to the control plane node to mark it as the master node.
6, Generate a join token
7, Configure node joining
8, Install coreDNS not kube-dns(which is a deprecated and not recommended)



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
kubectl get pods -o wide
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
### Kubernetes configuration file syntax

The kuberenete configuration file uses YAML syntax for defining resources.
YAML is a key-value pair format that is easy to read and write.

Here is an example of a YAML configuration file for a deployment:

```yaml
key: value

# when we have objects with multiple fields
key:
  subkey: value
# when we have objects with multiple fields and subfields
key:
  subkey:
    subsubkey: value
# when we have a list
key:
  - item1
  - item2
  - item3

# when we have a list of objects with multiple fields
key:
  - subkey: value
    subsubkey: value
  - subkey: value
    subsubkey: value
# when we have a list of objects with multiple fields and subfields
key:
  - subkey:
      subsubkey: value
    subsubkey: value
  - subkey:
      subsubkey: value
    subsubkey: value
```

You can use this url to learn more about YAML syntax: https://onlineyamltools.com/convert-yaml-to-json 
this will show you the syntax implementation by converting YAML to JSON which most programmers are addopted with.

### the configuration file groups

The configuration file have five section:

1, The apiVersion: the apiVersion section specifies the version of the Kubernetes API you are using. e.g. `apiVersion: v1`, `apiVersion: apps/v1`
2, The kind: the kind section specifies the type of object you are creating, such as a Pod, Service, or Deployment. e.g. `kind: Pod`, `kind: Deployment`
3, The metadata: the metadata section contains information about the object, such as its name, namespace, and labels
4, The spec: this is where you define the desired state of the object, and it has a structure that depends on the kind of object you are creating
5, The status: this will be auto generated by kubernetes
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


## Kubernetes Contexts

In Kubernetes, you can have multiple **contexts**. A context is a configuration that points to a specific **cluster**, **user**, and optionally a **default namespace**. Contexts make it easy to switch between environments such as **development**, **staging**, and **production**.

### List all contexts

Use the following command to list all available contexts:

```bash
kubectl config get-contexts
```

Example output:

```bash
CURRENT   NAME             CLUSTER          AUTHINFO         NAMESPACE
          docker-desktop   docker-desktop   docker-desktop
*         minikube         minikube         minikube         default
```

The asterisk (`*`) indicates the **currently active context**.

### Check the current context

To display the active context, run:

```bash
kubectl config current-context
```

### Switch to a different context

To switch to another context, use:

```bash
kubectl config use-context <context-name>
```

For example:

```bash
kubectl config use-context docker-desktop
```

After switching, verify the active context by running:

```bash
kubectl config get-contexts
```

You should see output similar to:

```bash
CURRENT   NAME             CLUSTER          AUTHINFO         NAMESPACE
*         docker-desktop   docker-desktop   docker-desktop
          minikube         minikube         minikube         default
```

The `*` has now moved to `docker-desktop`, indicating that it is the active context.
### removing context

1. Delete context
```bash
kubectl config delete-context <context-name>
```
2. Delete cluster
```bash
kubectl config delete-cluster <cluster-name>
```
3. Delete user
```bash
kubectl config unset users.<user-name>
```

## Accessing the Kubernetes Cluster from Your Local Machine

If you initialized the control plane with:

```bash
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --apiserver-cert-extra-sans="$(curl -s ifconfig.me)"
```

the generated API server certificate will include the server's public IP, allowing secure access from your laptop.

### 1. Copy the kubeconfig from the control plane

On the control plane:

```bash
sudo cp /etc/kubernetes/admin.conf ~/aws-cluster.conf
sudo chown $(id -u):$(id -g) ~/aws-cluster.conf
```

Copy it to your local machine:

```bash
scp -i <private-key> ubuntu@<CONTROL_PLANE_PUBLIC_IP>:~/aws-cluster.conf .


scp -i "dev-key-pair.pem" `
    ubuntu@ec2-3-70-228-19.eu-central-1.compute.amazonaws.com:/home/ubuntu/aws-cluster.conf `
    $HOME\.kube\aws-cluster.conf
```

### 2. Update the API server address

Open `aws-cluster.conf` and make sure the `server` field points to the control plane's public IP:

```yaml
clusters:
- cluster:
    server: https://<CONTROL_PLANE_PUBLIC_IP>:6443
```

### 3. Save the kubeconfig

#### Linux / macOS

Move the file to:

```text
~/.kube/aws-cluster.conf
```

#### Windows

Move the file to:

```text
%USERPROFILE%\.kube\aws-cluster.conf
```

### 4. Back up your existing kubeconfig

#### Linux / macOS

```bash
cp ~/.kube/config ~/.kube/config.backup
```

#### Windows PowerShell

```powershell
Copy-Item "$HOME\.kube\config" "$HOME\.kube\config.backup"
```

### 5. Merge the kubeconfig files

#### Linux / macOS

```bash
export KUBECONFIG="$HOME/.kube/config:$HOME/.kube/aws-cluster.conf"

kubectl config view --flatten > "$HOME/.kube/config.merged"

mv "$HOME/.kube/config.merged" "$HOME/.kube/config"

unset KUBECONFIG
```

#### Windows PowerShell

```powershell
$env:KUBECONFIG="$HOME\.kube\config;$HOME\.kube\aws-cluster.conf"

kubectl config view --flatten > "$HOME\.kube\config.merged"

Move-Item -Force "$HOME\.kube\config.merged" "$HOME\.kube\config"

Remove-Item Env:\KUBECONFIG
```

### 6. Rename the imported context

```bash
kubectl config rename-context kubernetes-admin@kubernetes aws
```

### 7. Switch to the AWS cluster

```bash
kubectl config use-context aws
```

### 8. Verify the connection

```bash
kubectl get nodes
```

If everything is configured correctly, you should see the nodes in your remote Kubernetes cluster and be able to manage it directly from your local machine.

## AWS CCM installation
resource: https://rancher.github.io/product-docs-playbook/rancher-manager/v2.10/en/cluster-deployment/set-up-cloud-providers/amazon.html

prerequisites: 
first,
The OS hostname of each EC2 instance must match its internal AWS Private DNS name
example: ip-172-31-42-124.eu-central-1.compute.internal you can check this with `hostname -f`

second,
subnet, security groups, and  nodes must be tagged with the appropriate values
like kubernetes.io/cluster/<cluster-name / cluster-id> = shared / owned

third,
ec2 intance profiles should be set up with the appropriate IAM role and policies

fourth, Install the AWS Cloud Controller Manager
resource: https://kubernetes.github.io/cloud-provider-aws/

## Persistent Storage in Kubernetes

By default, a container stores data in its writable layer. If the container is recreated, that data is lost. To persist data across restarts, Kubernetes provides different volume mechanisms.

### emptyDir

An `emptyDir` volume is created when a Pod starts and exists for the lifetime of that Pod. It is suitable for temporary files, caching, or sharing data between containers in the same Pod.

```yaml
volumes:
  - name: mongodb-data
    emptyDir: {}
```

The volume is mounted into the container using:

```yaml
volumeMounts:
  - name: mongodb-data
    mountPath: /data/db
```

Any data written to `/data/db` is stored in the `emptyDir` volume instead of the container's writable layer. However, the data is deleted when the Pod is removed.

### PersistentVolume (PV)

A `PersistentVolume` (PV) represents actual storage available to the cluster. It defines where and how data is physically stored, such as a local disk, network storage, or cloud volume.

### PersistentVolumeClaim (PVC)

A `PersistentVolumeClaim` (PVC) is a request for storage made by an application. Instead of referencing the storage directly, workloads use the PVC, which is then bound to a suitable PV.

### StorageClass

A `StorageClass` defines how Kubernetes should dynamically provision persistent storage. When a cluster has a StorageClass configured, creating a PVC is often enough because Kubernetes automatically creates and binds a matching PV.

If no StorageClass exists, a matching PV must be created manually before the PVC can be bound.

### Relationship Between PV, PVC, and StorageClass

- `PersistentVolume (PV)` → The actual storage resource.
- `PersistentVolumeClaim (PVC)` → A request for storage made by an application.
- `StorageClass` → A template that tells Kubernetes how to automatically create PVs.

In clusters without a `StorageClass`, developers or administrators typically create both the PV and the PVC manually.


## Helm 


``` bash
# Check Helm version
helm version
# Add Bitnami Helm repository
helm repo add <repo-name> <repo-url>
# Update Helm repositories
helm repo update
# Search for MongoDB Helm chart
helm search repo <chart-name>
# Create a Helm chart 
helm create <chart-name>
# Install the Helm chart
helm Install <release-name> <chart-name>
# Remote chart
helm install <release-name> <repo-name>/<chart-name>
# Update dependencies
helm dependency update
# List all Helm releases
helm list
# List all Helm repositories
helm repo list
# Get status of a Helm release
helm status <release-name>
# Get values of a Helm release
helm get values <release-name>
# Upgrade a Helm release
helm upgrade <release-name> <chart-name>
# Rollback a Helm release to a previous revision
helm rollback <release-name> <revision>
# Uninstall a Helm release
helm uninstall <release-name>
```

# Structure of a Helm chart
my-chart/
├── Chart.yaml
├── values.yaml
├── charts/
│   └── mongodb-16.5.0.tgz
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    └── configmap.yaml

### Mongodb helm chart 

reading resource: https://github.com/mongodb/helm-charts/tree/main/charts/community-operator

``` bash
helm repo add mongodb https://mongodb.github.io/helm-charts
helm repo update

helm install community-operator mongodb/community-operator --namespace mongodb [--create-namespace]

kubectl apply -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/master/config/samples/mongodb.com_v1_mongodbcommunity_cr.yaml [--namespace mongodb]
```
### Prometheus helm chart for container resource monitoring

``` bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
# Install monitoring
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
### Upgrade monitoring
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
--namespace monitoring
### Uninstall monitoring
helm uninstall monitoring -n monitoring
```
### Grafana helm chart for cluster level logging

``` bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki \
  --namespace monitoring \
  --create-namespace

helm install fluent-bit grafana/fluent-bit \
  --namespace monitoring
```

### logging in kubernetes

``` bash
# Show logs from a Pod with one container
kubectl logs my-pod

# Show logs from a specific container in a multi-container Pod
kubectl logs my-pod -c sidecar-container

# Follow logs in real time
kubectl logs -f my-pod

kubectl logs my-pod -c my-container
kubectl logs --previous my-pod
```
