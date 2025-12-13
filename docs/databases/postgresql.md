# PostgreSQL

This clusters runs PostgreSQL using the [CloudNativePG](https://cloudnative-pg.io/) operator. Backups and restore are handled using the [Barman Cloud CNPG-I plugin](https://cloudnative-pg.io/plugin-barman-cloud/), which enables continuous WAL archiving and base backups to an object store.

## Table of Contents

- [PostgreSQL](#postgresql)
  - [Table of Contents](#table-of-contents)
  - [Configuration](#configuration)
    - [CNPG](#cnpg)
    - [Barman Cloud Plugin](#barman-cloud-plugin)
  - [Bootstrap](#bootstrap)
  - [Backups](#backups)
    - [Cluster Configuration](#cluster-configuration)
    - [Schedule Backups](#schedule-backups)
  - [Monitoring](#monitoring)
    - [Operator Monitoring](#operator-monitoring)
    - [Cluster Monitoring](#cluster-monitoring)
    - [Plugin / Backup Monitoring](#plugin--backup-monitoring)
  - [PostgreSQL Version Upgrade](#postgresql-version-upgrade)
    - [Minor Upgrade](#minor-upgrade)
    - [Major Upgrade](#major-upgrade)
  - [Some consideration regarding storage class](#some-consideration-regarding-storage-class)
  - [Resources](#resources)

## Configuration

### CNPG
The CloudNativePG operator itself is deployed using the official [Helm chart](https://cloudnative-pg.io/charts/). Since this repository follows a GitOps approach with ArgoCD, a few Helm values must be explicitly set to ensure compatibility and correct reconciliation behavior.

These values are defined in the operator’s [values file](../../infrastructure/databases/cloudnative-pg/cloudnative-pg-operator/values.yaml#L8):

```yaml
config:
  data:
    INHERITED_ANNOTATIONS: "argocd.argoproj.io/sync-wave"
    INHERITED_LABELS: "app.kubernetes.io/managed-by"
```

### Barman Cloud Plugin

Backups and WAL archiving are handled by the Barman Cloud CNPG-I plugin.

To configure it, two resources are required:
  1. A Kubernetes Secret containing: `ACCESS_KEY_ID` ,nd `ACCESS_SECRET_KEY`. These credentials are used by the plugin to authenticate against the configured object storage backend.
  2. An [`ObjectStore`](../../infrastructure/databases/cloudnative-pg/barman-plugin/barmanObjectStore.yaml) resource, which defines the backup destination and retention policy.  

> **Note:**: According to the [docs](https://cloudnative-pg.io/plugin-barman-cloud/docs/retention/), the Barman Cloud plugin currently supports retention only in time, not by number of backups.

## Bootstrap

A PostgreSQL cluster can be bootstrapped in two ways:

1. From scratch:

    Using initdb, the operator creates a new `Cluster` resource from nothing.
    ```yaml
    spec:
      bootstrap:
          initdb:
          database: <db>
          owner: <owner>
          secret:
              name: <secret>
    ```

2. From backup (recovery):

    The cluster can be restored from an **existing backup**, based on the configured backup strategy. This leverages the Barman Cloud plugin and object store–based backups for recovery.
    ```yaml
    spec:
      bootstrap:
        recovery:
          source: source
      externalClusters:
      - name: source
        plugin:
          name: barman-cloud.cloudnative-pg.io
          parameters:
            barmanObjectName: <object-store-name>
            serverName: <original cluster name>
    ```

## Backups

PostgreSQL backups are implemented using [Object Store–based backups](https://cloudnative-pg.io/docs/1.28/backup#object-storebased-backups) trough the [Barman Cloud plugin](https://cloudnative-pg.io/plugin-barman-cloud/docs/usage/#configuring-wal-archiving).

### Cluster Configuration
Each PostgreSQL `Cluster` resource is explicitly configured to use the Barman Cloud plugin as its WAL archiver. This is done via the `plugins` section of the cluster specification:
```yaml
spec:
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: <object-store-name>
```

### Schedule Backups

Backups can be scheduled using the `ScheduledBackup` resource, which allows PostgreSQL base backups to be executed automatically on a defined schedule.
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: <name of backup>
spec:
  cluster:
    name: <target postgresql cluster name>
  immediate: <true|false>       # Wether to trigger immediate backup upon creation or not
  schedule: '0 0 0 * * *'       # GO cron format
  backupOwnerReference: self
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
```

> **NOTE:** Backups can also be triggered on demand. See the [docs](https://cloudnative-pg.io/docs/1.28/backup#on-demand-backups).

## Monitoring

It is possible to monitor all components of this PostgreSQL setup—including the operator, clusters, and plugins using Prometheus and Grafana. All manifests related to monitoring are available in [here](../../monitoring/prometheus-stack/monitors/pods/databases).

### Operator Monitoring

The Helm chart’s built-in `PodMonitor` is deployed in the operator’s namespace, which cannot be scraped by Prometheus in its own namespace. Therefore, we disable automatic PodMonitor creation. However, grafana dashboards from the Helm chart can still be created correctly in the Prometheus stack namespace. So in the operator’s [values file](../../infrastructure/databases/cloudnative-pg/cloudnative-pg-operator/values.yaml):
```yaml
monitoring:
  podMonitorEnabled: false
  grafanaDashboard:
    create: true
    namespace: "prometheus-stack"
    sidecarLabel: ""
    sidecarLabelValue: ""
    labels:
      grafana_dashboard: "1"
```

For monitoring the operator itself, we create a manual `PodMonitor` in the prometheus operator’s namespace:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: cloudnative-pg-operator
  labels:
    app.kubernetes.io/name: cloudnative-pg
    release: kube-prometheus-stack
    prometheus: kube-prometheus-stack-prometheus
spec:
  namespaceSelector:
    matchNames:
      - cloudnative-pg
  podMetricsEndpoints:
    - port: metrics
  selector:
    matchLabels:
      app.kubernetes.io/instance: cloudnative-pg-operator
      app.kubernetes.io/name: cloudnative-pg
```

### Cluster Monitoring

Each PostgreSQL `Cluster` exposes metrics on the metrics port. To collect these, we create a manual `PodMonitor` per cluster:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: <pod monitor>
  labels:
    release: kube-prometheus-stack
    prometheus: kube-prometheus-stack-prometheus
    #...
spec:
  namespaceSelector:
    matchNames:
      - cloudnative-pg  # Namespace where database is deployed
  selector:
    matchLabels:
      cnpg.io/cluster: <cluster name>
      cnpg.io/podRole: instance
  podMetricsEndpoints:
    - port: metrics
```

### Plugin / Backup Monitoring

The Barman Cloud plugin exposes backup-related metrics on the same /metrics endpoint as the `cluster`. These are collected automatically by the cluster’s `PodMonitor`.

## PostgreSQL Version Upgrade

PostgreSQL version upgrades are managed using the mechanisms provided by CloudNativePG. The upgrade strategy depends on whether the upgrade is minor or major.

### Minor Upgrade

Minor version upgrades (example: X.Y → X.Y+1) are handled automatically by CloudNativePG and do not require downtime. CloudNativePG performs a rolling update of the cluster while preserving availability. In practice, minor upgrades only require updating the PostgreSQL image tag used by the cluster.

### Major Upgrade

For major upgrades (example: X → X+1), the strategy used is called offline in-place upgrades. In this setup, all you do is update the cluster’s imageName to the new version and apply the manifest. The CloudNativePG operator then automatically creates a `major_update` job, stops the cluster, performs the upgrade, and restarts it.

This method works well in a homelab where some downtime is acceptable and doesn't require any extra work. Other upgrade strategies exist for production or high-availability environments, see the [CloudNativePG docs](https://cloudnative-pg.io/docs/1.28/postgres_upgrades) for details.

## Some consideration regarding storage class

As described before, in the [longhorn readme.md](../storage/longhorn.md#cnpg-longhorn-storage), a **special** Longhorn storage class is used for PostgreSQL volumes. In the `Cluster` resources, both the main database volume and a dedicated WAL volume use this class:
```yaml
spec:
  storage:
    size: 5Gi
    storageClass: cnpg-longhorn-storage
  walStorage:
    size: 1Gi
    storageClass: cnpg-longhorn-storage
```
The separate WAL volume is required because backups and point-in-time recovery rely on continuous WAL archiving. Using the specialized storage class ensures proper replication and backup handling by CloudNativePG.

## Resources
The CloudNativePG ecosystem is vast and extensively documented. This guide does not cover every feature, so for full details and advanced usage, please refer to the official documentation

- [CloudNativePG Docs](https://cloudnative-pg.io/docs/)
- [Barman Cloud CNPG-I plugin](https://cloudnative-pg.io/plugin-barman-cloud/docs/intro/)
