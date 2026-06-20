# Kubernetes Priority Classes

This clusters uses Kubernetes `PriorityClass` resources to define workload scheduling priorities.

## Priority Hierarchy

Higher values have higher scheduling priority. Workloads with `preemptionPolicy: PreemptLowerPriority` may evict lower-priority workloads when required.

| Priority Class | Value | Preemption Policy | Purpose |
| -------------- | ----- | ----------------- | ------- |
| `system-node-critical` | `2000001000` | `PreemptLowerPriority` | Kubernetes node-level critical components. |
| `system-cluster-critical` | `2000000000` | `PreemptLowerPriority` | Kubernetes cluster-level critical components. |
| `storage-critical` | `1000000000` | `PreemptLowerPriority` | Storage components required for persistent volume management. |
| `gitops-critical` | `900000` | `PreemptLowerPriority` | GitOps components required to manage cluster state. |
| `platform-critical` | `900000` | `PreemptLowerPriority` | Infrastructure controllers and operators required by workloads. |
| `data-critical` | `700000` | `PreemptLowerPriority` | Stateful data services such as databases and caches. |
| `observability-critical` | `700000` | `Never` | Monitoring and observability components. |
| `backup-critical` | `500000` | `Never` | Backup workloads required for disaster recovery. |
| `application-critical` | `200000` | `Never` | Important user-facing applications. |
| `application-default` | `100000` | `Never` | Default priority for application workloads. |
| `batch-low` | `1000` | `Never` | Non-critical batch workloads and maintenance jobs. |

---

## Component Assignment

### System Components

Managed by Kubernetes and should use the built-in critical classes.

| Priority Class | Components |
| -------------- | ---------- |
| `system-node-critical` | Kubernetes Control Plane components and Cilium agents (`cilium`, `cilium-envoy`) |
| `system-cluster-critical` | CoreDNS, Cilium operator, metrics-server |

## Storage

| Priority Class | Components |
| -------------- | ---------- |
| `storage-critical` | Longhorn, OpenEBS |

Storage components receive a high priority because applications depend on persistent volume availability.

## GitOps

| Priority Class | Components |
| -------------- | ---------- |
| `gitops-critical` | ArgoCD components |

ArgoCD is responsible for maintaining the desired cluster state and should remain available during resource pressure.

## Platform Controllers

| Priority Class | Components |
| -------------- | ---------- |
| `platform-critical` | External Secrets Operator, Cert-Manager, CNPG operator and Barman Cloud plugin, Redis operator, External-Dns, Reloader, Cloudflared |

These components provide services but are not themselves application workloads.

## Data Services

| Priority Class | Components |
| -------------- | ---------- |
| `data-critical` | CloudNativePG database clusters, Redis instances |

Database and cache workloads receive elevated priority because they hold application state.

## Observability

| Priority Class | Components |
| -------------- | ---------- |
| `observability-critical` | Prometheus, Alertmanager, Grafana and other observability tools |

Monitoring should remain available but should not preempt core platform or data services.

## Applications

| Priority Class | Components |
| -------------- | ---------- |
| `application-critical` | Important user applications such as Vaultwarden, FireflyIII, etc |
| `application-default` | Default priority for standard user applications |

Applications that require explicit importance should define their own PriorityClass. All other applications inherit `application-default`.

## Batch Workloads

| Priority Class | Components |
| -------------- | ---------- |
| `batch-low` | Renovate jobs, cleanup jobs, maintenance jobs, non-critical CronJobs |

Batch workloads should run when resources are available and should not impact long-running services.