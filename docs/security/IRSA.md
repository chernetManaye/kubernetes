## Setting up IRSA
```
Environment variables
        ↓
Shared credentials file (~/.aws/credentials)
        ↓
Web Identity Token (IRSA)
        ↓
EC2 Instance Metadata Service (IMDS)
```
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

what we want is 

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
    encryption-provider-config: /etc/kubernetes/encryption-config.yaml
    service-account-issuer: https://oidc.example.com
    service-account-jwks-uri: https://oidc.example.com/openid/v1/jwks

  extraVolumes:
    - name: encryption-config
      hostPath: /etc/kubernetes/encryption-config.yaml
      mountPath: /etc/kubernetes/encryption-config.yaml
      readOnly: true
      pathType: File
```
