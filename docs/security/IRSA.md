# IRSA - IAM Roles for Service Accounts

### IMDS(Instance Metadata Service) vs IRSA

```
Environment variables
        ↓
Shared credentials file (~/.aws/credentials)
        ↓
Web Identity Token (IRSA)
        ↓
EC2 Instance Metadata Service (IMDS)
```

## Setting up IRSA

```bash
/var/run/secrets/kubernetes.io/serviceaccount/token
```
```bash
kubectl get --raw /.well-known/openid-configuration | jq
```
```json
{
  "issuer":"https://kubernetes.default.svc.cluster.local",
  "jwks_uri":"https://10.0.0.8:6443/openid/v1/jwks",
  "response_types_supported":["id_token"],
  "subject_types_supported":["public"],
  "id_token_signing_alg_values_supported":["RS256"]
}
```

```bash
kubectl get --raw /openid/v1/jwks | jq
```

```json
{
  "keys": [
    {
      "use": "sig",
      "kty": "RSA",
      "kid": "3Xh-5mDwmI_BlZP6EP3DAfcj-JdimTM3RE2SIi2gZPc",
      "alg": "RS256",
      "n": "wdaxaZqClG9JcCDLLyBPG4DNApGxRf3bbDqQkWNV_EFjqNgwjAzY7zT_bkjmXjv9FcEZ-PqpwBdOniOsVo0vtLuAvcmYFE8nL2EVTjkxLkEZgRUeFvhlivfZfMUtXlehbtZjrfxXFvXLWjmrD4VCXTAtenVuc1oBB55kxdb-16aNJLRb3czlCqZyqMoD60_nM1dxk5fS9KZ1W8ulPdR292olOD2cx7zp9etLGFmnQMRd7D2F0QPreKcQrla7w2QW5HMvHLZxLm76bm0xV_JcVH04kklrJDelG2G9GJHI6jkPK8wiMWQGVqayjE6BvY3AGlJhuLFfM5OSPR4deC71iQ",
      "e": "AQAB"
    }
  ]
}
```


```bash
kubectl get --raw /.well-known/openid-configuration | jq \
> openid-configuration

kubectl get --raw /openid/v1/jwks | jq \
> jwks

kubectl create configmap oidc-documents \
  --from-file=openid-configuration \
  --from-file=jwks


mkdir -p oidc-files/.well-known
mkdir -p oidc-files/openid/v1

kubectl get --raw /.well-known/openid-configuration \
> oidc-files/.well-known/openid-configuration

kubectl get --raw /openid/v1/jwks \
> oidc-files/openid/v1/jwks
```
```yaml
# token-test.yaml
apiVersion: v1
kind: Pod
metadata:
  name: token-test
spec:
  containers:
  - name: busybox
    image: busybox
    command:
      - sleep
      - "3600"
```
```bash
kubectl apply -f token-test.yaml
kubectl exec -it token-test -- sh

ls -l /var/run/secrets/kubernetes.io/serviceaccount

wc -c /var/run/secrets/kubernetes.io/serviceaccount/token

exit

kubectl exec token-test -- cat /var/run/secrets/kubernetes.io/serviceaccount/token

TOKEN=$(kubectl exec token-test -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)

echo "$TOKEN" | tr '.' '\n'

echo "$TOKEN" \
| cut -d '.' -f1 \
| tr '_-' '/+' \
| base64 -d | jq

echo "$TOKEN" \
| cut -d '.' -f2 \
| tr '_-' '/+' \
| base64 -d \
| jq

sudo nano /etc/kubernetes/manifests/kube-apiserver.yaml

```

```bash
https://oidc.shadoshops.com/.well-known/openid-configuration

# download
curl -s https://oidc.shadoshops.com/.well-known/openid-configuration

# then download
https://oidc.shadoshops.com/openid/v1/jwks
```
```bash
sudo grep service-account /etc/kubernetes/manifests/kube-apiserver.yaml
```
```yaml
  - --service-account-issuer=https://kubernetes.default.svc.cluster.local
  - --service-account-key-file=/etc/kubernetes/pki/sa.pub
  - --service-account-signing-key-file=/etc/kubernetes/pki/sa.key
```

what we want is:

```
https://10.0.0.8:6443/.well-known/openid-configuration
https://10.0.0.8:6443/openid/v1/jwks
```


Every pod has a Service Account the default service account. Most simple applications never use it. Controllers and operators use it extensively because they communicate with the Kubernetes API.

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration

clusterName: kubernetes
kubernetesVersion: v1.34.0

apiServer:
  extraArgs:
    encryption-provider-config: /etc/kubernetes/encryption/encryption-config.yaml
    service-account-issuer: https://oidc.example.com
    # for backward compatibility with older clients
    service-account-issuer: https://kubernetes.default.svc.cluster.local
    service-account-jwks-uri: https://oidc.example.com/openid/v1/jwks

  extraVolumes:
    - name: encryption-config
      hostPath: /etc/kubernetes/encryption
      mountPath: /etc/kubernetes/encryption
      readOnly: true
      pathType: Directory
```
## Installation

we have to install the webhook first

we have two options:

1, from github 
2, from helm chart

```bash
helm repo add jkroepke https://jkroepke.github.io/helm-charts
helm repo update

helm install amazon-eks-pod-identity-webhook \
  jkroepke/amazon-eks-pod-identity-webhook \
  --namespace irsa-demo \
  --set config.annotationPrefix=eks.amazonaws.com \
  --set config.defaultAwsRegion=eu-central-1

helm show values jkroepke/amazon-eks-pod-identity-webhook

# we also should Install cert manager if we do not have it already

# Add cert-manager repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager chart
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.21.0  \
  --set crds.enabled=true
  
```

the above script will join the master script command soon

## Demonstration

```bash
mkdir ~/irsa-demo
cd ~/irsa-demo
```

- create a namespace

```bash
kubectl create namespace irsa-demo
```

- create configmaps

1, nginx config 

```bash
cat <<EOF > nginx-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: irsa-demo
data:
  nginx.conf: |
    events {}

    http {
      server {
        listen 80;

        location = /.well-known/openid-configuration {
          default_type application/json;
          alias /usr/share/nginx/html/.well-known/openid-configuration;
        }

        location = /openid/v1/jwks {
          default_type application/json;
          alias /usr/share/nginx/html/openid/v1/jwks;
        }
      }
    }
EOF

kubectl apply -f nginx-config.yaml

kubectl get --raw /.well-known/openid-configuration > openid-configuration

kubectl create configmap openid-config \
    --from-file=openid-configuration \
    -n irsa-demo

kubectl get --raw /openid/v1/jwks > jwks

kubectl create configmap jwks-config \
    --from-file=jwks \
    -n irsa-demo

# for the above two do 3 things make the script one flow, apply it and then remove the json content files after that get the yaml output as a file 
```

- create deployment

```bash
cat <<EOF > deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: irsa-demo
spec:
  replicas: 1
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
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: openid-config
          mountPath: /usr/share/nginx/html/.well-known/openid-configuration
          subPath: openid-configuration
        - name: jwks-config
          mountPath: /usr/share/nginx/html/openid/v1/jwks
          subPath: jwks
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
      - name: openid-config
        configMap:
          name: openid-config
      - name: jwks-config
        configMap:
          name: jwks-config
EOF

kubectl apply -f deployment.yaml
```
- create service

```bash
cat <<EOF > service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: irsa-demo
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
EOF

kubectl apply -f service.yaml
```
- create limit range

```bash
cat <<EOF > limitrange.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: irsa-demo-limitrange
  namespace: irsa-demo
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    default:
      cpu: 500m
      memory: 512Mi
EOF
```

- create http ingress - exposing oidc.shadoshops.com on port 80

```bash
cat <<EOF > irsa-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: irsa-ingress
  namespace: irsa-demo
spec:
  ingressClassName: nginx
  rules:
    - host: oidc.shadoshops.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-service
                port:
                  number: 80
EOF

kubectl apply -f irsa-ingress.yaml
```
- create https ingress - we need to apply the tls secret

```bash
cat <<EOF > irsa-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: irsa-ingress
  namespace: irsa-demo
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - oidc.shadoshops.com
      secretName: oidc-tls
  rules:
    - host: oidc.shadoshops.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx-service
                port:
                  number: 80
EOF
```

```bash
curl http://localhost/.well-known/openid-configuration
curl http://oidc.shadoshops.com/.well-known/openid-configuration
curl https://oidc.shadoshops.com/.well-known/openid-configuration

curl http://localhost/openid/v1/jwks
curl http://oidc.shadoshops.com/openid/v1/jwks
curl https://oidc.shadoshops.com/openid/v1/jwks
```

next
1, terraform configuration for IAM role trust policy with oidc service account 

```hcl
resource "aws_iam_policy" "s3_readonly" {
  name = "irsa-s3-readonly"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_openid_connect_provider" "kubernetes" {
  url = "https://oidc.shadoshops.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = []
}

resource "aws_iam_role" "irsa_demo" {
  name = "irsa-demo-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.kubernetes.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "oidc.shadoshops.com:aud" = "sts.amazonaws.com"
            "oidc.shadoshops.com:sub" = "system:serviceaccount:irsa-demo:s3-reader"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "irsa_demo" {
  role       = aws_iam_role.irsa_demo.name
  policy_arn = aws_iam_policy.s3_readonly.arn
}
```

```bash
cat <<EOF > serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-reader
  namespace: irsa-demo
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::176852750047:role/irsa-demo-role
EOF

kubectl apply -f serviceaccount.yaml
```
```bash
cat <<EOF > aws-cli.yaml
apiVersion: v1
kind: Pod
metadata:
  name: aws-cli
  namespace: irsa-demo
spec:
  serviceAccountName: s3-reader
  containers:
    - name: aws
      image: amazon/aws-cli:latest
      command:
        - sleep
        - infinity
EOF

kubectl apply -f aws-cli.yaml
```


verify 

kubectl describe pod aws-cli
You should see variables like:

AWS_ROLE_ARN
AWS_WEB_IDENTITY_TOKEN_FILE
AWS_REGION


```bash

kubectl exec -it aws-cli -- sh


aws sts get-caller-identity

aws s3 ls

aws s3api list-buckets
```
```
Best: One IAM role per ServiceAccount (StringEquals on a specific sub).
Acceptable: One IAM role per namespace (StringLike with system:serviceaccount:<namespace>:*) when multiple workloads legitimately need the same AWS permissions.
Avoid: system:serviceaccount:*:* unless you intentionally want every ServiceAccount in the cluster to have identical AWS permissions, which is uncommon and significantly broadens access.

```
questions:

1, what is aud?
2, what is sub?
3, can I use my own selfsigned ca and add the thumbprint to the provider and be valid unlike browsers?


2, also install the cert-manager since it needs it 
3, install the webhook 


### Cleanup

```bash
kubectl delete all --all -n irsa-demo

kubectl delete configmap --all -n irsa-demo
kubectl delete secret --all -n irsa-demo
kubectl delete pvc --all -n irsa-demo
kubectl delete ingress --all -n irsa-demo
kubectl delete serviceaccount --all -n irsa-demo
kubectl delete role --all -n irsa-demo
kubectl delete rolebinding --all -n irsa-demo
kubectl delete networkpolicy --all -n irsa-demo

kubectl delete namespace irsa-demo
```
