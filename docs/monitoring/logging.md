```bash
# Install cluster level logging tools: Loki, Fluent-Bit, and Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki -n monitoring --create-namespace
helm install fluent-bit grafana/fluent-bit -n monitoring
helm install grafana grafana/grafana -n monitoring

# Fluent Bit installation
# resource: https://docs.fluentbit.io/manual/installation/downloads/kubernetes
helm repo add fluent https://fluent.github.io/helm-charts
helm upgrade --install fluent-bit fluent/fluent-bit


helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki \
  --namespace monitoring \
  --create-namespace

helm install fluent-bit grafana/fluent-bit \
  --namespace monitoring
```
