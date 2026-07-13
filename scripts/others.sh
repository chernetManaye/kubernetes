# Add the headlamp repository
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update

kubectl create namespace headlamp

# Install headlamp
helm install headlamp headlamp/headlamp -n headlamp

# # Add the prometheus-community repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

Also remember to install mongod-exporter so it can be scraped by Prometheus

# # Install monitoring stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace kube-admin --create-namespace

# Get Grafana admin password
kubectl get secret monitoring-grafana \
-n kube-admin \
-o jsonpath="{.data.admin-password}" | base64 -d

# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd \
-f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml


# Install cluster level logging tools: Loki, Fluent-Bit, and Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki -n monitoring --create-namespace
# for loki
# grafana:
#   additionalDataSources:
#     - name: Loki
#       type: loki
#       access: proxy
#       url: http://loki.monitoring.svc.cluster.local:3100
#
# helm show values grafana/loki > loki-values.yaml
# helm show values grafana/loki

helm install fluent-bit grafana/fluent-bit -n monitoring
# for fluentbit
# config:
#   outputs: |
#     [OUTPUT]
#         Name loki
#         Match *
#         Host loki.monitoring.svc.cluster.local
#         Port 3100
# helm show values grafana/fluent-bit > fluent-bit-values.yaml
# helm show values grafana/fluent-bit


helm install grafana grafana/grafana -n monitoring


# helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
#   -n monitoring \
#   --set grafana.additionalDataSources[0].name=Loki \
#   --set grafana.additionalDataSources[0].type=loki \
#   --set grafana.additionalDataSources[0].access=proxy \
#   --set grafana.additionalDataSources[0].url=http://loki.monitoring.svc.cluster.local:3100 \
# --set grafana.additionalDataSources[1].name=Tempo \
# --set grafana.additionalDataSources[1].type=tempo \
# --set grafana.additionalDataSources[1].access=proxy \
# --set grafana.additionalDataSources[1].url=http://tempo.monitoring.svc.cluster.local:3100

# helm install fluent-bit grafana/fluent-bit \
#   -n monitoring \
#   --set config.outputs='[OUTPUT]
#     Name loki
#     Match *
#     Host loki.monitoring.svc.cluster.local
#     Port 3100'

# grafana:
#   additionalDataSources:
#     - name: Tempo
#       type: tempo
#       access: proxy
#       url: http://tempo.monitoring.svc.cluster.local:3100

cat > /home/ubuntu/fluent-bit-values.yaml <<'EOF'
config:
  outputs: |
    [OUTPUT]
        Name  loki
        Match *
        Host  loki.monitoring.svc.cluster.local
        Port  3100
EOF
helm install fluent-bit grafana/fluent-bit \
  -n monitoring \
  -f fluent-bit-values.yaml

# what is Fluent Bit's [OUTPUT] block?
#
helm show values grafana/tempo > tempo-values.yaml
helm install tempo grafana/tempo \
  -n monitoring

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

helm repo update

helm show values open-telemetry/opentelemetry-collector > otel-values.yaml

helm install otel-collector \
    open-telemetry/opentelemetry-collector \
    -n monitoring

helm install otel-collector \
open-telemetry/opentelemetry-collector \
-n monitoring \
--set config.exporters.otlp.endpoint=tempo.monitoring.svc.cluster.local:4317 \
--set config.exporters.otlp.tls.insecure=true


# exporters:
#   otlp:
#     endpoint: tempo.monitoring.svc.cluster.local:4317
#     tls:
#       insecure: true

# service:
#   pipelines:
#     traces:
#       receivers:
#         - otlp

#       processors:
#         - batch

#       exporters:
#         - otlp


# Enabling hubble
helm install cilium cilium/cilium \
  -n kube-system \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true

kubectl port-forward -n kube-system svc/hubble-ui 12000:80

kubectl port-forward -n kube-system svc/hubble-relay 4245:80


# Join the Kubernetes cluster as worker node
# sudo kubeadm join 18.185.239.164:6443 --token 774yb5.9phbt6tphz8mjysc \
# 	--discovery-token-ca-cert-hash sha256:5bf2e9829bc6267a1db375a2bae36f3d527ab409c536f4acccc12873e4ab5966 \
# 	--node-name=$(hostname -f)

# Join the Kubernetes cluster as control plane node
# kubeadm join 10.0.0.245:6443 --token 8sst2z.yb2ycwje84g9c9wu \
# 	--discovery-token-ca-cert-hash sha256:991be94561034d9701af51f66f45bfdc5ab0142c85f3fbf3cb7f2197acc0f587 \
# 	--control-plane \
# 	--node-name=$(hostname -f)
