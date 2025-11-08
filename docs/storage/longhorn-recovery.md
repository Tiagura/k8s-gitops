# Longhorn Disaster Recovery Guide

## Table of contents

- [Longhorn Disaster Recovery Guide](#longhorn-disaster-recovery-guide)
  - [Table of contents](#table-of-contents)
  - [Overview](#overview)
  - [Prerequisites](#prerequisites)
  - [Snapshot Management](#snapshot-management)
    - [Manual Snapshot](#manual-snapshot)
    - [Snapshot Operations](#snapshot-operations)
  - [Backup Management](#backup-management)
    - [Manual Backup](#manual-backup)
    - [Backup Operations](#backup-operations)
  - [Disaster Recovery](#disaster-recovery)
    - [Single Volume Recovery](#single-volume-recovery)
    - [Full Cluster Recovery (RIP)](#full-cluster-recovery-rip)
  - [Monitoring \& Alerts](#monitoring--alerts)
    - [Snapshot and Backup System Monitoring](#snapshot-and-backup-system-monitoring)
    - [Prometheus Metrics](#prometheus-metrics)
    - [Alert Rules](#alert-rules)
  - [Resources](#resources)

## Overview

The Longhorn disaster recovery and backup strategy is designed to provide multi-tiered data protection, retention and recovery based on data importance.

Backups are stored in the configured Longhorn Default Backup Target. 

The data is organized into **three main tiers**. Each tier uses recurring snapshot jobs for fast, local recovery and recurring backup jobs for durable, off-cluster disaster recovery. The definition of the snapshot and backup jobs can be seen in [`recurring-snapshot-jobs.yaml`](../../infrastructure/storage/longhorn/recurring-snapshot-jobs.yaml) and [`recurring-backup-jobs.yaml`](recurring-backup-jobs.yaml), accordingly.

Remember that the recurring snapshots and backups jobs are only for PV/PVC using the default storage class `longhorn`.

## Prerequisites

- **Configured default backup target**: This target defines where all recurring backup jobs will be stored. Longhorn supports multiple types of backup destinations, including: NFS, SMB/CIFS, Azure Blob Storage and S3 Object Storage.
  > Saving to **S3-compatible** object storage is preferable. There are various solutions: self-hosted like Garage or MinIO, as well as cloud providers such as AWS S3 and others.

- **Volume Grouping**: To include a volume in Longhorn’s recurring snapshot or backup jobs, you can either
  - Option 1 - Label the PVC (recommended)
    ```yaml
    labels:
      recurring-job.longhorn.io/source: enabled
      recurring-job-group.longhorn.io/<standard | important | critical>: enabled
    ```
  - Option 2 - Label the Longhorn Volume directly. Apply the same labels as option 1.

  > **Note**: By default all volumes belong to the default group - which, by design, is not configured.
  To include a default snapshot and/or backup behaviour, you can either: 1. add the "default" group to the existing standard jobs (`groups: ["standard"]` → `groups: ["standard", "default"]`) 2. Create a dedicated recurring job specifically for the default group.

  > **Note**: By default all volumes belong to the default group. If the default group is configured and another group is assigned to a PV/PVC (for example, `recurring-job-group.longhorn.io/standard: enabled`), the recurring job groups will stack, causing snapshot and backup duplication. To prevent this behavior, explicitly disable the default group by adding the following label to the PV/PVC:
    ```yaml
    labels:
      recurring-job-group.longhorn.io/default: disabled
    ```

## Snapshot Management

### Manual Snapshot

Besides automatic snapshots, these can also be made manually.

```bash
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: <snapshot-name>
  namespace: <volume-ns>
  labels:
    longhornvolume: <volume-name> 
    snapshot-type: manual
spec:
  volume: <volume-name>
  createSnapshot: true
EOF
```

### Snapshot Operations

```bash
# List snapshots for a volume
kubectl get snapshots -n longhorn -l longhornvolume=<volume-name>

# Delete specific snapshot
kubectl delete snapshot <snapshot-name> -n longhorn

# Restore from snapshot (carefull it creates a new volume)
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: restored-<volume-name>
  namespace: longhorn
spec:
  fromSnapshot: <snapshot-name>
  numberOfReplicas: <>
  size: "<>"
EOF
```

## Backup Management

### Manual Backup

Besides automatic backups, these can also be made manually.

```bash
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Backup
metadata:
  name: backup-<volume-name>
  namespace: longhorn
  labels:
    longhornvolume: <volume-name>
    backup-type: manual
spec:
  backupMode: [full|incremental]    # If using manually better to make a full backup
  snapshotName: <snapshot-name>
  labels:
    longhornvolume: <volume-name>
    backup-type: manual
EOF
```

### Backup Operations

```bash
# List backups for volume
kubectl get backups -n longhorn -l longhornvolume=<volume-name>

# Delete specific backup
kubectl delete backup <backup-name> -n longhorn

# Verify backup integrity
kubectl describe backup <backup-name> -n longhorn

# Restore from backup (carefull it creates a new volume)
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Volume
metadata:
  name: <volume-name>
  namespace: longhorn
  labels:
    original-volume: <volume-name>
spec:
  fromBackup: <url>     # Find it with kubectl -n longhorn get backup <backup-name> -o yaml | grep url
  numberOfReplicas: 2
  frontend: blockdev    # Other options are "iscsi", "nvmf", "ublk", ""
EOF
```

## Disaster Recovery

### Single Volume Recovery

1. Scale down the Deployment/StatefullSet/Others:
    ```bash
    kubectl scale <resource>/<resource-name> --replicas=0 -n <namespace>
    ```
    > **Note**: If ArgoCD is running you must scale down the replicas to 0 in the yaml file and remove the creation of the pv/pvc and then commit the changes.
2. Wait for Volume to detach:
    ```bash
    kubectl get volumes -n longhorn -w
    # OR
    kubectl get volume <volume-name> -n longhorn -w
    ``` 
3. Find the volume name:
    ```bash
    # Find the volume name (format: pvc-<uuid>)
    kubectl get pv | grep <namespace>/<pvc-name>
    ``` 
4. Delete old Volume:
   - Via Longhorn GUI:
     1. Navigate to Longhorn UI → Volumes
     2. Find and delete the specified volume
     3. Confirm deletion 
   - Via CLI:
      ```bash
      kubectl delete volume <volume-name> -n longhorn
      ``` 
5. Restore Backup to new Volume:
   - Via Longhorn GUI:
     1. Go to Backup → Select backup to restore
     2. Assign the new volume the exact name from step 3
     3. Start restore process
   - Via CLI:
     Use [Restore from backup command](#backup-operations/) and adapt it
6. Wait for restore process to complete:
    ```bash
    kubectl get volumes -n longhorn -w
    # OR
    kubectl get volume <volume-name> -n longhorn -w
    ``` 
7. Create PV/PVC:
   - Via Longhorn GUI (Recommended):
     1. Navigate to Longhorn UI → Volume → Operations → Create PV/PVC
     2. Ensure "Create PVC" option is checked
     3. Ensure "Use Previous PVC" option is checked
   - Via CLI (Untested):
     1. Create the PV pointing to the restored Longhorn volume. Base it on the app's PersistentVolumeClaim file.
        ```yaml
        kubectl apply -f - <<EOF
        apiVersion: v1
        kind: PersistentVolume
        metadata:
          name: <pv-name>
        spec:
          capacity:
            storage: <>       # Storage must be =< than the restored volume size
          accessModes:
            - <>              # Depends on your app
          storageClassName: longhorn
          csi:
            driver: driver.longhorn.io
            fsType: ext4      # Defined in the values file persistence.defaultFsType
            volumeHandle: <volume-name>
        EOF
        ```
     2. Create the PVC for the restored Longhorn volume. Base it on the app's PersistentVolumeClaim file.
        ```yaml
        kubectl apply -f - <<EOF
        apiVersion: v1
        kind: PersistentVolumeClaim
        metadata:
          name: <pvc-name>
          namespace: <pvc-namespace>
        spec:
          accessModes:
            - <>            # Must match the mode in the created PV
          resources:
            requests:
              storage: <>   # Storage must be =< than the restored volume size;
          storageClassName: longhorn
          volumeName: <pv-name>
        EOF
        ```
8.  Wait for PV/PVC to be available:
    ```bash
    # Verify PVC is bound to the restored volume
    kubectl get pvc -n longhorn
    # OR
    kubectl get pv | grep <pvc-name>
    ``` 
9.  Scale up the resource:
    ```bash
    kubectl scale <resource>/<resource-name> --replicas=<n> -n <namespace>
    ``` 
    > **Note**: If ArgoCD is running undo the git changes made in step 1.

### Full Cluster Recovery (RIP)

To find out

## Monitoring & Alerts

### Snapshot and Backup System Monitoring

```bash
# Check snapshot and backup system status
kubectl get settings -n longhorn | grep -E "backup|snapshot"

# Monitor recent snapshot jobs
kubectl get snapshots -n longhorn --sort-by=.metadata.creationTimestamp

# Monitor recent backup jobs
kubectl get backups -n longhorn --sort-by=.metadata.creationTimestamp

# Check recurring job status
kubectl get recurringjobs -n longhorn
```

### Prometheus Metrics

Metrics usefull to monitor for snapshots and backups:

- `longhorn_backup_state` - Backup job states
- `longhorn_snapshot_actual_size_bytes` - Snapshot sizes
- `longhorn_volume_actual_size_bytes` - Volume utilization
- `longhorn_backup_progress` - Backup progress

### Alert Rules

The configured alerts (defined in the [`storage-backup-alerts.yaml`](../../monitoring/prometheus-stack/alerts/storage-backup-alerts.yaml)) continuously monitor the health and capacity of the Longhorn storage system to ensure data reliability and cluster stability.

| **Alert Name**                    | **Trigger Condition**                                      | **Severity** | **Description**                                                                                                                                      |
| --------------------------------- | ---------------------------------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **LonghornBackupFailed**          | `longhorn_backup_state == 3 or longhorn_backup_state == 4` | Critical     | Fires when a backup enters an *Error* (3) or *Unknown* (4) state, indicating that the backup operation failed or could not be verified.              |
| **LonghornBackupStuckInProgress** | `longhorn_backup_state == 1` for more than **3 hours**      | Warning      | Triggers when a backup remains *InProgress* for an unusually long period, which may indicate issues with the backup process or storage connectivity. |


## Resources

- [Recurring Snapshots and Backups](https://longhorn.io/docs/latest/snapshots-and-backups/scheduling-backups-and-snapshots/)
- [Setting a Backup Target](https://longhorn.io/docs/latest/snapshots-and-backups/backup-and-restore/set-backup-target/)
- [Create a Backup](https://longhorn.io/docs/latest/snapshots-and-backups/backup-and-restore/create-a-backup/)
- [Create a Snapshot](https://longhorn.io/docs/latest/snapshots-and-backups/setup-a-snapshot/)
- [Single Volume Restore Community](https://medium.com/@mahdad.ghasemian/restoring-data-using-longhorn-528c33535915)