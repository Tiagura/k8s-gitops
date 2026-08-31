# Secret Management

## Table of Contents

- [Secret Management](#secret-management)
  - [Table of Contents](#table-of-contents)
  - [External Secrets Operator](#external-secrets-operator)
    - [How It Works](#how-it-works)
    - [Configuration](#configuration)
      - [Dependencies](#dependencies)
      - [Configuration](#configuration-1)
        - [Vault authentication](#vault-authentication) 
      - [HashiCorp Vault Backend](#hashicorp-vault-backend)
    - [Single Cluster Store](#single-cluster-store)
    - [Monitoring & Alerts](#monitoring--alerts)
      - [Monitor](#monitor)
      - [Alerts](#alerts)
  - [Sealed Secrets (Removed)](#sealed-secrets-removed)
  - [Resources](#resources)

## [External Secrets Operator](https://external-secrets.io/latest/)

[External Secrets Operator (ESO)](https://external-secrets.io/) is used to synchronize secrets from [HashiCorp Vault](https://www.vaultproject.io/) into Kubernetes `Secret` resources.

The goal of this setup is to keep secret values in a single source location and out of the Git repository while still allowing applications to consume them through native Kubernetes `Secret` resources.

### How It Works

The secret flow is:

```text
HashiCorp Vault
    |
    | AppRole authentication
    v
ClusterSecretStore
    |
    | ExternalSecret
    v
Kubernetes Secret
    |
    v
Application
```

ESO periodically reads the requested values from Vault and reconciles them into Kubernetes `Secret` resources. Applications therefore consume secrets using the standard Kubernetes API without needing to communicate directly with Vault.

### Configuration

#### Dependencies

This configuration has two direct dependencies:

##### cert-manager

[cert-manager](https://cert-manager.io/) is used to provide the TLS certificate required by the ESO webhook.

The webhook certificate is issued through the existing `internal-cluster-issuer` `ClusterIssuer`.

##### HashiCorp Vault

[HashiCorp Vault](https://www.vaultproject.io/) is the source of truth for the secrets consumed by ESO.

This setup uses:

* Vault's KV secrets engine
* KV API version 2
* AppRole authentication
* HTTPS communication

The Vault instance is intentionally not running inside the Kubernetes cluster. See [HashiCorp Vault Backend](#hashicorp-vault-backend) for the reasoning behind this decision.

#### Configuration

The ESO configuration is managed through Kustomize and consists of the ESO deployment, the `ClusterSecretStore`, and the network policy required to access Vault.

The main configuration provides the following functionality:

* ESO runs in the `eso` namespace.
* HashiCorp Vault is configured as the external secret provider.
* Secrets are synchronized from Vault into Kubernetes `Secret` resources.
* The ESO webhook uses a certificate managed by cert-manager.
* Push functionality is disabled because Vault is being used as a read-only source of secrets for Kubernetes.
* Prometheus metrics and a Grafana dashboard are enabled.
* Network access is restricted so ESO can only reach the Kubernetes API, DNS, and the Vault endpoint.

#### Vault authentication

The `ClusterSecretStore` connects to Vault using AppRole authentication.

The store points to:

```text
Vault server: https://secrets.tamhomelab.com
Secrets path: secrets
API version: v2
Authentication: AppRole
```

The AppRole SecretID is referenced from:

```text
Namespace: eso
Secret:    vault-approle
Key:       secret-id
```

Only the reference to the SecretID is stored in the Git-managed configuration. The SecretID itself must be provisioned separately.

### HashiCorp Vault Backend

HashiCorp Vault is used as the ESO backend and is intentionally hosted outside the Kubernetes cluster.

The main reason is disaster recovery. Longhorn uses S3-compatible storage for backups, and the credentials for that S3 storage are stored in Vault. Running Vault inside the cluster would create a chicken-and-egg problem:

```text
Vault
  |
  v
Longhorn S3 credentials
  |
  v
Longhorn
  |
  v
Cluster storage
```

If the cluster is completely lost, Vault would also be unavailable, preventing Longhorn from accessing its backups.

Instead, Vault has its own independent infrastructure and backup:

```text
Independent Vault
  |
  v
Longhorn S3 credentials
  |
  v
Longhorn restoration
  |
  v
Kubernetes cluster
```

This avoids having to maintain a second secret location just for the Longhorn credentials. If Vault itself fails, it can be restored independently from its own backups.

For this homelab, this is a deliberate trade-off between simplicity and resilience.

### Single Cluster Store

This setup intentionally uses a single `ClusterSecretStore` rather than creating a separate `SecretStore` for every namespace.

A per-namespace `SecretStore` model can provide stronger isolation. For example, each application namespace could have its own Vault authentication credentials and be restricted to its own Vault paths.

However, this is a homelab rather than a production multi-tenant Kubernetes environment. Maintaining separate stores, authentication credentials, and policies for every namespace would add operational complexity that is not particularly valuable for this cluster.

The chosen approach is therefore a compromise:

* Centralized configuration through one `ClusterSecretStore`
* Simpler operations when adding new applications
* Vault remains the source of truth

The trade-off is that the `ClusterSecretStore` represents a broader trust boundary than individual namespace-scoped `SecretStore` resources.

If this cluster were converted into a multi-tenant or production environment, separating stores and Vault policies per namespace or application would be a stronger security model.

### Monitoring & Alerts

### Monitor

ESO exposes Prometheus metrics and is configured with a `ServiceMonitor`.

Monitoring is enabled directly in the Helm values:

```yaml
serviceMonitor:
  enabled: true
  namespace: prometheus-stack
```

A Grafana dashboard is also enabled as part of the ESO deployment.

The dashboard provides a quick overview of ESO's operational state, while Prometheus metrics can be used for more specific troubleshooting and alerting.

### Alerts

ESO-specific alert rules are not currently defined.


## [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) (Removed)

This projets previously used [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) to manage cluster secrets. If you need to help/understand how they work, refer to commit [ddb74c6](https://github.com/Tiagura/k8s-gitops/tree/ddb74c674e7209b55c6c7a54fe12f5d24b74aeb8) for an example how to add them to your clusters and/or use them.

## Resources

- [External Secrets Operator documentation](https://external-secrets.io/)
- [External Secrets Operator Vault provider](https://external-secrets.io/latest/provider/hashicorp-vault/)
- [HashiCorp Vault documentation](https://developer.hashicorp.com/vault/docs)
- [Vault KV secrets engine](https://developer.hashicorp.com/vault/docs/secrets/kv)
- [Vault AppRole authentication](https://developer.hashicorp.com/vault/docs/auth/approle)