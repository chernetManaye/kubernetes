# Setting up Auto-Scaling

## 1, Setting up metrics-server

#### 1, Installing metrics-server

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

helm install metrics-server metrics-server/metrics-server \
  -n kube-system \
  --set args="{--kubelet-insecure-tls}"
```

#### 2, Check metrics-server is running

```bash
kubectl get pods -n kube-system | grep metrics-server

# or if the next commands return a json response the metric server is running
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes"
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods"

# or check if the metrics API service is available
kubectl get apiservices | grep metrics
```

#### 3, See metrics

```bash
kubectl top nodes
kubectl top pods -A
```

```
Containers
      │
      ▼
Container Runtime (or cAdvisor)
      │
      ▼
Kubelet
      │
      ▼
/metrics/resource (10250)
      │
      ▼
Metrics Server
      │
      ▼
metrics.k8s.io API
      │
      ├── HPA
      └── kubectl top
```

## 2, Setting up Horizontal Pod Autoscaler

First, create a workload like deployment or statefulset for the application you want to scale:
```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment

metadata:
  name: nginx
  labels:
    app: nginx

spec:
  replicas: 2 # Initial replicas (remove after HPA manages it)

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
          image: nginx:1.27

          ports:
            - containerPort: 80

          # Required for HPA CPU/Memory utilization
          resources:
            requests:
              cpu: "100m"  # 0.1 CPU cores or 10% of a CPU core
              memory: "128Mi"  # 128 mebibytes of memory 

            limits:
              cpu: "500m"  # 0.5 CPU cores or 50% of a CPU core
              memory: "256Mi"  # 256 mebibytes of memory
          # Setup Probes to prevent startup spikes tricking HPA into scaling up
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5

          startupProbe:
            httpGet:
              path: /
              port: 80
            failureThreshold: 30
            periodSeconds: 2

```
Best practices we should do in workload resources:

1, Add readiness and startup probes so startup CPU spikes don't affect scaling.
2, Always define CPU and memory requests
3, Remove spec.replicas from Deployment manifests managed by HPA to avoid conflicts after applying HPA.


Add the HPA manifest to your cluster:
```yaml
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler

metadata:
  name: nginx-hpa

spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx

  minReplicas: 2
  maxReplicas: 10

  metrics:

    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60

    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 70

  behavior:

    scaleUp:

      stabilizationWindowSeconds: 0

      policies:
        - type: Percent
          value: 100
          periodSeconds: 15

        - type: Pods
          value: 4
          periodSeconds: 15

      selectPolicy: Max

    scaleDown:

      stabilizationWindowSeconds: 300

      policies:
        - type: Percent
          value: 10
          periodSeconds: 60

      selectPolicy: Max

```
Best practices we should do in HPA:
1, Stabilization windows and scaling policies help prevent rapid oscillations (flapping).

2, For new deployments, use autoscaling/v2 because it supports memory, custom metrics, external metrics, multiple metrics, and configurable scaling behavior.

```
Client Traffic
      │
      ▼
Nginx Pods
      │
      ▼
CPU / Memory Usage
      │
      ▼
Kubelet
      │
      ▼
Metrics Server
(metrics.k8s.io)
      │
      ▼
HPA Controller (every 15s)
      │
      ▼
CPU Target = 60%
Memory Target = 70%
      │
      ▼
Formula:
desiredReplicas =
currentReplicas × currentMetric / targetMetric
      │
      ▼
Deployment.scale
      │
      ▼
ReplicaSet
      │
      ▼
Pods Created or Removed
```

## 3, Setting up Karpenter

```

               User creates Pods
                       │
                       ▼
          Kubernetes Scheduler
                       │
          Some Pods stay Pending
                       │
                       ▼
          Karpenter Controller
                       │
        Reads matching NodePool
                       │
                       ▼
         Reads EC2NodeClass
                       │
                       ▼
          Creates NodeClaim
                       │
                       ▼
           Calls AWS EC2 Fleet
                       │
                       ▼
        AWS selects best instance
                       │
                       ▼
           EC2 instance launches
                       │
                       ▼
        User data/bootstrap runs
                       │
                       ▼
         kubelet joins cluster
                       │
                       ▼
      Node becomes Ready in Kubernetes
                       │
                       ▼
     Scheduler binds Pending Pods
```


```bash
CLUSTER_ENDPOINT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.13.0 \
  --namespace karpenter \
  --create-namespace \
  --set replicas=1 \
  --set controller.env[0].name=AWS_REGION \
  --set controller.env[0].value=us-east-1 \
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
```

check tents and labels
```bash
kubectl get nodes --show-labels
kubectl get nodes --show-labels
```
```bash
# Generate the join command
JOIN_COMMAND="$(kubeadm token create --print-join-command)"
JOIN_COMMAND="sudo ${JOIN_COMMAND} --node-name=\$(hostname -f)"

echo "$JOIN_COMMAND"

# From the log file
# JOIN_COMMAND="$(sed -n '/kubeadm join/,/sha256/p' /var/log/master-bootstrap.log | tr -d '\\' | xargs)"
# JOIN_COMMAND="sudo ${JOIN_COMMAND} --node-name=\$(hostname -f)"

# echo "$JOIN_COMMAND"
```






contex:


questions:


command: 


My understanding:



I want to make sure you agree with my understanding and if there is anything you want to refine you can but make it short and clear


questions:








```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    k8s-app: metrics-server
    rbac.authorization.k8s.io/aggregate-to-admin: "true"
    rbac.authorization.k8s.io/aggregate-to-edit: "true"
    rbac.authorization.k8s.io/aggregate-to-view: "true"
  name: system:aggregated-metrics-reader
rules:
- apiGroups:
  - metrics.k8s.io
  resources:
  - pods
  - nodes
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    k8s-app: metrics-server
  name: system:metrics-server
rules:
- apiGroups:
  - ""
  resources:
  - nodes/metrics
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - pods
  - nodes
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server-auth-reader
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server:system:auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    k8s-app: metrics-server
  name: system:metrics-server
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:metrics-server
subjects:
- kind: ServiceAccount
  name: metrics-server
  namespace: kube-system
---
apiVersion: v1
kind: Service
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server
  namespace: kube-system
spec:
  ports:
  - appProtocol: https
    name: https
    port: 443
    protocol: TCP
    targetPort: https
  selector:
    k8s-app: metrics-server
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    k8s-app: metrics-server
  name: metrics-server
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: metrics-server
  strategy:
    rollingUpdate:
      maxUnavailable: 0
  template:
    metadata:
      labels:
        k8s-app: metrics-server
    spec:
      containers:
      - args:
        - --cert-dir=/tmp
        - --secure-port=10250
        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
        - --kubelet-use-node-status-port
        - --metric-resolution=15s
        image: registry.k8s.io/metrics-server/metrics-server:v0.8.1
        imagePullPolicy: IfNotPresent
        livenessProbe:
          failureThreshold: 3
          httpGet:
            path: /livez
            port: https
            scheme: HTTPS
          periodSeconds: 10
        name: metrics-server
        ports:
        - containerPort: 10250
          name: https
          protocol: TCP
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /readyz
            port: https
            scheme: HTTPS
          initialDelaySeconds: 20
          periodSeconds: 10
        resources:
          requests:
            cpu: 100m
            memory: 200Mi
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
          seccompProfile:
            type: RuntimeDefault
        volumeMounts:
        - mountPath: /tmp
          name: tmp-dir
      nodeSelector:
        kubernetes.io/os: linux
      priorityClassName: system-cluster-critical
      serviceAccountName: metrics-server
      volumes:
      - emptyDir: {}
        name: tmp-dir
---
apiVersion: apiregistration.k8s.io/v1
kind: APIService
metadata:
  labels:
    k8s-app: metrics-server
  name: v1beta1.metrics.k8s.io
spec:
  group: metrics.k8s.io
  groupPriorityMinimum: 100
  insecureSkipTLSVerify: true
  service:
    name: metrics-server
    namespace: kube-system
  version: v1beta1
  versionPriority: 100

```


questions:
1, what is on-demand and what is spot in node pools?
2, what is the connetcion between labels and taints in nodes and how do I use them? 
3, what is the difference between kubectl rollout status and kubectl wait command lets learn both of them?
4, How does kubernets RBAC works 
5, What are service accounts in kubernets
6, what are porbes and types of them
7, how does IRSA works
8, why are crds have extension .sh at the end I thougt crds are like regular kubernets resources like yaml

9, what is the usage of helm value and helm template commands?
