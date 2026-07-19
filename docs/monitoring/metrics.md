### Prometheus helm chart for container resource monitoring

``` bash
# Add the prometheus community helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install prometheus community chart
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --timeout 20m 


# Create grafana directory
mkdir -p /home/ubuntu/grafana

# Create grafana ingress
cat <<EOF > /home/ubuntu/grafana/grafana-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
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
            name: monitoring-grafana
            port:
              number: 80
EOF

kubectl apply -f /home/ubuntu/grafana/grafana-ingress.yaml


# Get the secret and save the password in a file
kubectl -n monitoring get secret monitoring-grafana \
-o jsonpath="{.data.admin-password}" \
| base64 -d > /home/ubuntu/grafana/grafana-password.txt

```
