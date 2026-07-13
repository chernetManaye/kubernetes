## Design and arctecture


- we will have 4 CronJobs one pairs for volume snapshotting one pairs for backup
- the snapshot will be taken every hour using a CronJob and the deletion of old snapshots is in 24 hours
- backup will be take every 6 hours and backups more than 7 days in s3 will be remove 
- for snashots we use fsynclock() and fsyncunlock() every single hour 

## Installation and Configuration

```bash
# add the snashot controller repository
helm repo add piraeus https://piraeus.io/helm-charts/
helm repo update

# install the snapshot controller
helm install snapshot-controller piraeus/snapshot-controller -n kube-system

# verification commands
kubectl get pods -n kube-system | grep snapshot
kubectl get crd | grep snapshot

# create the volume snapshot class
cat > /home/ubuntu/manifests/volumesnapshotclass.yaml <<'EOF'
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ebs-snapshot-class
driver: ebs.csi.aws.com
deletionPolicy: Delete
EOF

# apply the volume snapshot class
kubectl apply -f /home/ubuntu/manifests/volumesnapshotclass.yaml

```

CronJob to take hourly snapshots of a MongoDB PVC using EBS snapshots.
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mongodb-hourly-snapshot
spec:
  schedule: "0 * * * *"

  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: default
          containers:
          - name: snapshot
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              SNAPSHOT="mongodb-$(date +%Y%m%d-%H%M%S)"

              cat <<EOF >/tmp/snapshot.yaml
              apiVersion: snapshot.storage.k8s.io/v1
              kind: VolumeSnapshot
              metadata:
                name: ${SNAPSHOT}
              spec:
                volumeSnapshotClassName: ebs-snapshot
                source:
                  persistentVolumeClaimName: mongodb-data
              EOF

              kubectl apply -f /tmp/snapshot.yaml
              echo "Waiting for snapshot..."

              until [ "$(kubectl get volumesnapshot ${SNAPSHOT} -o jsonpath='{.status.readyToUse}')" = "true" ]
              do
                sleep 5
              done

              echo "Snapshot completed."
```

Clean up CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mongodb-snapshot-cleanup
spec:
  schedule: "30 2 * * *"

  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: snapshot-manager

          containers:
          - name: cleanup
            image: bitnami/kubectl:latest

            command:
            - /bin/sh
            - -c
            - |
              KEEP=48

              kubectl get volumesnapshot \
                --sort-by=.metadata.creationTimestamp \
                -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
              | head -n -${KEEP} \
              | while read SNAPSHOT
                do
                  if [ -n "$SNAPSHOT" ]; then
                    echo "Deleting $SNAPSHOT"
                    kubectl delete volumesnapshot "$SNAPSHOT"
                  fi
                done
```

Cron job for backup every six hour

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mongodb-backup
spec:
  schedule: "0 */6 * * *"

  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: mongodb-backup

          containers:
          - name: backup

            image: yourrepo/mongodb-backup:latest

            command:
            - /bin/sh
            - -c
            - |
              TIMESTAMP=$(date +%Y%m%d-%H%M%S)

              mkdir -p /backup

              mongodump \
                --host mongodb-service \
                --username "$MONGO_USERNAME" \
                --password "$MONGO_PASSWORD" \
                --authenticationDatabase admin \
                --gzip \
                --archive=/backup/${TIMESTAMP}.gz

              aws s3 cp \
                /backup/${TIMESTAMP}.gz \
                s3://my-mongodb-backups/${TIMESTAMP}.gz

              rm -rf /backup/*
```


Cronjob for backup deletion

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mongodb-backup-cleanup
spec:
  schedule: "30 2 * * *"

  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: mongodb-backup

          containers:
          - name: cleanup

            image: amazon/aws-cli:latest

            command:
            - /bin/sh
            - -c
            - |
              aws s3 rm \
                s3://my-mongodb-backups \
                --recursive \
                --exclude "*" \
                --include "*.gz" \
                --only-show-errors \
                --recursive

              aws s3api list-objects-v2 \
                --bucket my-mongodb-backups \
                --query "Contents[?LastModified<=\`$(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%SZ)\`].Key" \
                --output text \
              | while read KEY
              do
                  [ -z "$KEY" ] && continue
                  aws s3 rm s3://my-mongodb-backups/$KEY
              done
```
S3 Lifecycle Rule

An S3 Lifecycle Rule is a configuration on the bucket itself. AWS automatically manages objects according to the rule—you don't need a CronJob.


Lifecycle rules can also:
Delete old files
Move files to cheaper storage classes (like Glacier)
Archive files after a certain number of days
Delete incomplete multipart uploads

0-30 days     → Standard
30-90 days    → Standard-IA
90-365 days   → Glacier
>365 days     → Delete

Amazon Data Lifecycle Manager (DLM)

```

┌──────── Minute (0-59)
│ ┌────── Hour (0-23)
│ │ ┌──── Day of month (1-31)
│ │ │ ┌── Month (1-12)
│ │ │ │ ┌─ Day of week (0-7, where 0 or 7 = Sunday)
│ │ │ │ │
* * * * *

```


backup with mongodump

```bash
mongodump --version 

which mongodump
```

```bash
mongodump --uri="mongodb://username:password@host:27017"

# or 

mongodump \
  --host localhost \
  --port 27017 \
  --username backupUser \
  --password password \
  --authenticationDatabase admin

```


backup an entire server

```bash

mongodump \
  --uri="mongodb://admin:password@localhost:27017"
```

output looks like 


```
dump/

    admin/

    config/

    local/

    mydatabase/
```

backup a specific database

```bash
mongodump \
  --uri="mongodb://admin:password@localhost:27017" \
  --db shadoshops
```

```
dump/

    shadoshops/
```


backup a specific collection

```bash
mongodump \
  --uri="mongodb://admin:password@localhost:27017" \
  --db shadoshops \
  --collection products
  
```



```

dump/

    shadoshops/

        products.bson

        products.metadata.json

        users.bson

        users.metadata.json

```

Produce a compressed archive
```bash
mongodump \
  --uri="mongodb://admin:password@localhost:27017" \
  --archive=backup.archive \
  --gzip
```

for a replica set

```bash
mongodump \
--uri="mongodb://user:pass@mongo-0,mongo-1,mongo-2/?replicaSet=rs0" \
--oplog
```

Restore
```bash
mongorestore --archive=backup.archive

or

mongorestore /dump
```


I did not undertstand the next concept:


These CronJobs need permission to create, list, and delete VolumeSnapshot resources. By default, the default ServiceAccount usually won't have those permissions.

You'll need to create:

A dedicated ServiceAccount
A ClusterRole (or Role) with permissions for volumesnapshots.snapshot.storage.k8s.io
A ClusterRoleBinding (or RoleBinding)

Then set:

serviceAccountName: snapshot-manager

in both CronJobs.

That is the standard Kubernetes approach and is more secure than granting broad permissions to the default ServiceAccount.

questions:

1, what is a service Account?
A ServiceAccount is simply an identity for applications running inside Kubernetes.
2, what is the default service account?
3, how does k8s implements RBAC?

The explain the text also prperly cluster role and permission an role binding
