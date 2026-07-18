### Prometheus helm chart for container resource monitoring

``` bash
# Add the prometheus community helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
# Install prometheus community chart
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --timeout 20m \
  --wait

# Create grafana directory
mkdir -p /home/ubuntu/grafana

# Create grafana ingress
cat <<EOF > /home/ubuntu/grafana/grafana-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: grafana
spec:
  ingressClassName: nginx
  rules:
    - host: grafana.shadoshops.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 80
EOF

kubectl apply -f /home/ubuntu/grafana/grafana-ingress.yaml


# Upgrade monitoring
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
--namespace monitoring

```
### Grafana helm chart for cluster level logging

``` bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install fluent-bit
helm install fluent-bit grafana/fluent-bit \
  --namespace monitoring

# Install loki
helm install loki grafana/loki \
  --namespace monitoring \
  --create-namespace
```
