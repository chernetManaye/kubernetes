ACME = Automatic Certificate Management Environment
```bash
# Add cert-manager repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager chart
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.21.0  \
  --set crds.enabled=true

kubectl get pods -n cert-manager -w

# List all Issuers, ClusterIssuers, Certificates, CertificateRequests, Orders, and Challenges in all namespaces
kubectl get Issuers,ClusterIssuers,Certificates,CertificateRequests,Orders,Challenges --all-namespaces
  

helm template cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.21.0 \
  --set crds.enabled=true > cert-manager.yaml

helm show values jetstack/cert-manager \
  --version v1.21.0 > values.yaml

helm show all jetstack/cert-manager --version v1.21.0

helm pull jetstack/cert-manager \
  --version v1.21.0 \
  --untar

```
```
cert-manager

├── cert-manager
│     Main controller
│
├── cert-manager-webhook
│     Validates CRDs
│
└── cert-manager-cainjector
      Injects CA certificates
```
letsencrypt-clusterissuer.yaml
```yaml
# ClusterIssuer for Let's Encrypt staging
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: chernet491@gmail.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
      - dns01:
          route53:
            region: eu-central-1
---
# ClusterIssuer for Let's Encrypt production
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    email: chernet491@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-production-account-key
    solvers:
    - dns01:
        route53:
          region: eu-central-1
```

certificate.yaml
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: oidc-cert
spec:
  secretName: oidc-tls
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-production
  dnsNames:
    - oidc.shadoshops.com
```

```
How HTTP-01 actually works

When you create a Certificate, cert-manager does this:

Creates a CertificateRequest.
Creates an Order.
Creates a Challenge.
Creates a temporary Pod (acmesolver).
Creates a temporary Service pointing to that Pod.
Creates a temporary Ingress that routes only
/.well-known/acme-challenge/<token>
```


## Demonstration
```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: default
spec:
  replicas: 2
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
          image: nginx:1.29
          ports:
            - containerPort: 80
            
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: default
spec:
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  type: ClusterIP

---

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-http
  namespace: default
spec:
  ingressClassName: nginx

  rules:
    - host: api.shadoshops.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
---

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-https
  namespace: default
spec:
  ingressClassName: nginx

  tls:
    - hosts:
        - api.shadoshops.com
      secretName: api-tls

  rules:
    - host: api.shadoshops.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80

```


```
Namespace
└── cert-manager

Deployments
├── cert-manager
├── cert-manager-webhook
└── cert-manager-cainjector

Pod
├── controller
├── webhook
├── cainjector
└── startup check

CRDs
├── Certificate
├── CertificateRequest
├── Issuer
├── ClusterIssuer
├── Challenge
└── Order
```

## Recommendations

- One ClusterIssuer for staging.
- One ClusterIssuer for production.
- One ACME account key secret for each issuer.
- One wildcard Certificate for *.shadoshops.com.
- One wildcard TLS secret (for example, wildcard-tls) that all your Ingress resources reference.


## Cleanup workflow 
```bash
# 1, Delete the ingress which uses the cert
# 2, Delete the certificate
# 3, Delete the TLS secret
# 4, Delete the ClusterIssuer
# 5, Delete the ACME account key secret
# 6, Uninstall cert-manager
```
