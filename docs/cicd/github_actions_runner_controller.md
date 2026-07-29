# GitHub Actions Runner Controller (ARC)

This cluster uses [**GitHub Actions Runner Controller (ARC)**](https://github.com/actions/actions-runner-controller/tree/master) to provide
self-hosted GitHub Actions runners on Kubernetes.

The setup is designed around **ephemeral runners with scale-to-zero
autoscaling**:

  * The ARC controller runs continuously in the `arc` namespace.
  * Runner pods run in the `arc-runners` namespace **only**.
  * Runners are provisioned when GitHub Actions jobs require them and are removed when no longer needed.
  * The current runner scale set is dedicated to this repository, with the intention of adding additional scale sets for other repositories in the future.
  * ARC metrics are exposed and monitored, with alerts configured for runner provisioning, job execution, and resource-related issues.
  * Controller and Runner workloads are hardened using Kubernetes security contexts and `CiliumNetworkPolicies`, restricting container privileges and controlling network access to the resources required.


## Table of Contents

- [GitHub Actions Runner Controller (ARC)](#github-actions-runner-controller-arc)
  - [Table of Contents](#table-of-contents)
  - [Architecture](#architecture)
  - [ARC Controller](#arc-controller)
    - [Configuration](#configuration)
  - [Runner Scale Set](#runner-scale-set)
    - [Scaling](#scaling)
    - [Runner Labels](#runner-labels)
  - [Adding Runner Scale Sets](#adding-runner-scale-sets)
  - [Monitoring](#monitoring)
    - [Alerts](#alerts)
  - [Scheduling (Priority Classes)](#scheduling-priority-classes)
  - [Resources](#resources)

## Architecture

The deployment is split into two parts:

``` text
                         GitHub Actions
                               |
                               | jobs
                               v
                    +----------------------+
                    |   ARC Controller     |
                    |      namespace: arc  |
                    +----------+-----------+
                               |
                     provisions runners
                               |
                               v
                    +----------------------+
                    |   Runner Scale Set    |
                    | namespace: arc-runners|
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    | Ephemeral Runner Pod  |
                    |                      |
                    |  actions-runner      |
                    |  Docker-in-Docker    |
                    +----------------------+
```

The controller is responsible for reconciling the runner scale set and
communicating with GitHub. The runner pods execute the actual GitHub
Actions jobs.

The separation between `arc` and `arc-runners` namespaces is intentional:

-   `arc` contains the long-running ARC controller.
-   `arc-runners` contains ephemeral workload pods.

## ARC Controller

The ARC controller is deployed in the `arc` namespace.

The controller uses:

-   A dedicated service account named `arc-controller-sa`.
-   A dedicated priority class of `gitops-critical`.
-   Namespace-scoped watching of `arc-runners`.
-   Prometheus metrics on port `8080`.

### Configuration

The controller Helm values are defined in
[`values.yaml`](../../infrastructure/controllers/arc/controller/values.yaml).

The controller is deliberately limited to watching the runner namespace:

``` yaml
flags:
  watchSingleNamespace: "arc-runners"
```

Therefore all `autoscalingrunnersets` need to be deployed in the watched namespace for the controller to reconcile it.
This reduces the controller's scope and avoids watching unrelated namespaces.

The controller also limits concurrent runner reconciliations:

``` yaml
flags:
  runnerMaxConcurrentReconciles: 2
```

## Runner Scale Set

This section describes the runner scale set configured for this repository only. Other repositories can have their own dedicated runner scale sets, which are added independently as described in [Adding Runner Scale Sets](#adding-runner-scale-sets).

The current runner scale set is defined in [`values.yaml`](../../infrastructure/controllers/arc/runners/k8s-gitops/values.yaml).

It configures self-hosted runners only for this repository:

```yaml
githubConfigUrl: "https://github.com/Tiagura/k8s-gitops"
```

The runner scale set is named:

```yaml
runnerScaleSetName: arc-runner
```

### Scaling

The runner scale set uses:

``` yaml
minRunners: 0
maxRunners: 2
```

This is an intentional **scale-to-zero** configuration.

When there are no GitHub Actions jobs there are 0 runners.
When jobs appear, ARC provisions runners up to 2 runners.
This helps prevent waste of resources when there are no jobs for runners to execute.

### Runner Labels

The runner scale set registers runners with:

``` yaml
scaleSetLabels:
  - self-hosted
  - linux
  - x64
```

GitHub Actions workflows can target these runners using:

``` yaml
runs-on: [self-hosted, linux, x64]
```

## Adding Runner Scale Sets

Additional repositories can have their own dedicated ARC runner scale sets.

To add a runner scale set for another repository, create a new directory under: `infrastructure/controllers/arc/runners/`

The directory should contain the Kustomize configuration and the Helm values for that runner scale set.

For example:

```text
infrastructure/
└── controllers/
    └── arc/
        └── runners/
            ├── kustomization.yaml
            ├── repository-a/
            │   ├── kustomization.yaml
            │   └── values.yaml
            │
            └── repository-b/
                ├── kustomization.yaml
                └── values.yaml
```

Each runner scale set should have its own:

1. `kustomization.yaml` — defines the Helm release and resources for the runner scale set.
2. `values.yaml` — configures the runner scale set, including the target GitHub repository, runner scale set name, autoscaling limits, resources, security settings, and network policy labels.

The `values.yaml` should then point the runner scale set at the appropriate GitHub repository using `githubConfigUrl` and give it a unique `runnerScaleSetName`.

The existing ARC controller is configured to watch the `arc-runners` namespace, so all runner scale sets should continue to be deployed there unless the controller configuration is intentionally changed.

This means adding another repository does **not** require changing the ARC controller. Simply add the new runner directory and include it in the appropriate Kustomize configuration so Argo CD deploys it.

## Monitoring

ARC metrics are disabled by default and are explicitly enabled in the controller Helm values:

```yaml
metrics:
  controllerManagerAddr: ":8080"
  listenerAddr: ":8080"
  listenerEndpoint: "/metrics"
```

This exposes Prometheus-compatible metrics from the controller-manager and listener on port `8080` at the `/metrics` endpoint. The metrics are then scraped by the Prometheus Operator using a `PodMonitor` defined in [`arc-controller-monitor.yaml`](../../monitoring/prometheus-stack/monitors/pods/arc-controller-monitor.yaml).

### Alerts

ARC alerts are defined in [`arc-alerts.yaml`](../../monitoring/prometheus-stack/alerts/arc-alerts.yaml).

The alerts focus on runner provisioning latency, job execution duration, and runner resource issues. Zero runners is considered normal because the runner scale sets use scale-to-zero autoscaling.

| **Alert Name**                      | **Severity** | **Description**                                                                           |
| ----------------------------------- | ------------ | ----------------------------------------------------------------------------------------- |
| **ARCJobStartupLatencyHigh**        | Warning      | Triggers when p95 job startup latency remains above 5 minutes for 20 minutes.             |
| **ARCJobStartupLatencyCritical**    | Critical     | Triggers when p95 job startup latency remains above 5 minutes for 30 minutes.             |
| **ARCJobExecutionDurationHigh**     | Warning      | Triggers when average job execution duration remains above 30 minutes for 15 minutes.     |
| **ARCJobExecutionDurationCritical** | Critical     | Triggers when average job execution duration remains above 60 minutes for 15 minutes.     |
| **ARCJobsNotStarting**              | Critical     | Triggers when jobs are assigned but no jobs have started for 10 minutes.                  |
| **ARCControllerMetricsMissing**     | Critical     | Triggers when ARC controller metrics have been absent for 10 minutes.                     |
| **ARCRunnerContainerOOMKilled**     | Critical     | Triggers when an ARC runner container has a recent restart caused by an OOM kill.        |
| **ARCRunnerHighCPU**                | Warning      | Triggers when an ARC runner container uses more than 90% of its CPU limit for 3 minutes.  |

## Scheduling (Priority Classes)

The ARC controller and runner pods use different Kubernetes `PriorityClass` values to reflect their different roles in the system.

The **ARC controller** uses the higher-priority `gitops-critical` class. The controller needs to remain available so it can communicate with GitHub and detect new jobs, provision runners, and reconcile the runner scale sets. If the controller is evicted or unable to run, new GitHub Actions jobs cannot be picked up.

The **runner pods** use a lowest-priority class, `batch-low`. If a runner cannot be scheduled due to resource pressure, the GitHub Actions job simply remains pending until a runner becomes available. While this means the affected pipeline may be delayed, it is preferable to evict or prevent other critical workloads from running just to make room for an ephemeral CI runner.

This prioritizes the availability of the **cluster infrastructure and other workloads** over the execution speed of individual CI jobs. Runner workloads are therefore treated as lowest-priority, rather than workloads that should displace other applications when cluster resources are constrained.


## Resources

-   [GitHub Actions Runner Controller documentation](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller)
-   [Deploy and configure runner scale sets](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/deploy-runner-scale-sets)
-   [ARC metrics](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/deploy-runner-scale-sets#enabling-metrics)
-   [Authenticate ARC to the GitHub API](https://docs.github.com/en/actions/how-tos/manage-runners/use-actions-runner-controller/authenticate-to-the-api)