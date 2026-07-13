## Install the Velero CLI on the control plane

<!--resource: https://velero.io/docs-->
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
```

## Create an s3 bucket

## create an IAM user or role

s3 and ec2 snapshots
AWS_ACCESS_KEY_ID=XXXXXXXX
AWS_SECRET_ACCESS_KEY=YYYYYYYY

```bash
mkdir ~/velero

nano ~/velero/credentials

[default]
aws_access_key_id=YOUR_ACCESS_KEY
aws_secret_access_key=YOUR_SECRET_KEY

velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.12.2 \
    --bucket my-cluster-backups \
    --secret-file ~/velero/credentials \
    --backup-location-config region=eu-central-1 \
    --snapshot-location-config region=eu-central-1


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
