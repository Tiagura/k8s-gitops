# ArgoCD & GitOps

This cluster is managed entirely through **Argo CD** using **GitOps**.
This document describes the **App-of-Apps architecture** used here, which enables the cluster to fully manage itself from the definitions stored in this repository.

## Table of Contents

- [ArgoCD \& GitOps](#argocd--gitops)
  - [Table of Contents](#table-of-contents)
  - [App of Apps Pattern](#app-of-apps-pattern)
    - [Apps and AplicationSets](#apps-and-aplicationsets)
  - [Dependency Management with Sycn Waves](#dependency-management-with-sycn-waves)
    - [How to Declare a Sync-Wave](#how-to-declare-a-sync-wave)
  - [Health Check Customization for App-of-Apps Pattern](#health-check-customization-for-app-of-apps-pattern)
  - [Initial Bootstrapp and Self-Management Loop](#initial-bootstrapp-and-self-management-loop)
  - [Resources](#resources)

## App of Apps Pattern

A [single root application](../infrastructure/controllers/argocd/root.yaml) serves as the entrypoint for the cluster. It points to the Applications and ApplicationSets defined in `infrastructure/controllers/argocd/apps/`, which are then discovered and deployed to assemble the rest of the cluster automatically.

### Apps and AplicationSets

There are three main ApplicationSets in this repository:
- [`infrastructure-applicationset.yaml`](infrastructure/controllers/argocd/apps/infrastructure-applicationset.yaml): Core system components, including CNI, Secret Management, Certificates, and other essential services.
- [`monitoring-applicationset.yaml`](infrastructure/controllers/argocd/apps/monitoring-applicationset.yaml): The monitoring stack for the cluster.
- [`user-apps-applicationset.yaml`](infrastructure/controllers/argocd/apps/user-apps-applicationset.yaml): User-facing applications and workloads.

Although the `infrastructure-applicationset.yaml` is intended to include all core system components, this is not the case. Some components are separated into solo applications due to interdependencies, which are explained in more detail in the following section.

## Dependency Management with Sycn Waves

Many resources in the cluster depend on others to function correctly, creating a dependency challenge. For example, the cluster’s CNI must be deployed first to ensure pod-to-pod connectivity, and secrets need to exist before workloads can access configuration data.

To address this, Argo CD **sync-waves** are used to enforce an explicit deployment order, ensuring that dependent resources are applied only after their prerequisites are ready.

| Wave  | Layer               | Components                                                       |  Description |
| ----- | ------------------- | -----------------------------------------------------------------|--------------|
| **0** | Core Foundations          | [`cilium`](../infrastructure/networking/cilium/), [`sealed-secrets`](../infrastructure/controllers/sealed-secrets/) | Provides baseline networking and secret management required before any higher-level infrastructure can function. |
| **1** | Storage Services          | [`longhorn`](../infrastructure/storage/longhorn/)               | Delivers the persistent storage layer needed by controllers and applications that rely on PVCs. |
| **2** | GitOps and Ingress        | [`argocd`](../infrastructure/controllers/argocd/), [`cert-manager`](../infrastructure/controllers/cert-manager/), [`gateway`](../infrastructure/networking/gateway-api/) | GitOps orchestration, certificate automation, and cluster ingress/routing components. |
| **3** | System & Monitoring | Rest of infrastructure (manifests in [`infrastructure/*`](../infrastructure/)) and Monitoring stack (manifests in [`monitoring/*`](../monitoring/)) | Core system services and observability components.                                   |
| **4** | User Apps           | User Applications (manifests under [`user-apps/*`](../user-apps/)) | All user-facing applications that rely on the underlying infrastructure being available.|

### How to Declare a Sync-Wave
In ArgoCD, sync-waves are declared using the annotation:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "<wave-number>"
```
- `<wave-number>` is an integer indicating the deployment order.
- Lower numbers are deployed first, higher numbers later.
- Resources with the same wave number are deployed in parallel.

Each `Application` resource in `infrastructure/controllers/argocd/apps/` is annotated with its corresponding sync-wave to enforce this order.

## Health Check Customization for App-of-Apps Pattern

When using the App-of-Apps pattern, **custom health checks** are required to make sync-waves work correctly. 

By default, Argo CD marks a parent Application as Healthy as soon as the child Application resource is created, even if the child is still syncing or degraded. This breaks sync-wave ordering. For example, Longhorn (Wave 1) could start deploying before Sealed-Secrets (Wave 0) is ready, causing failures.

To fix this, a custom Lua health check is injected in [ArgoCD's `values.yaml`](../infrastructure/controllers/argocd/values.yaml) file:
```lua
resource.customizations.health.argoproj.io_Application: |
  hs = {}
  hs.status = "Progressing"
  hs.message = ""
  if obj.status ~= nil then
    if obj.status.health ~= nil then
      hs.status = obj.status.health.status
      if obj.status.health.message ~= nil then
        hs.message = obj.status.health.message
      end
    end
  end
  return hs
```

Effects of this customization:
1. It overrides the health assessment of `Application` resources. Making it so that the health of each child `Application` is accurately reflected in the parent (Root) `Application`.
2. Prevents the Root App from marking child `Applications` as healthy prematurely.
3. Keeps the Root App in "Progressing" until all child `Applications` are healthy, regardless of their sync-wave.
4. Maintains correct sync-wave behavior by allowing ArgoCD to advance to the next wave only when all applications in the current wave are healthy.

## Initial Bootstrapp and Self-Management Loop

1. Apply the [`root.yaml`]((../infrastructure/controllers/argocd/root.yaml)) Application to the cluster.
2. Argo CD deploys Wave 0 components and adopts any existing resources on the cluster, such as a running `cilium` instance.
3. Argo CD waits until all Wave 0 applications are healthy.
4. ArgoCD deploys Wave 1, `longhorn`.
5. The process continues until all waves are healthy.
6. Any changes pushed to Git are automatically detected by Argo CD, triggering reconciliation so the cluster continuously aligns with the desired state defined in the repository.

## Resources
- [ArgoCD Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/)
- [ArgoCD Kustomize](https://argo-cd.readthedocs.io/en/latest/user-guide/kustomize/)
- [ArgoCD Helm](https://argo-cd.readthedocs.io/en/latest/user-guide/helm/)
- [ArgoCD Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/#sync-phases-and-waves)
- [ArgoCD Secret Management](https://argo-cd.readthedocs.io/en/latest/operator-manual/secret-management/)
- [ArgoCD FAQ](https://argo-cd.readthedocs.io/en/latest/faq/)
- [Argo CD Application Dependencies Codefresh](https://codefresh.io/blog/argo-cd-application-dependencies/)