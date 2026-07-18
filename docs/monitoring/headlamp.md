
### Installation
```bash
# Add headlamp repository
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update

# Install headlamp chart
helm install headlamp headlamp/headlamp \
  --namespace headlamp --create-namespace

# Create headlamp directory
mkdir -p /home/ubuntu/headlamp

# Create headlamp ingress
cat <<EOF > /home/ubuntu/headlamp/headlamp-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: headlamp
  namespace: headlamp
spec:
  ingressClassName: nginx
  rules:
    - host: headlamp.shadoshops.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: headlamp
                port:
                  number: 80
EOF

kubectl apply -f /home/ubuntu/headlamp/headlamp-ingress.yaml

# Create headlamp service account
cat <<EOF > /home/ubuntu/headlamp/headlamp-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: headlamp-admin
  namespace: headlamp
EOF

kubectl apply -f /home/ubuntu/headlamp/headlamp-sa.yaml

# Create headlamp role
cat <<EOF > /home/ubuntu/headlamp/headlamp-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-admin
subjects:
- kind: ServiceAccount
  name: headlamp-admin
  namespace: headlamp
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
EOF

kubectl apply -f /home/ubuntu/headlamp/headlamp-role.yaml

# Create headlamp token and save it to a file
kubectl create token headlamp-admin \
  -n headlamp \
  --duration=720h > /home/ubuntu/headlamp/headlamp-token.txt
```


```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: headlamp
  namespace: headlamp
spec:
  ingressClassName: nginx
  rules:
    - host: headlamp.shadoshops.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: headlamp
                port:
                  number: 80
```

## Generate a service account token 
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: headlamp-admin
  namespace: headlamp
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-admin
subjects:
- kind: ServiceAccount
  name: headlamp-admin
  namespace: headlamp
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
```


```bash
kubectl create token headlamp-admin \
  -n headlamp


kubectl create token headlamp-admin \
  -n headlamp \
  --duration=24h
```

Step 7. Verify the token yourself

You can test it with curl:

```bash
TOKEN=$(kubectl create token headlamp-admin -n headlamp-users)
APISERVER=https://<api-server-ip>:6443
curl \
  --cacert /etc/kubernetes/pki/ca.crt \
  -H "Authorization: Bearer $TOKEN" \
  $APISERVER/api
```

If the token is valid, you'll receive JSON similar to:

```json
{
  "kind": "APIVersions",
  "versions": [
    "v1"
  ]
}
```


```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:headlamp-users:headlamp-admin
```


```bash
mkdir -p /home/ubuntu/headlamp
cd /home/ubuntu/headlamp

cat <<EOF > headlamp-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: headlamp
  namespace: headlamp
spec:
  ingressClassName: nginx
  rules:
    - host: headlamp.shadoshops.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: headlamp
                port:
                  number: 80
EOF

kubectl apply -f headlamp-ingress.yaml

cat <<EOF > headlamp-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: headlamp-admin
  namespace: headlamp
EOF

kubectl apply -f headlamp-sa.yaml

cat <<EOF > headlamp-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: headlamp-admin
subjects:
- kind: ServiceAccount
  name: headlamp-admin
  namespace: headlamp
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
EOF

kubectl apply -f headlamp-role.yaml

kubectl create token headlamp-admin \
  -n headlamp

kubectl create token headlamp-admin \
  -n headlamp \
  --duration=720h > headlamp-token.txt

cd ~
```
