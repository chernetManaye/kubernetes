# velero - cluster backuping tool

### Install the Velero CLI on the control plane

<!--resource: https://velero.io/docs-->
<!--resource: https://velero.io/docs/main/supported-providers-->

```bash
# Download the latest release (replace the version if needed):
wget https://github.com/vmware-tanzu/velero/releases/download/v1.16.2/velero-v1.16.2-linux-amd64.tar.gz

# Extract it:
tar -xzf velero-v1.16.2-linux-amd64.tar.gz

# Move the binary:
sudo mv velero-v1.16.2-linux-amd64/velero /usr/local/bin/

# Verify the installation:
velero version

# Clean up:
rm -rf velero-v1.16.2-linux-amd64 velero-v1.16.2-linux-amd64.tar.gz
```

### Create an s3 bucket

```hcl
resource "aws_s3_bucket" "velero" {
  bucket = "velero-kubernetes-cluster-backups"
  # force_destroy = true
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket = aws_s3_bucket.velero.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "bucket_name" {
  value = aws_s3_bucket.velero.bucket
}

# what is this?
# If you wanted to use KMS instead:

# sse_algorithm = "aws:kms"
# kms_master_key_id = aws_kms_key.s3.arn
```

<!--For a production Velero bucket, these four resources (bucket, versioning, public access block, and server-side encryption) are the standard minimum configuration.-->

### create an IAM role with s3 and snapshots policies

```hcl
"ec2:DescribeVolumes",
"ec2:DescribeSnapshots",
"ec2:CreateTags",
"ec2:CreateVolume",
"ec2:CreateSnapshot",
"ec2:DeleteSnapshot",
"s3:GetObject",
"s3:DeleteObject",
"s3:PutObject",
"s3:PutObjectTagging",
"s3:AbortMultipartUpload",
"s3:ListMultipartUploadParts",
"s3:ListBucket",
```


### Install the velero server to the cluster
```bash
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.12.2 \
    --features=EnableCSI \
    --bucket velero-kubernetes-cluster-backups \
    --no-secret \
    --backup-location-config region=eu-central-1 \
    --snapshot-location-config region=eu-central-1

# to uninstall
velero uninstall
```

```bash
kubectl get pod ebs-csi-controller-767c89688b-d7fs8 -n kube-system \
  -o jsonpath='{.spec.containers[*].name}'
```

<!--Take this inmind-->

For **Dynamic Provisioning**: The EBS CSI driver automatically tags dynamically created volumes and snapshots. No extra steps are needed.

For **Existing/Static Snapshots**: If you ever try to restore an EBS snapshot that was not created by this CSI driver instance, it will fail unless you manually add the following AWS tag to that snapshot: ebs.csi.aws.com/cluster = true.


For CSI snapshots You need:

- CSI driver with Snapshot support enabled
- PVCs using that CSI driver
- Kubernetes snapshot controller and CRDs


```bash
kubectl get crd | grep velero
kubectl get crd | grep snapshot
```

### Basic commands

- get velero version
```bash
velero version
velero version --client-only=false
```

#### Backup 
- get backups 

```bash
velero backup get
```

- describe backup

```bash
velero backup describe <backup-name>
# or
velero backup describe <backup-name> --details
```

- view logs
```bash
velero backup logs <backup-name>
```
- create a backup

```bash
# backup everything
velero backup create <backup-name>
# backup specific namespace
velero backup create <backup-name> \
    --include-namespaces <namespace>
# backup multiple namespaces
velero backup create <backup-name> \
    --include-namespaces <namespace>,<namespace2>
# exclude specific namespace
velero backup create <backup-name> \
    --exclude-namespaces <namespace>
# exclude multiple namespaces
velero backup create <backup-name> \
    --exclude-namespaces <namespace>,<namespace2>
```

- Delete a backup
```bash
velero backup delete <backup-name>
# to skip confirmation
velero backup delete <backup-name> --confirm
```

#### Restore

- get restores
```bash
velero restore get
```
- Restore from backup
```bash
velero restore create \
  --from-backup <backup-name> 

# Give it a custom name   
velero restore create <restore-name> \
  --from-backup <backup-name>

# Restore to a specific namespace
velero restore create <restore-name> \
  --from-backup <backup-name> \
  --namespace <namespace>
```
- Describe a restore
```bash
velero restore describe <restore-name>
```
- Restore logs
```bash
velero restore logs <restore-name>
```
- Delete a restore
```bash
velero restore delete <restore-name>
# or skip confirmation
velero restore delete <restore-name> --confirm
```

#### Scheduling

- Create a schedule
```bash
velero schedule create <schedule-name> \
  --schedule "<cron-schedule>" 

# Create a schedule with namespace inclusion
velero schedule create <schedule-name> \
  --schedule "<cron-schedule>" \
  --include-namespaces <namespace>
```
- Get scheduled backups
```bash
velero schedule get
```
- Describe a schedule
```bash
velero schedule describe <schedule-name>
```

- Delete a schedule
```bash
velero schedule delete <schedule-name>
# or skip confirmation
velero schedule delete <schedule-name> --confirm
```

#### Locations

- backup location
```bash
velero backup-location get
```
- Describe a backup location
```bash
velero backup-location describe <location-name>
```
- Delete a backup location
```bash
velero backup-location delete <location-name>
# or skip confirmation
velero backup-location delete <location-name> --confirm
```

- snapshot location
```bash
velero snapshot-location get
```
- Describe a snapshot location
```bash
velero snapshot-location describe <location-name>
```
- Delete a snapshot location
```bash
velero snapshot-location delete <location-name>
# or skip confirmation
velero snapshot-location delete <location-name> --confirm
```

#### Plugins

- List plugins
```bash
velero plugin get
```

- Add a plugin
```bash
velero plugin add <plugin-name>
# plugin name structure: velero/velero-plugin-for-aws:v1.12.2
```

#### Repositories

- List repositories
```bash
velero repo get
```

- Describe a repository
```bash
velero repo describe <repo-name>
```
- Delete a repository
```bash
velero repo delete <repo-name>
# or skip confirmation
velero repo delete <repo-name> --confirm
```

#### Debug
```bash
velero debug
```

#### help
```bash
# Top level help
velero help
# or for a specific command
velero backup --help
```


### Demonstration

- create a velero-demo folder in home directory
```bash
mkdir ~/velero-demo
cd ~/velero-demo
```

- create deployment

```bash
cat <<EOF > deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: velero-demo
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 1
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
          - name: web-storage
            mountPath: /usr/share/nginx/html
      volumes:
      - name: web-storage
        persistentVolumeClaim:
          claimName: nginx-pvc
EOF
```

- create service

```bash
cat <<EOF > service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: velero-demo
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
    - port: 80
      targetPort: 80
EOF
```
- create limit range

```bash
cat <<EOF > limitrange.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: velero-demo-limitrange
  namespace: velero-demo
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

- create pvc

```bash
cat <<EOF > pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-pvc
  namespace: velero-demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: ebs-gp3-sc
EOF
```

- Create the namespace

```bash
kubectl create namespace velero-demo
```

- apply resources
```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f limitrange.yaml
kubectl apply -f pvc.yaml
```

#### use velero to backup
##### make sure you always create backup resources in velero namespace in which velero is installed

- create a backup
```bash
velero backup create nginx-backup --include-namespaces velero-demo
```

- list backups

```bash
velero backup get
```
```bash
velero backup describe nginx-backup -n velero
velero backup describe nginx-backup -n velero --details
```

```bash
velero backup logs nginx-backup -n velero
```

- delete a backup
```bash
velero backup delete nginx-backup -n velero
```








requirments

Set the storage class to default 
```yaml
annotations:
  snapshot.storage.kubernetes.io/is-default-class: "true"
```
