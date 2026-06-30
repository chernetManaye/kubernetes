# Storage
## Volume
A volume is just a directory mounted inside a container. Kubernetes decides whether that directory is backed by temporary storage (emptyDir) or persistent storage (PV/PVC via a CSI driver such as AWS EBS)

```bash
apiVersion: v1
kind: Pod
metadata:
  name: no-volume
spec:
  containers:
    - name: app
      image: nginx

      # Application writes here
      # /usr/share/nginx/html/index.html

      # If this container crashes or is recreated,
      # everything written inside the container is lost.

```
```bash
apiVersion: v1
kind: Pod
metadata:
  name: emptydir-demo

spec:

  # Step 1:
  # Kubernetes creates a temporary directory
  volumes:
    - name: cache
      emptyDir: {}     # Deleted when Pod is deleted

  containers:
    - name: app
      image: nginx

      volumeMounts:

        # Step 2:
        # Mount that directory inside the container
        - name: cache
          mountPath: /data

```
```bash
apiVersion: v1
kind: Pod
metadata:
  name: config-demo

spec:

  volumes:
    - name: config

      # Mount files stored inside a ConfigMap
      configMap:
        name: app-config

  containers:
    - name: app
      image: nginx

      volumeMounts:

        # ConfigMap appears as files
        - name: config
          mountPath: /etc/config
```
```bash
volumes:
  - name: secret

    # Mount Kubernetes Secret
    secret:
      secretName: db-password
```
```bash
apiVersion: v1
kind: Pod
metadata:
  name: database

spec:

  volumes:
    - name: database-storage

      # Ask Kubernetes to attach
      # the PersistentVolume claimed by this PVC
      persistentVolumeClaim:

        # Existing PVC name
        claimName: postgres-pvc

  containers:
    - name: postgres
      image: postgres

      volumeMounts:

        # Database stores files here
        - name: database-storage
          mountPath: /var/lib/postgresql/data
```


Application
      │
      │ writes files
      ▼
+----------------------+
|      /data           |   <-- mountPath
+----------------------+
           │
           ▼
+----------------------+
|       Volume         |
+----------------------+
      │           │
      │           │
      │           └─────────────────────────┐
      │                                     │
      ▼                                     ▼
emptyDir                             persistentVolumeClaim
Temporary                            Durable storage request
Deleted with Pod                     Survives Pod deletion
      │                                     │
      │                                     ▼
      │                              PersistentVolume (PV)
      │                                     │
      │                                     ▼
      │                              CSI Driver
      │                                     │
      └──────────────────────────────► AWS EBS
                                       Azure Disk
                                       GCE PD
                                       NFS
                                       Ceph
                                       etc.


## Persistent Volume
The entire purpose of PVs is to make data survive Pod deletion
Pod:	Uses storage
PVC:	Requests storage, owned by the application
PV:	Represents the actual storage, owned by the k8s cluster

### Static and Dynamic Provisioning

Static Provisioning: PVs are created manually by an administrator.

``` text
Admin

↓

Create PV

↓

Developer creates PVC

↓

PVC binds to existing PV

```

Dynamic Provisioning: PVs are created automatically by the k8s cluster using a StorageClass.

``` text
PVC

↓

StorageClass

↓

CSI Driver

↓

Automatically create AWS EBS

↓

PV created automatically
```
### Binding
Kubernetes connects one PVC to one PV. one PVC exactly owns one PV. Pod uses the PVC not PV.

```bash
volumes:
  - name: data
    persistentVolumeClaim:
      claimName: postgres-pvc
```

``` text
PVC

↓

Control Plane

↓

Matching PV

↓

Bound

PVC <-------> PV
```

### Access Modes 

RWO:	One node can read/write. Most common for block storage like AWS EBS.
ROX:	Many nodes can read only.
RWX:	Many nodes can read and write. Used by shared filesystems like NFS.
RWOP:	Only one Pod in the entire cluster can mount the volume read/write.

For AWS EBS you'll almost always use ReadWriteOnce (RWO).

### Lifecycle Policy

#### Delete:

Delete PVC

↓

Delete PV

↓

Delete AWS EBS

#### Retain:

Delete PVC

↓

PV stays

↓

AWS EBS stays

↓

Administrator decides what to do


Increasing storage doesn't create a new disk.

### PV Lifecycle
Available

↓

Bound

↓

Released

↓

Deleted

Meaning:

Available

Nobody owns it.

↓

Bound

PVC owns it.

↓

Released

PVC deleted.

↓

Deleted

Storage removed

A Pod never uses a PersistentVolume directly. It uses a PersistentVolumeClaim (PVC), which either binds to an existing PersistentVolume (static provisioning) or causes one to be created automatically through a StorageClass and CSI driver (dynamic provisioning).


The full workflow
Application
      │
      │ writes files
      ▼
/var/lib/postgresql/data
      │
      ▼
Pod
      │
      ▼
PersistentVolumeClaim (PVC)
      │
      │ "I need 20Gi, RWO"
      ▼
StorageClass
      │
      ▼
CSI Driver (AWS EBS CSI)
      │
      ▼
Creates AWS EBS volume
      │
      ▼
PersistentVolume (PV)
      │
      ▼
AWS EBS Disk

## Storage Classes

A StorageClass is a template that tells Kubernetes how to create storage when a PVC requests it.

A StorageClass is a blueprint for dynamic provisioning. It tells Kubernetes which CSI driver to use and how to create new storage when a PersistentVolumeClaim requests it.

```bash
PVC

↓

StorageClass
(How should I create storage?)

↓

CSI Driver

↓

AWS EBS created automatically
```

```yaml

apiVersion: storage.k8s.io/v1
kind: StorageClass

metadata:
  name: ebs-gp3          # Name used by PVCs

# Which CSI driver should create storage? example: efs.csi.aws.com, disk.csi.azure.com etc
provisioner: ebs.csi.aws.com

# Which type of EBS disk? example: gp3, io2, io1. these are cloud provider-specific
parameters:
  type: gp3
  encrypted: "true"
  csi.storage.k8s.io/fstype: xfs

# Can the disk grow later? example: 20Gi -> 50Gi in PVC will allow the disk to grow to 50Gi
allowVolumeExpansion: true

# Delete or keep the disk after the PVC is deleted?
reclaimPolicy: Delete

# When should Kubernetes actually create the disk?
# Wait until a Pod is scheduled before creating the EBS volume,
# ensuring it is created in the correct Availability Zone.
volumeBindingMode: WaitForFirstConsumer

```

A cluster can have one default storage class, which is used by PVCs that don't specify a storage class.

PVC references the storage class to determine how to create the disk. Pods reference the PVC to use the disk. Pods -> PVC -> StorageClass -> CSI Driver -> Cloud Provider


## Dynamic Provisioning

Dynamic Provisioning eliminates manual storage creation. A developer creates only a PersistentVolumeClaim (PVC), and Kubernetes uses the referenced StorageClass and CSI driver to automatically create the real storage and its corresponding PersistentVolume.

Dynamic Provisioning means Kubernetes automatically creates a storage volume (PV + actual disk) when a PVC is created.

without:
Admin creates EBS

↓

Admin creates PV

↓

Developer creates PVC

↓

PVC binds to PV

with:
Developer creates PVC

↓

StorageClass

↓

CSI Driver

↓

AWS EBS created automatically

↓

PV created automatically

↓

PVC binds

↓

Pod uses storage

In dynamic provisioning, the administrator creates a StorageClass that defines how to create storage when a PVC is created. The StorageClass is referenced by the PVC, and the CSI Driver creates the actual disk.


Administrator
      │
      ▼
Creates StorageClass
      │
      ▼
+-----------------------------+
| StorageClass                |
|-----------------------------|
| provisioner: ebs.csi.aws.com|
| type: gp3                   |
| expansion: true             |
+-----------------------------+

                │
                ▼

Developer creates PVC
                │
                ▼
+-----------------------------+
| PVC                         |
|-----------------------------|
| storageClassName: ebs-gp3   |
| storage: 30Gi               |
+-----------------------------+

                │
                ▼

AWS EBS CSI Driver
                │
                ▼

Creates AWS EBS
                │
                ▼

Creates PV
                │
                ▼

PVC Binds to PV
                │
                ▼

Pod Mounts Storage
                │
                ▼

Application writes files
