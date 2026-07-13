A secret stores sensitive data. ex: Database passwords, API keys, JWT signing keys, SSH private keys, TLS certificates

ways to create create secrets:

1, literal values

```bash
kubectl create secret generic <secret-name> --from-literal=<key>=<value>

# example
kubectl create secret generic db-secret \
  --from-literal=username=admin \
  --from-literal=password=mysecret
```

2, from a file

```yaml
apiVersion: v1
kind: Secret

metadata:
  name: db-secret

type: Opaque

stringData:
  username: admin
  password: mysecret
```

Secret Usages:

1, as environment variables

updating secrets will not update the environment variables the pods may need to restart

```yaml
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: db-secret
      key: password

```

2, as volume mounts

updating secrets will update the volume mounts with some delay

```yaml
volumes:
- name: db-secret
  secret:
    secretName: db-secret

```

There are immutable secrets

```yaml
immutable: true
```

suggestions and recommendations 

1, use external secret management solutions like HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, or Google Secret Manager
2, Enable encryption at rest for secrets using Kubernetes Secrets Encryption


Secret types

1, opaque

2, tls 

tls.crt
tls.key

```bash
kubectl create secret tls <secret-name> --cert=<path-to-cert> --key=<path-to-key>

# example
kubectl create secret tls api-tls --cert=tls.crt --key=tls.key
```
usage in ingress

```yaml
spec:
  tls:
  - hosts:
      - api.shadoshops.com
    secretName: api-tls
```
3, docker registry secrets

```bash
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=myuser \
  --docker-password=mypassword \
  --docker-email=me@example.com
```
usage inside pod

```yaml
spec:
  imagePullSecrets:
    - name: dockerhub-secret

  containers:
    - image: chernet/private-api:v1
```
