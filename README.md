# GitOps-Driven Kubernetes Cluster with ArgoCD

This repository contains the configuration and manifests for a **GitOps-driven Kubernetes cluster** managed entirely through **ArgoCD**, built for my homelab using GitOps best practices and patterns.

## Table of Contents

- [GitOps-Driven Kubernetes Cluster with ArgoCD](#gitops-driven-kubernetes-cluster-with-argocd)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Cluster Components](#cluster-components)
    - [Infrastructure](#infrastructure)
    - [Applications](#applications)
  - [Prerequisites](#prerequisites)
  - [Bootstrapping the Cluster](#bootstrapping-the-cluster)
    - [1. Install Cilium CNI and wait for it to be ready](#1-install-cilium-cni-and-wait-for-it-to-be-ready)
    - [2. Install Sealed Secrets CRDs](#2-install-sealed-secrets-crds)
    - [3. Create Encryption and Decryption Keys for Sealed Secrets](#3-create-encryption-and-decryption-keys-for-sealed-secrets)
    - [4. Create the Kubernetes Secret Manifest](#4-create-the-kubernetes-secret-manifest)
    - [5. Deploy ArgoCD Main Components and CRDs](#5-deploy-argocd-main-components-and-crds)
    - [6. Bootstrap the GitOps Loop](#6-bootstrap-the-gitops-loop)
    - [7. Optional: Access ArgoCD Web GUI](#7-optional-access-argocd-web-gui)
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

- **GitOps Pattern:** Flattened ApplicationSets provide a clean separation of concerns between infrastructure and applications.
- **App of Apps Pattern:** Enables management of multiple applications through a single ArgoCD application, automatically detecting and deploying changes from the Git repository to the Kubernetes cluster.
- **Self-Management:** ArgoCD manages its own installation and configuration, while continuously reconciling all other infrastructure components and applications declared in this repository—ensuring the entire cluster remains consistent with the Git source of truth.
- **External & Internal Access to Services**  
  - Internal: All services are accessible inside the home network.  
  - External: Selected services are available from the internet through **Cloudflare Tunnel**.


## Cluster Components

### Infrastructure

| Logo | Name | Purpose |
|------|------|---------|
| <img src="https://argo-cd.readthedocs.io/en/stable/assets/logo.png" width="50"/> | [ArgoCD](https://argo-cd.readthedocs.io/) | GitOps continuous delivery controller |
| <img src="https://raw.githubusercontent.com/cert-manager/cert-manager/refs/heads/master/logo/logo-small.png" width="50"/> | [Cert-Manager](https://cert-manager.io/) | Automated TLS certificate management |
| <img src="https://camo.githubusercontent.com/4759101d66da36edea0998f8da3084921bd4f4eed32b999dde06685d7ac9f068/68747470733a2f2f63646e2e6a7364656c6976722e6e65742f67682f686f6d6172722d6c6162732f64617368626f6172642d69636f6e732f7376672f63696c69756d2e737667" width="50"/> | [Cilium](https://cilium.io/) | Super CNI with advanced networking. Uses eBPF and has observability and security. Also acts as a kube-proxy replacement in this case |
| <img src="https://cdn-1.webcatalog.io/catalog/cloudflare-zero-trust/cloudflare-zero-trust-icon-unplated.png?v=1714773945620" width="50"/> | [Cloudflare Zero Trust](https://www.cloudflare.com/zero-trust/) | External secure access and tunneling |
| <img src="https://kubernetes-sigs.github.io/external-dns/latest/docs/img/external-dns.png" width="50"/> | [External DNS](https://kubernetes-sigs.github.io/external-dns/latest/) | DNS synchronisation and automation |
| <img src="https://longhorn.io/img/logos/longhorn-icon-color.png" width="50"/> | [Longhorn](https://longhorn.io/) | Distributed block storage for Kubernetes |
| <img src="https://docs.renovatebot.com/assets/images/logo.png" width="50"/> | [Renovate](https://docs.renovatebot.com/) | Automated dependency updates (Github Application) |
| <img src="https://avatars.githubusercontent.com/u/34656521?v=4" width="50"/> | [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) | Encrypt and manage Kubernetes secrets securely |


### Applications

| Logo | Name | Purpose |
|------|------|---------|
| <img src="https://svgicons.com/api/ogimage/?id=221729&n=file-type-excalidraw" width="50"/> | [Excalidraw](https://excalidraw.com/) | Whiteboard |
| <img src="https://raw.githubusercontent.com/gethomepage/homepage/refs/heads/dev/public/android-chrome-192x192.png" width="50"/> | [Homepage](https://gethomepage.dev/) | Dashboard  |
| <img src="https://upload.wikimedia.org/wikipedia/commons/thumb/4/41/Jellyfin_-_icon-transparent.svg/1024px-Jellyfin_-_icon-transparent.svg.png?20240822231831" width="50"/> | [Jellyfin](https://jellyfin.org/) | LiveTV (my use case)  |
| <img src="https://www.filecroco.com/wp-content/uploads/2019/05/nextpvr-icon.png" width="50"/> | [NextPVR](https://nextpvr.com/) | Live IPTV & DVR |
| <img src="https://www.stremio.com/website/stremio-logo-small.png" width="50"/> | [Stremio](https://www.stremio.com/) | Media streaming |


## Prerequisites

Before deploying this setup, make sure you have the following:

1. **A Kubernetes cluster** with:
   - Gateway API enabled
   - Without kube-proxy → See [Cilium KubeProxy-Free Docs](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
   - If Gateway API is **not installed**, run:
     ```bash
     kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
     kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml
     ```
   - **Tip:** If you don't already have a Kubernetes cluster but have access to a **Proxmox node/cluster**, you can use my other project — which I also use to create my own cluster.  
     It comes preconfigured with the **Gateway API CRDs installed** and **kube-proxy installation skipped**:  
     [Tiagura/proxmox-k8s-IaC (GatewayAPI branch)](https://github.com/Tiagura/proxmox-k8s-IaC/tree/GatewayAPI)

2. **A domain configured on Cloudflare**

3. **Local CLI tools installed**:
   - [`kubectl`](https://kubernetes.io/docs/tasks/tools/#kubectl)
   - [`kustomize`](https://kubectl.docs.kubernetes.io/installation/kustomize/) (Normally installed when `kubectl` is installed)
   - [`kubeseal`](https://github.com/bitnami-labs/sealed-secrets?tab=readme-ov-file#kubeseal)
   - [`cilium CLI`](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)

## Bootstrapping the Cluster

Follow these steps to bootstrap your Kubernetes cluster with all the necessary components and start the GitOps workflow:


### 1. Install Cilium CNI and wait for it to be ready

Make sure you have the `cilium` CLI installed locally.

```bash
cilium install --values infrastructure/networking/cilium/values.yaml
cilium status --wait
```


### 2. Install Sealed Secrets CRDs

```bash
kubectl apply -f https://raw.githubusercontent.com/bitnami-labs/sealed-secrets/v0.31.0/helm/sealed-secrets/crds/bitnami.com_sealedsecrets.yaml
```


### 3. Create Encryption and Decryption Keys for Sealed Secrets

Generate a private key:

```bash
openssl genrsa -out sealed-secrets.key 4096
```

Generate a self-signed certificate:

```bash
openssl req -x509 -new -nodes -key sealed-secrets.key -subj "/CN=sealed-secret" -days <DAYS_NUMBER> -out sealed-secrets.crt
```

Base64 encode the key and certificate:

```bash
base64 -w0 sealed-secrets.key > key.b64
base64 -w0 sealed-secrets.crt > crt.b64
```


### 4. Create the Kubernetes Secret Manifest

Edit `sealed-secrets-key.yaml` (for example with `nano sealed-secrets-key.yaml`) and paste the following, replacing `<contents-of-crt.b64>` and `<contents-of-key.b64>` with the base64-encoded contents from above:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: sealed-secrets-key
  namespace: sealed-secrets
type: kubernetes.io/tls
data:
  tls.crt: <contents-of-crt.b64>
  tls.key: <contents-of-key.b64>
```

  - **Note:** If you change the value of metadata.name, you must also update the `existingSecret` field in the [values file](infrastructure/controllers/sealed-secrets/values.yaml) to match. Otherwise, the controller won’t be able to find and use the correct key pair.

Create the namespace for sealed-secrets:

```bash
kubectl create namespace sealed-secrets
```

Apply the secret to the cluster:

```bash
kubectl apply -f infrastructure/controllers/sealed-secrets/sealed-secrets-key.yaml
```


### 5. Deploy ArgoCD Main Components and CRDs

Apply ArgoCD manifests via `kustomize` with Helm enabled:

```bash
kustomize build infrastructure/controllers/argocd --enable-helm | kubectl apply -f -
```

Wait for ArgoCD CRDs to be established:

```bash
kubectl wait --for condition=established --timeout=60s crd/applications.argoproj.io
```

Wait for ArgoCD server deployment to be ready:

```bash
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s
```


### 6. Bootstrap the GitOps Loop

Now that ArgoCD is running and its CRDs are ready, apply the root application to start the self-managing GitOps workflow:

```bash
kubectl apply -f infrastructure/controllers/argocd/root.yaml
```

### 7. Optional: Access ArgoCD Web GUI

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