# Cluster level logging setup

#### We are going to use two tools: Loki and fluent-bit.

## Loki
### Loki's architecture

```

                    Write Path
+------------+
| Fluent Bit |
+------------+
      |
      v
+----------------+
|  Distributor   |
+----------------+
      |
      | hashes labels
      |
      +-------------------+
      |                   |
      v                   v
+-----------+      +-----------+
| Ingester1 |      | Ingester2 |
+-----------+      +-----------+
      |                   |
      | chunks            |
      +---------+---------+
                |
                v
         Object Storage
         (S3, GCS, Azure)

               ^
               |
        Index Metadata
      (TSDB / BoltDB shipper)

=====================================

                 Read Path

        +-------------------+
        | Query Frontend    |
        +-------------------+
                  |
                  v
            +-----------+
            | Querier   |
            +-----------+
            |           |
      reads ingesters   |
      reads S3          |
            |           |
            +-----------+
                  |
                Result

=====================================

Background

Compactor
    |
    +--> merges indexes
    +--> deletes expired logs

```

#### 1, Distributer
It is stateless, stores nothing, only routes logs.
- validates data 
- compute stream identity
- consistent hashing
- replication
- wait for quorum

#### 2, Ingester
Each ingester has memory, chunks, ISDB, WAL.

log arrives -> check the label -> if stream exists, forward to it -> if not, create stream and forward

Each stream has an active chunk.
we write to chunks instead of writing to s3 directly

after chunk compress then upload to s3
there is a chunk size limit

factors for chunk closing are 
1,size
2, time
3, idle time

Every log write will not only stay in memory chunk but also in disk with WAL

chunks are immutable never modified again.

#### 3, Compactor
- Merge indexes
Merging of the index metadata into one file per stream
- Retention
- Cleanup


#### 4, Query Frontend

It just accepts request from grafana, it does not search logs by it self

- Queue queries
- split large queries
- cache

#### 5, Querier
The engine that actually read logs 

read query -> find matching index -> where are chunks(are they in the ingester or in s3) -> asks from both -> download chunks -> decompress -> scan logs -> apply logQL filters -> merge results from ingester and s3 -> sort by timestamp -> return results


```
Grafana

↓

Query Frontend

↓

Split into 24 hourly queries

↓

Querier workers

↓

Index lookup

↓

Read active chunks from ingesters

+

Read historical chunks from S3

↓

Decompress

↓

Execute LogQL

↓

Merge results

↓

Frontend cache

↓

Grafana

```

```

                  WRITE PATH
──────────────────────────────────────────────

Fluent Bit
     │
     ▼
 Distributor
     │
     ├── Validate request
     ├── Hash labels into a stream
     ├── Replicate to N ingesters
     └── Wait for quorum
             │
             ▼
        Ingesters
             │
             ├── Keep active chunks in memory
             ├── Append new log entries
             ├── Persist writes to the WAL
             ├── Build index metadata
             └── Flush compressed chunks
                     │
                     ▼
               Object Storage (S3)

          ▲
          │
     Compactor
          ├── Merge index files
          ├── Enforce retention
          └── Delete obsolete chunks

──────────────────────────────────────────────

                   READ PATH

Grafana
    │
    ▼
Query Frontend
    ├── Queue requests
    ├── Split long time ranges
    ├── Cache results
    ▼
Queriers
    ├── Read active chunks from ingesters
    ├── Read historical chunks from S3
    ├── Use indexes to locate chunks
    ├── Decompress chunks
    ├── Execute LogQL
    └── Merge and return results


```    
A distributed database is a database whose data is stored across multiple servers (nodes) that work together as if they were a single database.

Loki is a distributed log aggregation system that collects and stores logs from various sources.

| Component               | Primary responsibility                                                                  |
| ----------------------- | --------------------------------------------------------------------------------------- |
| **Distributor**         | Validate, hash streams, replicate, and route writes                                     |
| **Ingester**            | Buffer logs in memory, write to WAL, create chunks, flush to object storage             |
| **Object Storage (S3)** | Durable, long-term storage for immutable compressed chunks                              |
| **Compactor**           | Optimize index files and enforce retention policies                                     |
| **Query Frontend**      | Queue, split, cache, and distribute query work                                          |
| **Querier**             | Read indexes and chunks, execute LogQL, merge results from ingesters and object storage |

#### 6, Ruler
The Ruler is an automatic scheduler that repeatedly runs LogQL queries and can trigger alerts based on the results.

### Components
#### 1, The gateway component 
It is an nginx reverse proxy that routes incoming requests to the appropriate backend.
Fluent Bit sends logs here:

http://loki-gateway/loki/api/v1/push

Grafana queries here:

http://loki-gateway

#### 2, Loki canary
continuously test the gateway and ingester components to ensure they are working as expected.

#### 3, Loki-result-cache
caches the results of LogQL queries to avoid redundant computation.

#### 4, loki-chunks-cache
caches the chunks of log data to avoid redundant storage and retrieval.


```bash
kubectl get pvc -n monitoring
kubectl describe pvc loki-chunks-cache-0 -n monitoring

# or

kubectl describe pod loki-chunks-cache-0 -n monitoring
```

To desable the loki canary 

```yaml
lokiCanary:
  enabled: false
```
or
```bash
--set lokiCanary.enabled=false
```

```
               Fluent Bit
                    │
                    ▼
            +----------------+
            |  loki-gateway  |
            +----------------+
                    │
                    ▼
            +----------------+
            |    loki-0      |
            |----------------|
            | Distributor    |
            | Ingester       |
            | Querier        |
            | Frontend       |
            | Compactor      |
            +----------------+
              │          │
              │          │
              ▼          ▼
          EBS (WAL)      S3
                          │
              +-------------------+
              | chunks + indexes  |
              +-------------------+

      +------------------+
      | chunks-cache     |
      +------------------+

      +------------------+
      | results-cache    |
      +------------------+

      +------------------+
      | loki-canary      |
      +------------------+
```
grafana/lgtm-distributed    
for loki, grafana, tempo and mimir
grafana/loki           
the standard loki deployment
grafana/loki-canary         
grafana/loki-distributed   
grafana/loki-simple-scalable
+-------------+
| Write Pods  |
|-------------|
|Distributor  |
|Ingester     |
+-------------+

+-------------+
| Read Pods   |
|-------------|
|Frontend     |
|Querier      |
+-------------+

+-------------+
| Backend     |
|-------------|
|Compactor    |
|Gateway      |
|Ruler        |
+-------------+
grafana/loki-stack          
``` bash
# Add the Grafana Helm repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install loki
helm install loki grafana/loki \
  -n monitoring \
  --create-namespace \
  --set deploymentMode=SingleBinary \
  --set singleBinary.replicas=2 \
  --set write.replicas=0 \
  --set read.replicas=0 \
  --set backend.replicas=0 \
  --set loki.auth_enabled=false \
  --set gateway.enabled=true \
  --set singleBinary.persistence.enabled=true \
  --set singleBinary.persistence.storageClass=ebs-gp3-sc \
  --set singleBinary.persistence.size=10Gi \
  --set loki.storage.type=s3 \
  --set loki.storage.bucketNames.chunks=loki-kubernetes-cluster-logs \
  --set loki.storage.bucketNames.ruler=loki-kubernetes-cluster-logs \
  --set loki.storage.bucketNames.admin=loki-kubernetes-cluster-logs \
  --set loki.storage.s3.region=eu-central-1 \
  --set loki.useTestSchema=true \
  --set chunksCache.enabled=false \
  --set resultsCache.enabled=false \
  --set test.enabled=false \
  --set lokiCanary.enabled=false

# --set loki.schemaConfig.configs[0].from=2026-07-19 \
# --set loki.schemaConfig.configs[0].store=tsdb \
# --set loki.schemaConfig.configs[0].object_store=s3 \
# --set loki.schemaConfig.configs[0].schema=v13 \
# --set loki.schemaConfig.configs[0].index.prefix=loki_index_ \
# --set loki.schemaConfig.configs[0].index.period=24h


# --set chunksCache.allocatedMemory=256 \
# --set chunksCache.allocatedCPU=100m

# --set chunksCache.resources.requests.memory=256Mi \
# --set chunksCache.resources.requests.cpu=100m \
# --set chunksCache.resources.limits.memory=512Mi \
# --set chunksCache.resources.limits.cpu=500m

# --set lokiCanary.enabled=false


# Upgrade loki
helm upgrade loki grafana/loki \
  -n monitoring \
  --reuse-values \
  --set deploymentMode=SingleBinary \
  --set singleBinary.replicas=2 \
  --set write.replicas=0 \
  --set read.replicas=0 \
  --set backend.replicas=0 \
  --set loki.auth_enabled=false \
  --set gateway.enabled=true \
  --set singleBinary.persistence.enabled=true \
  --set singleBinary.persistence.storageClass=ebs-gp3-sc \
  --set singleBinary.persistence.size=10Gi \
  --set loki.storage.type=s3 \
  --set loki.storage.bucketNames.chunks=loki-storage \
  --set loki.storage.bucketNames.ruler=loki-storage \
  --set loki.storage.bucketNames.admin=loki-storage \
  --set loki.storage.s3.region=eu-central-1 \
  --set loki.useTestSchema=true \
  --set chunksCache.enabled=false \
  --set resultsCache.enabled=false \
  --set test.enabled=false \
  --set lokiCanary.enabled=false
  


# first desbale helm test 
# --set test.enabled=false \
# helm test loki -n monitoring

```


Questions:
1, what are schema configurations
2, how does indexing works in loki is not that hard to index things in s3


for fluent-bit

```conf
Host  loki-gateway.monitoring.svc.cluster.local
Port  80
URI   /loki/api/v1/push
```
1. Manually (good for learning)

Open Grafana

Connections
    ↓
Data Sources
    ↓
Add Loki

URL

http://loki-gateway.monitoring.svc.cluster.local

Save & Test.

2. Provision it automatically (recommended)

Since you're already using kube-prometheus-stack, Grafana supports provisioning data sources from a Helm value.

In the kube-prometheus-stack values file:

grafana:
  additionalDataSources:
    - name: Loki
      type: loki
      access: proxy
      url: http://loki-gateway.monitoring.svc.cluster.local
      isDefault: false

Then

helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f values.yaml

Grafana automatically creates the data source.

3. Via Grafana API

Grafana also has an HTTP API to create data sources, but Helm provisioning is almost always preferred in Kubernetes.

```bash
# Add Fluent Helm repo and install Fluent Bit
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

# Search for Fluent Helm charts
helm search repo fluent/

# 1, fluent/fluent-bit  
# 2, fluent/fluent-operator  
# 3, fluent/fluent-operator-fluent-bit-crds	
# 4, fluent/fluent-bit-aggregator 
# 5, fluent/fluent-bit-collector 

mkdir -p /home/ubuntu/fluent-bit

cat <<EOF > /home/ubuntu/fluent-bit/fluent-bit-config.yaml
config:
  service: |
    [SERVICE]
        Daemon Off
        Flush 1
        Log_Level warn
        Parsers_File /fluent-bit/etc/parsers.conf
        Parsers_File /fluent-bit/etc/conf/custom_parsers.conf
        HTTP_Server On
        HTTP_Listen 0.0.0.0
        HTTP_Port 2020
        Health_Check On

  inputs: |
    [INPUT]
        Name tail
        Path /var/log/containers/*nginx-logs*.log
        multiline.parser docker, cri
        Tag kube.*
        Mem_Buf_Limit 5MB
        Skip_Long_Lines On

    [INPUT]
        Name systemd
        Tag host.*
        Systemd_Filter _SYSTEMD_UNIT=kubelet.service
        Read_From_Tail On

  filters: |
    [FILTER]
        Name kubernetes
        Match kube.*
        Merge_Log On
        Keep_Log Off
        K8S-Logging.Parser On
        K8S-Logging.Exclude On

  outputs: |
    [OUTPUT]
        Name        loki
        Match       *
        Host        loki-gateway.monitoring.svc.cluster.local
        Port        80
        Labels job=fluent-bit,namespace=$kubernetes['namespace_name'],pod=$kubernetes['pod_name'],container=$kubernetes['container_name']
        Line_Format json

  customParsers: |
    [PARSER]
        Name docker_no_time
        Format json
        Time_Keep Off
        Time_Key time
        Time_Format %Y-%m-%dT%H:%M:%S.%L
EOF


helm install fluent-bit fluent/fluent-bit \
  -n monitoring \
  --create-namespace \
  -f /home/ubuntu/fluent-bit/fluent-bit-config.yaml \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=128Mi \
  --set resources.limits.cpu=500m \
  --set resources.limits.memory=512Mi \
  --set tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set tolerations[0].operator=Exists \
  --set tolerations[0].effect=NoSchedule

  
helm upgrade fluent-bit fluent/fluent-bit \
  -n monitoring \
  -f /home/ubuntu/fluent-bit/fluent-bit-config.yaml \
  --reuse-values \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=128Mi \
  --set resources.limits.cpu=500m \
  --set resources.limits.memory=512Mi \
  --set tolerations[0].key=node-role.kubernetes.io/control-plane \
  --set tolerations[0].operator=Exists \
  --set tolerations[0].effect=NoSchedule


# we will also set This
# --set serviceMonitor.enabled=true


cat <<EOF > /home/ubuntu/fluent-bit/nginx-logs.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-logs
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-logs
  template:
    metadata:
      labels:
        app: nginx-logs
    spec:
      containers:
        - name: nginx
          image: nginx:latest
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: "100m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "128Mi"
EOF

kubectl apply -f /home/ubuntu/fluent-bit/nginx-logs.yaml


kubectl port-forward deploy/nginx-logs 8080:80

# In another terminal:
for i in {1..20}; do
  curl http://localhost:8080
done

# Or continuously:
while true; do
  curl -s http://localhost:8080 > /dev/null
  sleep 1
done

# Then watch Fluent Bit's output:
kubectl logs -n monitoring -l app.kubernetes.io/name=fluent-bit -f
```


#### SERVICE
This configures the fluent-bit process.
There is exactly one service block in the configuration file.

values like: 

Daemon Off
Flush 1
Log_Level info
Parsers_File /fluent-bit/etc/parsers.conf
Parsers_File /fluent-bit/etc/conf/custom_parsers.conf
HTTP_Server On
HTTP_Listen 0.0.0.0
HTTP_Port 2020
Health_Check On

#### INPUT
This configures the input sources for fluent-bit
We can have multiple input sources, each with its own configuration

| Plugin    | Reads From                         |
| --------- | ---------------------------------- |
| `tail`    | Files                              |
| `systemd` | systemd journal                    |
| `cpu`     | CPU metrics                        |
| `mem`     | Memory metrics                     |
| `disk`    | Disk metrics                       |
| `tcp`     | TCP socket                         |
| `forward` | Other Fluent Bit/Fluentd instances |
| `http`    | HTTP requests                      |
| `mqtt`    | MQTT broker                        |
| `dummy`   | Fake generated logs                |


#### The input plugin roles

- Find files that match the configured path.
- Open those files.
- Remember how much has already been read.
- Read only newly appended data.
- Emit raw log records into Fluent Bit's pipeline.


#### FILTER
This configures the filter for fluent-bit
We can have multiple filter blocks in the configuration file.

types of filter plugins:

| Plugin          | Description                          |
| --------------- | ------------------------------------ |
| `grep`          | Filters log records based on patterns |
| `modify`        | Modifies log records                  |
| `lua`           | Executes Lua scripts for filtering and modification |
| `record_modifier`| Modifies log records based on Lua scripts |
| `rewrite_tag`   | Rewrites log tags based on Lua scripts |
| `nest`          | Nests log records                     |
| `parser`        | Parses log records                    |
| `kubernetes`    | Parses Kubernetes log records         |

#### OUTPUT
This configures the output for fluent-bit


INPUTS

↓

FILTERS

↓

RECORDS

↓

ROUTER

↓

OUTPUTS


| Plugin     | Sends To                   |
| ---------- | -------------------------- |
| stdout     | Console                    |
| loki       | Grafana Loki               |
| es         | Elasticsearch              |
| opensearch | OpenSearch                 |
| kafka      | Kafka                      |
| s3         | Amazon S3                  |
| http       | HTTP endpoint              |
| forward    | Another Fluent Bit/Fluentd |
| tcp        | TCP server                 |


```bash
kubectl logs fluent-bit-xxxxx
```

                 Fluent Bit Engine

              +----------------------+
              |      SERVICE         |
              |  Engine Settings     |
              +----------+-----------+
                         |
                         v
      +------------------------------------------+
      |                                          |
      |               INPUTS                     |
      |                                          |
      |  tail          systemd        tcp        |
      +------------------+-----------------------+
                         |
                         v
                Internal Records
                         |
                    Tag Attached
                         |
                         v
      +------------------------------------------+
      |              FILTERS                     |
      |                                          |
      | kubernetes  grep  modify  parser  lua    |
      +------------------+-----------------------+
                         |
                  Enriched Records
                         |
                         v
                    Router (Tags)
                         |
          +--------------+--------------+
          |                             |
          v                             v
    stdout (Match *)             Loki (Match kube.*)
          |
          v
   kubectl logs


```bash
# Follow logs in real time, starting with the last 100 lines
kubectl logs -f fluent-bit-7f8r7 -n monitoring --tail=100

# Show logs from the previous container (if the pod restarted)
kubectl logs -p fluent-bit-7f8r7 -n monitoring --tail=100

# Since Fluent Bit pods usually have only one container, this is optional,
# but if there are multiple containers:
kubectl logs fluent-bit-7f8r7 -n monitoring -c fluent-bit --tail=100

# If you want to search for errors in those logs:
kubectl logs fluent-bit-7f8r7 -n monitoring --tail=100 | grep -i error

# or warnings:
kubectl logs fluent-bit-7f8r7 -n monitoring --tail=100 | grep -Ei "warn|error|fail"
```

#### PARSER
This configures the parser for fluent-bit
Unlike input, filters and outputs parsers are not plugins, they are definitions.

[SERVICE]
    │
    ▼
Load Parser Definitions (Parsers_File)
    │
    ▼
Initialize INPUT plugins
    │
    ▼
INPUT reads raw bytes
    │
    ▼
(Optional) Parser parses the raw data
    │
    ▼
Record created
    │
    ▼
Attach Tag
    │
    ▼
FILTER(s)
    │
    ▼
Router (matches tags)
    │
    ▼
OUTPUT(s)
    │
    ▼
Destination(s)

or

SERVICE
   ↓
Load Parsers
   ↓
INPUT
   ↓
Parser (optional)
   ↓
Record
   ↓
FILTER
   ↓
Parser (optional)
   ↓
Router
   ↓
OUTPUT
   ↓
Destination

Note: A parser is not a separate pipeline stage like a filter or output. It's a utility that is invoked by an input or a filter whenever parsing is needed. That's why I marked it as optional in the pipeline.

```yaml
config:
  service: |
    [SERVICE]
        Daemon Off
        Flush 1
        Log_Level info
        Parsers_File /fluent-bit/etc/parsers.conf
        Parsers_File /fluent-bit/etc/conf/custom_parsers.conf
        HTTP_Server On
        HTTP_Listen 0.0.0.0
        HTTP_Port 2020
        Health_Check On

  inputs: |
    [INPUT]
        Name tail
        Path /var/log/containers/*.log
        multiline.parser docker, cri
        Tag kube.*
        Mem_Buf_Limit 5MB
        Skip_Long_Lines On

    [INPUT]
        Name systemd
        Tag host.*
        Systemd_Filter _SYSTEMD_UNIT=kubelet.service
        Read_From_Tail On

  filters: |
    [FILTER]
        Name kubernetes
        Match kube.*
        Merge_Log On
        Keep_Log Off
        K8S-Logging.Parser On
        K8S-Logging.Exclude On

  outputs: |
    [OUTPUT]
        Name stdout
        Match *

  customParsers: |
    [PARSER]
        Name docker_no_time
        Format json
        Time_Keep Off
        Time_Key time
        Time_Format %Y-%m-%dT%H:%M:%S.%L

```

```bash
# To get the default values
helm show values fluent/fluent-bit > values.yaml
# The values you added
helm get values fluent-bit -n monitoring
# the values you added and the default values
helm get values fluent-bit -n monitoring --all
# The rendered manifests
helm get manifest fluent-bit -n monitoring
# Generate values template without installing 
helm template fluent-bit fluent/fluent-bit > rendered.yaml
# Read the chart metadata
helm show chart fluent/fluent-bit
# Read the README
helm show readme fluent/fluent-bit
```

```yaml
# Default values for fluent-bit.

# kind -- DaemonSet or Deployment
kind: DaemonSet

# replicaCount -- Only applicable if kind=Deployment
replicaCount: 1

image:
  repository: cr.fluentbit.io/fluent/fluent-bit
  # Overrides the image tag whose default is {{ .Chart.AppVersion }}
  # Set to "-" to not use the default value
  tag:
  digest:
  pullPolicy: IfNotPresent

testFramework:
  enabled: true
  namespace:
  image:
    repository: busybox
    pullPolicy: Always
    tag: latest
    digest:

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name:
  automountServiceAccountToken:

rbac:
  create: true
  nodeAccess: false
  eventsAccess: false

# Configure podsecuritypolicy
# Ref: https://kubernetes.io/docs/concepts/policy/pod-security-policy/
# from Kubernetes 1.25, PSP is deprecated
# See: https://kubernetes.io/blog/2022/08/23/kubernetes-v1-25-release/#pod-security-changes
# We automatically disable PSP if Kubernetes version is 1.25 or higher
podSecurityPolicy:
  create: false
  annotations: {}
  runAsUser:
    rule: RunAsAny
  seLinux:
    # This policy assumes the nodes are using AppArmor rather than SELinux.
    rule: RunAsAny

# OpenShift-specific configuration
openShift:
  enabled: false
  securityContextConstraints:
    # Create SCC for Fluent-bit and allow use it
    create: true
    name: ""
    annotations: {}
    runAsUser:
      type: RunAsAny
    seLinuxContext:
      type: MustRunAs
    # Use existing SCC in cluster, rather then create new one
    existingName: ""

podSecurityContext: {}
#   fsGroup: 2000

hostNetwork: false
dnsPolicy: ClusterFirst

dnsConfig: {}
#   nameservers:
#     - 1.2.3.4
#   searches:
#     - ns1.svc.cluster-domain.example
#     - my.dns.search.suffix
#   options:
#     - name: ndots
#       value: "2"
#     - name: edns0

hostAliases: []
#   - ip: "1.2.3.4"
#     hostnames:
#     - "foo.local"
#     - "bar.local"

securityContext: {}
#   capabilities:
#     drop:
#     - ALL
#   readOnlyRootFilesystem: true
#   runAsNonRoot: true
#   runAsUser: 1000

service:
  type: ClusterIP
  port: 2020
  internalTrafficPolicy:
  loadBalancerClass:
  loadBalancerSourceRanges: []
  loadBalancerIP:
  labels: {}
  # nodePort: 30020
  # clusterIP: 172.16.10.1
  annotations: {}
  #   prometheus.io/path: "/api/v2/metrics/prometheus"
  #   prometheus.io/port: "2020"
  #   prometheus.io/scrape: "true"
  externalIPs: []
  # externalIPs:
  #  - 2.2.2.2

serviceMonitor:
  enabled: false
  #   namespace: monitoring
  #   interval: 10s
  #   scrapeTimeout: 10s
  #   selector:
  #    prometheus: my-prometheus
  #  ## metric relabel configs to apply to samples before ingestion.
  #  ##
  #  metricRelabelings:
  #    - sourceLabels: [__meta_kubernetes_service_label_cluster]
  #      targetLabel: cluster
  #      regex: (.*)
  #      replacement: ${1}
  #      action: replace
  #  ## relabel configs to apply to samples after ingestion.
  #  ##
  #  relabelings:
  #    - sourceLabels: [__meta_kubernetes_pod_node_name]
  #      separator: ;
  #      regex: ^(.*)$
  #      targetLabel: nodename
  #      replacement: $1
  #      action: replace
  #  scheme: ""
  #  tlsConfig: {}

  ## Bear in mind if you want to collect metrics from a different port
  ## you will need to configure the new ports on the extraPorts property.
  additionalEndpoints: []
  # - port: metrics
  #   path: /metrics
  #   interval: 10s
  #   scrapeTimeout: 10s
  #   scheme: ""
  #   tlsConfig: {}
  #   # metric relabel configs to apply to samples before ingestion.
  #   #
  #   metricRelabelings:
  #     - sourceLabels: [__meta_kubernetes_service_label_cluster]
  #       targetLabel: cluster
  #       regex: (.*)
  #       replacement: ${1}
  #       action: replace
  #   # relabel configs to apply to samples after ingestion.
  #   #
  #   relabelings:
  #     - sourceLabels: [__meta_kubernetes_pod_node_name]
  #       separator: ;
  #       regex: ^(.*)$
  #       targetLabel: nodename
  #       replacement: $1
  #       action: replace

prometheusRule:
  enabled: false
#   namespace: ""
#   additionalLabels: {}
#   rules:
#   - alert: NoOutputBytesProcessed
#     expr: rate(fluentbit_output_proc_bytes_total[5m]) == 0
#     annotations:
#       message: |
#         Fluent Bit instance {{ $labels.instance }}'s output plugin {{ $labels.name }} has not processed any
#         bytes for at least 15 minutes.
#       summary: No Output Bytes Processed
#     for: 15m
#     labels:
#       severity: critical

dashboards:
  enabled: false
  labelKey: grafana_dashboard
  labelValue: 1
  annotations: {}
  namespace: ""
  deterministicUid: false

lifecycle: {}
#   preStop:
#     exec:
#       command: ["/bin/sh", "-c", "sleep 20"]

livenessProbe:
  httpGet:
    path: /
    port: http

readinessProbe:
  httpGet:
    path: /api/v2/health
    port: http

resources: {}
#   limits:
#     cpu: 100m
#     memory: 128Mi
#   requests:
#     cpu: 100m
#     memory: 128Mi

## only available if kind is Deployment
ingress:
  enabled: false
  ingressClassName: ""
  annotations: {}
  #  kubernetes.io/ingress.class: nginx
  #  kubernetes.io/tls-acme: "true"
  hosts: []
  # - host: fluent-bit.example.tld
  extraHosts: []
  # - host: fluent-bit-extra.example.tld
  ## specify extraPort number
  #   port: 5170
  tls: []
  #  - secretName: fluent-bit-example-tld
  #    hosts:
  #      - fluent-bit.example.tld

## only available if kind is Deployment
autoscaling:
  vpa:
    enabled: false

    annotations: {}

    # List of resources that the vertical pod autoscaler can control. Defaults to cpu and memory
    controlledResources: []

    # Values that the vertical pod autoscaler can control. Allowed values are RequestsAndLimits and RequestsOnly. Default is RequestsAndLimits.
    controlledValues:

    # Define the max allowed resources for the pod
    maxAllowed: {}
    # cpu: 200m
    # memory: 100Mi
    # Define the min allowed resources for the pod
    minAllowed: {}
    # cpu: 200m
    # memory: 100Mi

    # Name of the VPA recommender that will provide recommendations for vertical scaling.
    recommender: default

    updatePolicy:
      # Specifies whether recommended updates are applied when a Pod is started and whether recommended updates
      # are applied during the life of a Pod. Possible values are "Off", "Initial", "Recreate", and "Auto".
      updateMode: Auto

  enabled: false
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 75
  #  targetMemoryUtilizationPercentage: 75
  ## see https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/#autoscaling-on-multiple-metrics-and-custom-metrics
  customRules: []
  #     - type: Pods
  #       pods:
  #         metric:
  #           name: packets-per-second
  #         target:
  #           type: AverageValue
  #           averageValue: 1k
  ## see https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#support-for-configurable-scaling-behavior
  behavior: {}
#      scaleDown:
#        policies:
#          - type: Pods
#            value: 4
#            periodSeconds: 60
#          - type: Percent
#            value: 10
#            periodSeconds: 60

## only available if kind is Deployment
podDisruptionBudget:
  enabled: false
  annotations: {}
  maxUnavailable: "30%"

nodeSelector: {}

tolerations: []

affinity: {}

labels: {}

annotations: {}

podAnnotations: {}

podLabels: {}

## How long (in seconds) a pods needs to be stable before progressing the deployment
##
minReadySeconds:

## How long (in seconds) a pod may take to exit (useful with lifecycle hooks to ensure lb deregistration is done)
##
terminationGracePeriodSeconds:

priorityClassName: ""

env: []
#  - name: FOO
#    value: "bar"

# The envWithTpl array below has the same usage as "env", but is using the tpl function to support templatable string.
# This can be useful when you want to pass dynamic values to the Chart using the helm argument "--set <variable>=<value>"
# https://helm.sh/docs/howto/charts_tips_and_tricks/#using-the-tpl-function
envWithTpl: []
#  - name: FOO_2
#    value: "{{ .Values.foo2 }}"
#
# foo2: bar2

envFrom: []

# This supports either a structured array or a templatable string
extraContainers: []

# Array mode
# extraContainers:
#   - name: do-something
#     image: busybox
#     command: ['do', 'something']

# String mode
# extraContainers: |-
#   - name: do-something
#     image: bitnami/kubectl:{{ .Capabilities.KubeVersion.Major }}.{{ .Capabilities.KubeVersion.Minor }}
#     command: ['kubectl', 'version']

flush: 1

metricsPort: 2020

extraPorts: []
#   - port: 5170
#     containerPort: 5170
#     protocol: TCP
#     name: tcp
#     nodePort: 30517

extraVolumes: []

extraVolumeMounts: []

updateStrategy: {}
#   type: RollingUpdate
#   rollingUpdate:
#     maxUnavailable: 1

# Make use of a pre-defined configmap instead of the one templated here
existingConfigMap: ""

networkPolicy:
  enabled: false
#   ingress:
#     from: []

# See Lua script configuration example in README.md
luaScripts: {}

## https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/classic-mode/configuration-file
config:
  service: |
    [SERVICE]
        Daemon Off
        Flush {{ .Values.flush }}
        Log_Level {{ .Values.logLevel }}
        Parsers_File /fluent-bit/etc/parsers.conf
        Parsers_File /fluent-bit/etc/conf/custom_parsers.conf
        HTTP_Server On
        HTTP_Listen 0.0.0.0
        HTTP_Port {{ .Values.metricsPort }}
        Health_Check On

  ## https://docs.fluentbit.io/manual/pipeline/inputs
  inputs: |
    [INPUT]
        Name tail
        Path /var/log/containers/*.log
        multiline.parser docker, cri
        Tag kube.*
        Mem_Buf_Limit 5MB
        Skip_Long_Lines On

    [INPUT]
        Name systemd
        Tag host.*
        Systemd_Filter _SYSTEMD_UNIT=kubelet.service
        Read_From_Tail On

  ## https://docs.fluentbit.io/manual/pipeline/filters
  filters: |
    [FILTER]
        Name kubernetes
        Match kube.*
        Merge_Log On
        Keep_Log Off
        K8S-Logging.Parser On
        K8S-Logging.Exclude On

  ## https://docs.fluentbit.io/manual/pipeline/outputs
  outputs: |
    [OUTPUT]
        Name es
        Match kube.*
        Host elasticsearch-master
        Logstash_Format On
        Retry_Limit False

    [OUTPUT]
        Name es
        Match host.*
        Host elasticsearch-master
        Logstash_Format On
        Logstash_Prefix node
        Retry_Limit False

  ## https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/classic-mode/upstream-servers
  ## This configuration is deprecated, please use `extraFiles` instead.
  upstream: {}

  ## https://docs.fluentbit.io/manual/pipeline/parsers
  customParsers: |
    [PARSER]
        Name docker_no_time
        Format json
        Time_Keep Off
        Time_Key time
        Time_Format %Y-%m-%dT%H:%M:%S.%L

  # This allows adding more files with arbitrary filenames to /fluent-bit/etc/conf by providing key/value pairs.
  # The key becomes the filename, the value becomes the file content.
  extraFiles: {}
#     upstream.conf: |
#       [UPSTREAM]
#           upstream1
#
#       [NODE]
#           name       node-1
#           host       127.0.0.1
#           port       43000
#     example.conf: |
#       [OUTPUT]
#           Name example
#           Match foo.*
#           Host bar

# The config volume is mounted by default, either to the existingConfigMap value, or the default of "fluent-bit.fullname"
volumeMounts:
  - name: config
    mountPath: /fluent-bit/etc/conf

daemonSetVolumes:
  - name: varlog
    hostPath:
      path: /var/log
  - name: varlibdockercontainers
    hostPath:
      path: /var/lib/docker/containers
  - name: etcmachineid
    hostPath:
      path: /etc/machine-id
      type: File

daemonSetVolumeMounts:
  - name: varlog
    mountPath: /var/log
  - name: varlibdockercontainers
    mountPath: /var/lib/docker/containers
    readOnly: true
  - name: etcmachineid
    mountPath: /etc/machine-id
    readOnly: true

command:
  - /fluent-bit/bin/fluent-bit

args:
  - --workdir=/fluent-bit/etc
  - --config=/fluent-bit/etc/conf/fluent-bit.conf

# This supports either a structured array or a templatable string
initContainers: []

# Array mode
# initContainers:
#   - name: do-something
#     image: bitnami/kubectl:1.22
#     command: ['kubectl', 'version']

# String mode
# initContainers: |-
#   - name: do-something
#     image: bitnami/kubectl:{{ .Capabilities.KubeVersion.Major }}.{{ .Capabilities.KubeVersion.Minor }}
#     command: ['kubectl', 'version']

logLevel: info

hotReload:
  enabled: false
  image:
    repository: ghcr.io/jimmidyson/configmap-reload
    tag: v0.15.0
    digest:
    pullPolicy: IfNotPresent
  resources: {}
  extraWatchVolumes: []
  securityContext:
    privileged: false
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    capabilities:
      drop:
        - ALL

```





### Exercise

1, deploy an nginx deployment
2, make the input specified for that container only
3, see the logs properly


#### Cleaup

```bash
helm uninstall fluent-bit -n monitoring
helm uninstall loki -n monitoring
```
