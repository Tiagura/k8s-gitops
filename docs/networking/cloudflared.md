# Cloudflared Zero Trust Tunnel Setup

## Overview

This setup requires using a **locally managed tunnel**, meaning the tunnel **cannot be created through the Cloudflare dashboard on the web**. Instead, you must create it via the `cloudflared` CLI.


## Steps

### 1. Install the `cloudflared` CLI

Follow the [official guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/local-management/create-local-tunnel/#1-download-and-install-cloudflared) to install the CLI


### 2. Create the tunnel

Run the following command to login and authenticate:

```bash
cloudflared tunnel login
```

This opens a browser where you link the tunnel to your Cloudflare domain.

Next, create the tunnel:

```bash
cloudflared tunnel create <tunnel-name>
```


### 3. Create the sealed secret for Kubernetes

To allow ArgoCD to access the tunnel credentials and create the tunnel successfully, create a Kubernetes secret from the credentials JSON file:

```bash
kubectl create secret generic cloudflared-credentials-secret \
  --from-file=credentials.json=<path-to-credentials-json-file> \
  --type=Opaque \
  --namespace=cloudflared \
  --dry-run=client -o yaml > cloudflared-tunnel-creds-secret.yaml
```

Then seal the secret with `kubeseal`:

```bash
kubeseal --format=yaml --scope=cluster-wide --cert=<your-sealed-secrets-public-key.crt> < cloudflared-tunnel-creds-secret.yaml > infrastructure/networking/cloudflared/cloudflared-tunnel-creds-secret-sealed.yaml
```


### 4. Configure DNS

You have two options:

- Use [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) to automatically push DNS records to Cloudflare.
- Or manually create DNS routes with:

```bash
cloudflared tunnel route dns <tunnel-name> "*.<your_domain>"
```

> Using `"*.<your_domain>"` exposes all services your gateway handles.
> If you want to expose only specific service/s, use `"<service>.<your_domain>"` instead.


### 5. Additional security recommendations

- Create Access policies (e.g., restricting allowed emails for family members and/or client from your home country only).
- Link to an app with authentication for added security.
- In your Cloudflare Gateway, use firewall policies to restrict traffic to your home country, for example.


## Reminder: Modify the config.yaml
Before deploying, make sure to customize the [config.yaml](../../infrastructure/networking/cloudflared/config.yaml) according to your environment and service needs.

