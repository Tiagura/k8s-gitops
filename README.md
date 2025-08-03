# GitOps-Driven Kubernetes Cluster with ArgoCD

This repository contains the configuration and manifests for a **GitOps-driven Kubernetes cluster** managed entirely through **ArgoCD**, built for my homelab using GitOps best practices and patterns.

## Table of Contents

- [GitOps-Driven Kubernetes Cluster with ArgoCD](#gitops-driven-kubernetes-cluster-with-argocd)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites](#prerequisites)
  - [Features](#features)
  - [Cluster Components](#cluster-components)
    - [Infrastructure](#infrastructure)
    - [Applications](#applications)

## Prerequisites

Before deploying this setup, make sure you have the following:

1. **A Kubernetes cluster** with:
   - Gateway API enabled
   - Without kube-proxy → See [Cilium KubeProxy-Free Docs](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
   - If Gateway APIs are **not installed**, run:
     ```bash
     kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
     kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/experimental-install.yaml
     ```
   - **Tip:** If you don't already have a Kubernetes cluster but have access to a **Proxmox node/cluster**, you can use my other project to create one:  
     [Tiagura/proxmox-k8s-IaC (GatewayAPI branch)](https://github.com/Tiagura/proxmox-k8s-IaC/tree/GatewayAPI)

2. **A domain configured on Cloudflare**

3. **Local CLI tools installed**:
   - [`kubectl`](https://kubernetes.io/docs/tasks/tools/#kubectl)
   - [`kustomize`](https://kubectl.docs.kubernetes.io/installation/kustomize/) (Normally installed when `kubectl` is installed)
   - [`kubeseal`](https://github.com/bitnami-labs/sealed-secrets?tab=readme-ov-file#kubeseal)
   - [`cilium CLI`](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)


## Features

- **GitOps Pattern:** Flattened ApplicationSets provide a clean separation of concerns between infrastructure and applications.
- **App of Apps Pattern:** Manage multiple applications from a single ArgoCD application. Automatically detect and deploy changes from your Git repository to your Kubernetes cluster.
- **Self-Managing:** ArgoCD manages itself, so the cluster remains consistent with the Git repository.
- **External & Internal Access to Services**  
  - Internal: All services are accessible inside the home network.  
  - External: Select services are available from the internet through **Cloudflare Tunnel**.


## Cluster Components

### Infrastructure

| Logo | Name | Purpose |
|------|------|---------|
| <img src="https://argo-cd.readthedocs.io/en/stable/assets/logo.png" width="100"/> | [ArgoCD](https://argo-cd.readthedocs.io/) | GitOps continuous delivery controller |
| <img src="https://raw.githubusercontent.com/cert-manager/cert-manager/refs/heads/master/logo/logo-small.png" width="100"/> | [Cert-Manager](https://cert-manager.io/) | Automated TLS certificate management |
| <img src="https://camo.githubusercontent.com/4759101d66da36edea0998f8da3084921bd4f4eed32b999dde06685d7ac9f068/68747470733a2f2f63646e2e6a7364656c6976722e6e65742f67682f686f6d6172722d6c6162732f64617368626f6172642d69636f6e732f7376672f63696c69756d2e737667" width="100"/> | [Cilium](https://cilium.io/) | Super CNI with advanced networking. Uses eBPF and has observability and security. Also acts as a kube-proxy replacement in this case |
| <img src="https://cdn-1.webcatalog.io/catalog/cloudflare-zero-trust/cloudflare-zero-trust-icon-filled-256.webp?v=1714773945620" width="100"/> | [Cloudflare Zero Trust](https://www.cloudflare.com/zero-trust/) | Secure access and tunneling |
| <img src="https://avatars.githubusercontent.com/u/34656521?v=4" width="100"/> | [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) | Encrypt and manage Kubernetes secrets securely |
| <img src="https://longhorn.io/img/logos/longhorn-icon-color.png" width="100"/> | [Longhorn](https://longhorn.io/) | Distributed block storage for Kubernetes |
| <img src="https://docs.renovatebot.com/assets/images/logo.png" width="100"/> | [Renovate](https://docs.renovatebot.com/) | Automated dependency updates |


### Applications

| Logo | Name | Purpose |
|------|------|---------|
| <img src="https://downloads.marketplace.jetbrains.com/files/17096/632286/icon/default.png" width="100"/> | [Excalidraw](https://excalidraw.com/) | Whiteboard |
| <img src="https://raw.githubusercontent.com/gethomepage/homepage/refs/heads/dev/public/android-chrome-192x192.png" width="100"/> | [Homepage](https://gethomepage.dev/) | Dashboard for self-hosted services |
| <img src="https://www.filecroco.com/wp-content/uploads/2019/05/nextpvr-icon.png" width="100"/> | [NextPVR](https://nextpvr.com/) | Live IPTV & DVR |
| <img src="https://www.stremio.com/website/stremio-logo-small.png" width="100"/> | [Stremio](https://www.stremio.com/) | Media streaming |


