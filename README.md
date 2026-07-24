# GitOps-Driven Kubernetes Cluster with ArgoCD

This repository contains the configuration and manifests for a **GitOps-driven Kubernetes cluster** managed entirely through **ArgoCD**, built for my homelab using GitOps best practices and patterns.

## Table of Contents

- [GitOps-Driven Kubernetes Cluster with ArgoCD](#gitops-driven-kubernetes-cluster-with-argocd)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Cluster Components and Apps](#cluster-components-and-apps)
    - [Infrastructure](#infrastructure)
      - [CI/CD](#cicd)
      - [Networking](#networking)
      - [Policies and Security](#policies-and-security)
      - [Storage and Databases](#storage-and-databases)
    - [Monitoring](#monitoring)
    - [Applications](#applications)
  - [Prerequisites](#prerequisites)
  - [Bootstrapping the Cluster](#bootstrapping-the-cluster)
    - [1. Install cluster-wide scheduling resources](#1-install-cluster-wide-scheduling-resources)
    - [2. Install Cilium CNI and wait for it to be ready](#2-install-cilium-cni-and-wait-for-it-to-be-ready)
    - [3. Configure External Secrets Operator authentication](#3-configure-external-secrets-operator-authentication)
    - [4. Deploy ArgoCD Main Components and CRDs](#4-deploy-argocd-main-components-and-crds)
    - [5. Bootstrap the GitOps Loop](#5-bootstrap-the-gitops-loop)
    - [6. Optional: Access ArgoCD Web GUI](#6-optional-access-argocd-web-gui)
      - [Get the ArgoCD Initial Admin Password](#get-the-argocd-initial-admin-password)
      - [Access the Web GUI](#access-the-web-gui)
      - [Changing Login Credentials](#changing-login-credentials)
  - [Verification](#verification)
    - [1. Verify Nodes Are Ready](#1-verify-nodes-are-ready)
    - [2. Verify CNI Functionality](#2-verify-cni-functionality)
    - [3. Verify All Pods Are Running](#3-verify-all-pods-are-running)
    - [4. Check That Secrets Have Been Populated](#4-check-that-secrets-have-been-populated)
    - [5. Check ArgoCD Applications Sync Status](#5-check-argocd-applications-sync-status)
  - [Extra Documentation](#extra-documentation)


## Features

- **GitOps-first architecture** powered by Argo CD, using both ApplicationSets and standalone Applications depending on workload needs.
- **Self-managed cluster**, where Argo CD continuously reconciles itself and all platform components.
- **End-to-end CI/CD pipeline**
  - GitHub Actions for CI automation
  - Renovate for automated dependency updates
  - Argo CD for continuous deployment
  - Reloader for live config updates
- **Full observability stack** covering cluster health, applications, and infrastructure with dashboards and alerts.
- **Unified service exposure**  
  - Internal access via home network  
  - External access via **Cloudflare Tunnel**
  - Automatic DNS management via **ExternalDNS**
- **Backup and recovery strategy**
  - Tiered PV/PVC backup strategy for all volumes, with automated snapshots and retention policies
  - Database backups with point-in-time recovery support
- **Network security enforcement** through `CiliumNetworkPolicy`, controlling and isolating service-to-service communication as well as ingress and egress traffic within the cluster.
- **Workload scheduling management** through Kubernetes `PriorityClass` resources, defining workload priorities and preemption policies across system components, infrastructure services, data workloads, and applications.

## Cluster Components and Apps

### Infrastructure

#### CI/CD

| Logo | Name | Purpose |
|------|------|---------|
| <img src="https://argo-cd.readthedocs.io/en/stable/assets/logo.png" width="50"/> | [ArgoCD](https://argo-cd.readthedocs.io/) | GitOps continuous delivery controller |
| <img src="https://avatars.githubusercontent.com/u/44036562?s=200&v=4" width="50"/> | [GitHub Actions](https://docs.github.com/en/actions) | Automated CI workflows |
| <img src="https://digicactus.com/wp-content/uploads/2020/07/1_8Irsw8IlIHORa2eeFh0f0g.png" width="50"/> | [Reloader](https://github.com/stakater/Reloader) | Auto-reloads workloads on ConfigMap/Secret changes |
| <img src="https://docs.renovatebot.com/assets/images/logo.png" width="50"/> | [Renovate](https://docs.renovatebot.com/) | Automated dependency updates |

#### Networking

| Logo | Name | Purpose |
|------|------|---------|
| <img src="https://raw.githubusercontent.com/cilium/cilium/main/Documentation/images/logo-solo.svg" width="50"/> | [Cilium](https://cilium.io/) | Super CNI with advanced networking. Uses eBPF and has observability and security. Also acts as a kube-proxy replacement in this case |
| <img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/cloudflare.svg" width="50"/> | [Cloudflare Tunnel](https://github.com/cloudflare/cloudflared) | External secure access and tunneling |
| <img src="https://kubernetes-sigs.github.io/external-dns/latest/docs/img/external-dns.png" width="50"/> | [External DNS](https://kubernetes-sigs.github.io/external-dns/latest/) | DNS synchronisation and automation |

#### Policies and Security

| Logo | Name | Purpose |
|------|------|---------|
| <img src="https://raw.githubusercontent.com/cert-manager/cert-manager/refs/heads/master/logo/logo-small.png" width="50"/> | [Cert-Manager](https://cert-manager.io/) | Automated TLS certificate management |
| <img src="https://raw.githubusercontent.com/external-secrets/external-secrets/refs/heads/main/assets/eso-round-logo.svg" width="50"/> | [External Secrets](https://github.com/external-secrets/external-secrets) | Syncs secrets from external providers into Kubernetes |

#### Storage and Databases

| Logo | Name | Purpose |
|------|------|---------|
| <img src="https://longhorn.io/img/logos/longhorn-icon-color.png" width="50"/> | [Longhorn](https://longhorn.io/) | Distributed block storage for Kubernetes |
| <img src="https://avatars.githubusercontent.com/u/20769039" width="50"/> | [OpenEBS](https://openebs.io/) | Local PV storage for lightweight, node-level provisioning |
| <img src="https://cloudnative-pg.io/images/hero_image.png" width="50"/> | [CloudNativePG](https://cloudnative-pg.io/) | Operator for managing PostgreSQL clusters, with automated scaling, failover, and backups (with [Barman Cloud plugin](https://cloudnative-pg.io/plugin-barman-cloud/)) |
| <img src="https://raw.githubusercontent.com/OT-CONTAINER-KIT/redis-operator/refs/heads/main/static/redis-operator-logo.svg" width="50"/> | [Redis Operator](https://github.com/OT-CONTAINER-KIT/redis-operator) | Operator for managing Redis |

### Monitoring

| Logo | Name | Purpose |
|------|---------|-------------|
| <img src="https://raw.githubusercontent.com/prometheus/alertmanager/refs/heads/main/ui/app/public/favicon.ico" width="50"/> | [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/) | Manages and routes alerts |
| <img src="https://gotify.net/img/logo.png" width="50"/> | [Gotify](https://gotify.net/) | Push notification server |
| <img src="https://raw.githubusercontent.com/Tiagura/gotigram/refs/heads/main/images/logo_no_background.png" width="50"/> | [Gotigram](https://github.com/Tiagura/gotigram) | Forwards Gotify notifications to Telegram |
| <img src="https://raw.githubusercontent.com/grafana/grafana/main/public/img/grafana_icon.svg" width="50"/> | [Grafana](https://grafana.com/) | Data visualization |
| <img src="https://raw.githubusercontent.com/cilium/hubble-ui/refs/heads/master/src/assets/images/hubble-logo.png" width="50"/> | [Hubble](https://github.com/cilium/hubble) | Networking and security observability (part of [Cilium](https://cilium.io/))|
| <img src="https://raw.githubusercontent.com/prometheus/prometheus/main/documentation/images/prometheus-logo.svg" width="50"/> | [Prometheus](https://prometheus.io/) | Metrics collection and monitoring |


### Applications

| Logo | Name | Purpose |
|------|------|---------|
| <img src="https://raw.githubusercontent.com/alam00000/bentopdf/main/public/images/favicon.svg" width="50"/> | [Bento PDF](https://bentopdf.com/) | PDF Toolkit |
| <img src="https://raw.githubusercontent.com/dgtlmoon/changedetection.io/master/changedetectionio/static/images/generic-icon.svg" width="50"/> | [ChangeDetection](https://changedetection.io/) | Website Monitor |
| <img src="https://raw.githubusercontent.com/excalidraw/excalidraw/refs/heads/master/public/favicon.ico" width="50"/> | [Excalidraw](https://excalidraw.com/) | Whiteboard |
| <img src="https://raw.githubusercontent.com/firefly-iii/firefly-iii/develop/.github/assets/img/logo-small.png" width="50"/> | [Firefly III](https://www.firefly-iii.org/) | Personal Finance Manager |
| <img src="https://raw.githubusercontent.com/gethomepage/homepage/refs/heads/dev/public/android-chrome-192x192.png" width="50"/> | [Homepage](https://gethomepage.dev/) | Dashboard  |
| <img src="https://raw.githubusercontent.com/CorentinTh/it-tools/refs/heads/main/public/android-chrome-192x192.png" width="50"/> | [IT Tools](https://github.com/CorentinTh/it-tools/tree/main) | Developer Tools |
| <img src="https://raw.githubusercontent.com/karakeep-app/karakeep/refs/heads/main/apps/web/app/icon.png" width="50"/> | [Karakeep](https://karakeep.app/) | Bookmark App |
| <img src="https://raw.githubusercontent.com/usememos/memos/refs/heads/main/web/public/logo.webp" width="50"/> | [Memos](https://usememos.com/)| Note Taking |
| <img src="https://raw.githubusercontent.com/technomancer702/nodecast-tv/main/public/favicon.svg" width="50"/> | [NodeCast TV](https://github.com/technomancer702/nodecast-tv) | Web IPTV Player |
| <img src="https://raw.githubusercontent.com/paperless-ngx/paperless-ngx/master/resources/logo/web/svg/square.svg" width="50"/> | [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) | Document Management |
| <img src="https://github.com/schlagmichdoch/PairDrop/raw/master/public/images/android-chrome-512x512.png" width="50"/> | [PairDrop](https://github.com/schlagmichdoch/pairdrop) | Local File Sharing |
| <img src="https://raw.githubusercontent.com/pgadmin-org/pgadmin4/refs/heads/master/docs/en_US/images/logo-128.png" width="50"/> | [pgAdmin](https://github.com/pgadmin-org/pgadmin4) | PostgreSQL Admin Tool |
| <img src="https://raw.githubusercontent.com/Stremio/stremio-brand/refs/heads/master/logos/SVG/stremio-logo-icon-only-fullcolor.svg" width="50"/> | [Stremio](https://www.stremio.com/) | Media Streaming |
| <img src="https://raw.githubusercontent.com/dani-garcia/vaultwarden/refs/heads/main/src/static/images/vaultwarden-icon.png" width="50"/> | [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | Password Manager |


## Prerequisites

Before deploying this setup, make sure you have the following:

1. **A Kubernetes cluster**:
   - Without kube-proxy -> See [Cilium KubeProxy-Free Docs](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
   - Gateway API enabled
     - If Gateway API is **not installed**, run:
        ```bash
        kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
        # OR
        kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/experimental-install.yaml
        ```
   - **Tip:** If you don't already have a Kubernetes cluster but have access to a **Proxmox node/cluster**, you can use my other project, which I also use to create my own cluster: [Tiagura/proxmox-k8s-IaC](https://github.com/Tiagura/proxmox-k8s-IaC)

2. **A domain configured on Cloudflare** (this project can possibly be adapted for use with domains from other providers)

3. **Local CLI tools installed**:
   - [`kubectl`](https://kubernetes.io/docs/tasks/tools/#kubectl)
   - [`kustomize`](https://kubectl.docs.kubernetes.io/installation/kustomize/) (Normally installed when `kubectl` is installed)

## Bootstrapping the Cluster

Follow these steps to bootstrap your Kubernetes cluster with all the necessary components and start the GitOps workflow:

### 1. Install cluster-wide scheduling resources

`PriorityClasses` are cluster-scoped Kubernetes resources used to control pod scheduling priority across the entire cluster. They must exist before any workloads are deployed.

Apply the scheduling resources:

```bash
kubectl kustomize infrastructure/scheduling | kubectl apply -f -
```

### 2. Install Cilium CNI and wait for it to be ready

```bash
kubectl kustomize infrastructure/networking/cilium --enable-helm | kubectl apply -f -

# If cilium CLI installed
cilium status --wait

# Else
kubectl get pods -n kube-system -l k8s-app=cilium
```

### 3. Configure External Secrets Operator authentication

Create the Kubernetes Secret manifest, `auth-secret.yaml`, required for the `External Secrets Operator` to authenticate against your chosen external secrets backend/provider.

> Note: The exact contents of this secret depend on the external secret provider you use (e.g. AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, HashiCorp Vault, etc.).
Refer to the [official provider documentation](https://external-secrets.io/latest/provider/aws-secrets-manager/) to know the supported providers and the corresponding secret format and required fields.

In my case, I use [HashiCorp Vault](https://github.com/hashicorp/vault) as the backend. Authentication can be done in multiple ways (Kubernetes auth, AppRole, token-based auth), and each requires a different `secret` structure.

Create the namespace:

```bash
kubectl create namespace eso
```

Apply the secret to the cluster:

```bash
kubectl -n eso apply -f infrastructure/controllers/eso/auth-secret
```

### 4. Deploy ArgoCD Main Components and CRDs

Apply ArgoCD manifests via `kustomize` with Helm enabled:

```bash
kubectl kustomize infrastructure/controllers/argocd --enable-helm | kubectl apply --server-side -f -
```

Wait for ArgoCD CRDs to be established:

```bash
kubectl wait --for condition=established --timeout=60s crd/applications.argoproj.io
```

Wait for ArgoCD server deployment to be ready:

```bash
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
```


### 5. Bootstrap the GitOps Loop

Now that ArgoCD is running and its CRDs are ready, apply the root application to start the self-managing GitOps workflow:

```bash
kubectl apply -f infrastructure/controllers/argocd/root.yaml
```

### 6. Optional: Access ArgoCD Web GUI

After ArgoCD is up and running, you can access its **Web GUI** for a visual overview of your cluster's current status.  
The Web GUI provides insight into the synchronization state of applications, health status of resources, and allows you to perform certain operations directly from the interface.


#### Get the ArgoCD Initial Admin Password

Run the following command to retrieve the initial admin password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```


#### Access the Web GUI

1. Open your browser and navigate to your ArgoCD server's URL or IP.  
2. Use the following credentials to log in:
   - **Username:** `admin`
   - **Password:** _(value retrieved from the previous command)_


#### Changing Login Credentials

You can change the default admin password using the **ArgoCD CLI**.  
For instructions, refer to the official [ArgoCD documentation](https://argo-cd.readthedocs.io/)


## Verification

After bootstrapping, wait a few minutes and verify that all components are healthy and running correctly.


### 1. Verify Nodes Are Ready

Check that all your Kubernetes nodes are in the `Ready` state:

```bash
kubectl get nodes
```


### 2. Verify CNI Functionality

Run a Cilium connectivity test to ensure that networking is functioning as expected:

```bash
cilium connectivity test
```


### 3. Verify All Pods Are Running

It may take **~15 minutes**(or more depending on nodes' resources and cluster components number) for all container images to pull and pods to become ready.

```bash
kubectl get pods -A
```


### 4. Check That Secrets Have Been Populated

Verify that Sealed Secrets resources exist:

```bash
kubectl get sealedsecrets -A
```


### 5. Check ArgoCD Applications Sync Status

Ensure that the `STATUS` column eventually shows `Synced` for all applications:

```bash
kubectl get applications -n argocd -w
```

## Extra Documentation

Additional information on setup and how things work can be found in the folder [`docs`](./docs/)