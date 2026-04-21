# OpenEBS Configuration

## Overview

This setup uses [OpenEBS Local PV (hostpath)](https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-hostpath/hostpath-overview) to provide simple, node-local storage for stateful workloads.

Instead of relying on distributed storage systems, volumes are created directly on the node filesystem. This keeps things lightweight and avoids unnecessary abstraction, which is especially useful for databases where replication and durability are already handled at the application level.

## Table of Contents

- [OpenEBS Configuration](#longhorn-configuration)
  - [Overview](#overview)
  - [Table of contents](#table-of-contents)
  - [Declarative Setup](#declarative-setup)
  - [Directory Structure](#directory-structure)
  - [Configuration](#configuration)
  - [Storage Class](#storage-class)
  - [Design Choices](#design-choices)
  - [Operational Notes](#operational-notes)
  - [Resources](#resources)

## Declarative Setup
OpenEBS is deployed declaratively through its respective [ArgoCD application](../../infrastructure/controllers/argocd/apps/longhorn-app.yaml). No manual Helm or kubectl commands are required.
All manifest live under `infrastructure/storage/openebs/` and are automatically synced by Argo CD.

## Directory Structure

```plaintext
infrastructure/storage/openebs/
├── kustomization.yaml
├── namespace.yaml
└── values.yaml                  
```

## Configuration

The configuration is intentionally minimal and can be found in [values.yaml](../../infrastructure/storage/openebs/values.yaml). Only the Local PV hostpath provisioner is enabled. All other engines and features are explicitly disabled.

## Storage Class

The setup produces a single storage class `openebs-hostpath`, which is not the default storage class and should not be used as one.

## Design Choices

This setup is intentionally simple. OpenEBS is used only as a dynamic provisioner for local storage, not as a full storage platform.

There is:
- no replication at the storage layer
- no snapshot or backup automation
- no distributed volume management

## Operational Notes
- The base path (`localpv-provisioner.hostpathClass.basePath`) must exist on all nodes
- Data is tied to the node where the volume is created
- Node failure means data loss unless handled at the application level
- OpenEBS Local PV exposes very limited metrics, so monitoring should be focused on the workloads using the storage.
- Best suited for:
  - databases with built-in replication (e.g. CNPG)
  - applications with built-in monitoring and observability 
  - non-critical stateful workloads

## Resources

- [OpenEBS Docs](https://openebs.io/docs)
- [Local PV Hostpath](https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-hostpath/hostpath-overview)