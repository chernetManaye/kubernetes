```bash
# Add Fluent Helm repo and install Fluent Bit
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

helm search repo fluent
```

### 1, fluent/fluent-bit   

The Helm chart for Fluent Bit running as a standalone agent.

```bash
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
--set serviceMonitor.enabled=true


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


### 2, fluent/fluent-operator  
### 3, fluent/fluent-operator-fluent-bit-crds	
### 4, fluent/fluent-bit-aggregator 
### 5, fluent/fluent-bit-collector


### Exercise

1, deploy an nginx deployment
2, make the input specified for that container only
3, see the logs properly
