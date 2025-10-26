# Longhorn Configuration

## Table of contents

- [Longhorn Configuration](#longhorn-configuration)
  - [Table of contents](#table-of-contents)
  - [Declarative Setup](#declarative-setup)
  - [Directory Structure](#directory-structure)
  - [Default Settings](#default-settings)
  - [Storage Classes](#storage-classes)
    - [`longhorn` (default)](#longhorn-default)
    - [`cnpg-longhorn-storage`](#cnpg-longhorn-storage)
  - [Snapshots and Backups](#snapshots-and-backups)
  - [Monitoring \& Alerts](#monitoring--alerts)
    - [Alerts](#alerts)
  - [Resources](#resources)

## Declarative Setup
All longhorn components described in this document — **Storage Classes**, **Snapshots and Backups**, **Settings** — are deployed declaratively through the infrastructure ApplicationSet. No manual helm or kubectl commands are required.
Their manifests are stored under infrastructure/storage/longhorn and are automatically synchronized by Argo CD to maintain a consistent and version-controlled network configuration.

## Directory Structure

```plaintext
infrastructure/storage/longhorn/
├── backup-settings.yaml                    # Backup Settings
├── cnpg-longhorn-storage.yaml              # Cloudnative-pg exclusive StorageClass
├── http-route.yaml                         # Route for Longhorn GUI
├── kustomization.yaml                      
├── namespace.yaml
├── recurring-backup-jobs.yaml              # Backup Data Tiers Configuration
├── recurring-snapshot-jobs.yaml            # Snapshots Data Tiers Configuration
├── s3-remote-backup-secret-sealed.yaml     # Secret for S3 Remote Storage Access
└── values.yaml                             # Values file for helm                     
```

## Default Settings

Longhorn configuration can be observed in the [`values.yaml`](../../infrastructure/storage/longhorn/values.yaml) and [`backup-settings.yaml`](../../infrastructure/storage/longhorn/backup-settings.yaml) files.

## Storage Classes

### `longhorn` (default)
Used for general workloads with 2 replicas and recurring snapshot/backup schedules. Generated from the longhorn helm chart. Obtain the full storage class configuration using:
```bash
kubectl describe storageclass longhorn
```

### `cnpg-longhorn-storage`
Specialized storage class used **exclusively by CloudNativePG** replicas.

Unlike regular workloads that rely on Longhorn’s own snapshot and backup automation, databases managed by CloudNativePG already implement **native replication and backup management**. To avoid overlapping or redundant data protection mechanisms, this storage class is configured to disable all Longhorn recurring jobs (snapshots and backups) and to **accomodate cloudnative-pg** needs.

Some Key Configurations:
- Non-default class – Explicitly used only by CloudNativePG, not general workloads.
- `numberOfReplicas` = `1` : Prevents redundant replication since CloudNativePG already replicates data at the database level.
- `dataLocality` = `strict-local` : Ensures the volume is placed on the same node as the PostgreSQL pod for lower latency.
- `recurringJobSelector` = `'[]'` – Disables Longhorn’s automatic snapshots/backups. CloudNativePG manages its own backup and restore processes.

## Snapshots and Backups

The backup and snapshot strategy is organized into three data tiers, each defining its own frequency and retention policy to match data. These tiers — critical, important, and standard — determine how often volumes are snapshotted and backed up to ensure the right balance between recovery speed and storage efficiency.
The configurations for these recurring jobs are defined in[`recurring-snapshot-jobs.yaml`](../../infrastructure/storage/longhorn/recurring-snapshot-jobs.yaml) and [`recurring-backup-jobs.yaml`](recurring-backup-jobs.yaml).

| Tier          | Snapshot Frequency | Snapshot Retention | Backup Frequency      | Backup Retention | Groups      |
| ------------- | ------------------ | ------------------ | --------------------- | ---------------- | ----------- |
| **Critical**  | Every 3 hours      | 8 (≈1 day)         | Daily @ 04:00         | 30 (≈1 month)    | `critical`  |
| **Important** | Every 6 hours      | 16 (≈2 days)       | Every 3 days @ 05:00  | 10 (≈1 month)    | `important` |
| **Standard**  | Daily @ 06:00      | 7 (≈1 week)        | Weekly @ Sunday 06:00 | 8 (≈2 months)    | `standard`  |
| **Default**   | -                  | -                  | -                     | -                | `default`   |


By default, Longhorn includes a default group that applies to volumes not explicitly assigned to any data tier.
In this setup, the default group has no recurring jobs configured, meaning such volumes will not have automatic snapshots or backups.
However, snapshot and backup policies can easily be added for the default group if desired, allowing it to follow a defined protection schedule.

## Monitoring & Alerts

### Alerts

The configured alerts (defined in the [`storage-alerts.yaml`](../../monitoring/prometheus-stack/alerts/storage-alerts.yaml)) continuously monitor the health and capacity of the Longhorn storage system to ensure data reliability and cluster stability.

| **Alert Name**                  | **Severity** | **Description**                                                                                                                                          |
| ------------------------------- | ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **LonghornNodeDown**            | Critical     | Triggers when one or more Longhorn nodes are offline for more than 10 minutes, indicating potential node or network failures.                            |
| **LonghornVolumeUnhealthy**     | Critical     | Fires when a volume’s robustness status changes from `Healthy` to `Degraded`, `Faulted`, or `Unknown`, signaling data redundancy or availability issues. |
| **LonghornNodeStorageSpaceLow** | Warning      | Alerts when a Longhorn node’s storage usage exceeds 90% capacity, allowing proactive management before disks run out of space.                           |




## Resources 

- [Longhorn Best Practices](https://longhorn.io/docs/1.10.0/best-practices/)
- [Block Storage Considerations ](https://cloudnative-pg.io/documentation/1.27/storage/#block-storage-considerations-cephlonghorn)
- [Cloudnative-pg + Longhorn Community](https://medium.com/@camphul/cloudnative-pg-in-the-homelab-with-longhorn-b08c40b85384)
- [Longhorn Metrics for Monitoring](https://longhorn.io/docs/1.10.0/monitoring/metrics/)
- [Setting up Prometheus and Grafana to monitor Longhorn](https://longhorn.io/docs/1.10.0/monitoring/prometheus-and-grafana-setup/)