## Install the Velero CLI on the control plane

<!--resource: https://velero.io/docs-->
<!--resource: https://velero.io/docs/main/supported-providers-->
Download the latest release (replace the version if needed):

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

## Create an s3 bucket

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

## create an IAM role with s3 and snapshots policy

```bash
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.12.2 \
    --bucket velero-kubernetes-cluster-backups \
    --no-secret \
    --backup-location-config region=eu-central-1 \
    --snapshot-location-config region=eu-central-1

velero uninstall
```

For CSI snapshots:

You need

CSI driver
VolumeSnapshotClass
PVCs using that CSI driver
Snapshot support enabled

```
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
"s3:ListBucket"
```                

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
kubectl get crd | grep velero

velero backup-location get
velero snapshot-location get

velero backup create mongo-backup

velero backup create mongo-backup \
    --include-namespaces database

velero restore create \
    --from-backup mongo-backup

velero backup create wordpress-backup \
    --default-volumes-to-fs-backup
    
velero restore create \
    --from-backup wordpress-backup


velero backup get
velero backup describe mongo-backup --details
velero backup logs mongo-backup

velero restore get
velero restore describe <restore-name>


velero schedule create daily-backup \
  --schedule="0 2 * * *"

velero schedule get

velero schedule describe daily-backup

velero schedule delete daily-backup

velero restore create \
  --from-backup production \
  --existing-resource-policy update
```
