### Pod
reading resource: https://kubernetes.io/docs/concepts/workloads/pods/

A Pod is a group of one or more containers, with shared storage and network resources, and a specification for how to run the containers.

There are 
1, init containers
2, ephemeral containers
3, application containers
4, sidecar containers

In docker the isolation boundary is the container itself but in k8s the isolation boundary is the pod.
In docker each container will have its own ip address but in k8s the pod will have a single ip address shared by all containers within it. The containers listen in the same ip with different ports.

Pods usage in k8s:
1, Pods that run a single container
2, Pods that run multiple containers that need to work together: the containers are collocated and shares the same namespace 

There are many kinds of namespaces in linux. docker containers implement most of them to create the isolation between containers. in contrast k8s does not utilize all of the namespaces available in linux at the container level. instead it uses the network and volume namespace separation at the pod level and applies the remaining namespaces like PID, IPC, filesystem namespaces at the container level. so containers in k8s are partially isolated from each other but share the same namespace.

A pod is not a process instead it is an environment, like a sandbox for a group of containers.
in k8s a container can restart based on restart policy defined in the pod spec. and we can not say pods will restart instead k8s will create a new pod and replace the old one.

containers provide an execution environment for applications and pods provide an execution environment for containers.

Containers are isolated environments in which processes run. Pods are shared environments that group one or more containers and provide them with shared networking, storage, and lifecycle.

Pod
├── Shared network namespace
├── Shared volumes
│
├── Container A
│     └── Processes
│          ├── nginx
│          └── worker
│
└── Container B
      └── Processes
           └── fluentd

### Properties
pods are immutable. once a pod is created, it cannot be modified.
### Pods and controllers 
we use controllers to manage pods. controllers are responsible for creating, updating, and deleting pods based on the desired state defined in the controller's configuration. but to do so we need to define a controller configuration. controller configurations can be defined using workload resources such as Deployments, StatefulSets, and DaemonSets. workload resources define the desired state of a group of pods and are used by controllers to manage them.
           
```bash
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  # This does not insure the pod is scheduled on a Linux node.
  os:
    name: linux
  # This is a label selector that ensures the pod is scheduled on a Linux node.
  nodeSelector:
    kubernetes.io/os: linux
  restartPolicy: Always
  volumes:
  - name: shared-data
    emptyDir: {}
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80
    resource:
        requests:
        memory: 128Mi
        cpu: 100m
        limits:
        memory: 256Mi
        cpu: 200m
    env:
    - name: ENV_VAR_NAME
      value: "value"
    volumeMounts:
    - name: shared-data
      mountPath: /usr/share/nginx/html
```

We use pod templates to define the desired state of a pod. Pod templates are used by controllers to create pods based on the desired state defined in the template.

### Jobs 

```bash
apiVersion: batch/v1
kind: Job
metadata:
  name: hello
spec:
  template:
    # This is the pod template
    spec:
      containers:
      - name: hello
        image: busybox:1.28
        command: ['sh', '-c', 'echo "Hello, Kubernetes!" && sleep 3600']
      restartPolicy: OnFailure
    # The pod template ends here
```

### restart policy
1, Always: The pod will always be restarted with exit code 0 or non-zero code.
2, OnFailure: The pod will only be restarted if it exits with a non-zero code.
3, Never: The pod will never be restarted.
