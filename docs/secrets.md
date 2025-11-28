# Secret Management

The cluster manages secrets using [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets). The goal was to avoid introducing additional components that require external dependencies or services. During the research, two main approaches were identified: [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) and [SOPS](https://github.com/isindir/sops-secrets-operator). Sealed Secrets was ultimately selected because the operator is mature and provides a straightforward workflow for handling secrets within a GitOps setup.

For a small number of secrets, Sealed Secrets is straightforward and manageable. However, as the number of sealed secrets grows, maintaining them in Git can become increasingly labor-intensive. In such cases, consider using ([ESO](https://external-secrets.io/latest/)) to simplify management.

> **NOTE**: In scenarios where committing secrets to Git is not desired, even in encrypted form, the External Secrets Operator ([ESO](https://external-secrets.io/latest/)) can be used. ESO retrieves secrets from a [variety of backends](https://external-secrets.io/latest/provider/aws-secrets-manager/). Also, for larger or more security-sensitive environments, ESO is generally the more robust choice.

## Table of contents

- [Secret Management](#secret-management)
  - [Table of contents](#table-of-contents)
  - [Initial Bootstrap and Un/Seal Key](#initial-bootstrap-and-unseal-key)
  - [Scoped Secrets](#scoped-secrets)
  - [Seal and Unseal Operations](#seal-and-unseal-operations)
    - [Seal a Secret](#seal-a-secret)
    - [Unseal a Secret](#unseal-a-secret)
  - [Key Rotation](#key-rotation)
    - [Using the Key Rotation Script](#using-the-key-rotation-script)
  - [Resources:](#resources)

## Initial Bootstrap and Un/Seal Key
In order for the Sealed Secrets controller to unseal and manage secrets that were sealed beforehand, it must be provided with the same key pair that was used to seal the secrets. This ensures the controller can successfully unseal all secrets when they are applied to the cluster.

To achieve this, the secret containing the private key and public certificate must be created before the controller is deployed/starts. This secret acts as the bootstrap key for the Sealed Secrets operator and allows it to operate with previously sealed secrets without generating a new key pair.

This process corresponds to [steps 3-5](../README.md#3-create-encryption-and-decryption-keys-for-sealed-secrets) in the ["Bootstrapping the Cluster"](../README.md#bootstrapping-the-cluster) section of the main README. Once the secret has been created, the only remaining thing is to tell the controller which secret to use. This is configured in the [`values.yaml`](../infrastructure/controllers/sealed-secrets/values.yaml#L5) file, where the `existingSecret` field specifies the name of the secret to use, allowing the controller to immediately use the provided key to unseal the secrets in the cluster.

## Scoped Secrets
Because resources are deployed across multiple namespaces, the Sealed Secrets controller cannot, by default, unseal secrets that are outside its own namespace. Each sealed secret is normally bound to the namespace it was created in, `scope: strict (default)`, which prevents a single controller instance from decrypting secrets in other namespaces.

As a workaround, Sealed Secrets supports [scopes](https://github.com/bitnami-labs/sealed-secrets?tab=readme-ov-file#scopes). In this setup, all secrets are sealed using the `cluster-wide` scope, which allows a secret to be unsealed in any namespace and with any name. This enables a single controller instance to manage and decrypt all secrets across the cluster.

If the `cluster-wide` scope is not used, a controller would need to be deployed per namespace to unseal secrets in each one. This approach increases complexity and maintenance effort significantly, especially in clusters with many namespaces and applications.

## Seal and Unseal Operations

Secrets can be sealed and unsealed using the [kubeseal CLI](https://github.com/bitnami-labs/sealed-secrets?tab=readme-ov-file#kubeseal), a client-side tool.

### Seal a Secret

1. Create the secret YAML (from an existing secret or directly using `kubectl`):
    ```bash
    kubectl create secret generic ... --dry-run=client -o yaml > <file_name>.yaml
    ```
2. Seal the secret using the public key:
    ```bash
    kubeseal --format yaml --scope=cluster-wide --cert sealed-secrets.crt < <file_name>.yaml > <file_name>-sealed.yaml
    ```
    > **Note**: If the public key file (.crt) is not available locally, it can be extracted from the cluster:
    ```bash
    kubectl -n sealed-secrets get secret sealed-secrets-key -o jsonpath='{.data.tls\.crt}' | base64 -d > sealed-secrets.crt
    ```
3. Commit the secret to git

### Unseal a Secret

1. If the private key file (.key) is not available locally, extract it from the cluster:
    ```bash
    kubectl -n sealed-secrets get secret sealed-secrets-key -o jsonpath='{.data.tls\.key}' | base64 -d > sealed-secrets.key
    ```

2. Unseal the secret:
    ```bash
    kubeseal --recovery-unseal --recovery-private-key ./sealed-secrets.key < <path_to_file>-sealed.yaml > <path_to_file>.yaml
    ```

## Key Rotation
Rotating the seal and unseal key pair is necessary to maintain security while keeping all existing secrets decryptable. Conceptually, the process involves:
1. Fetch existing sealed secrets
   - Collect all `*-sealed.yaml` files from the repository. 
2. Generate the new key pairs
   - Create a new TLS private key and public certificate.
3. Unseal and reseal secrets with the new key
   - Decode each sealed secret using the old private key.
   - Re-seal the secret using the new public certificate.
   - Replace the old sealed secret files in the repository with the updated versions.
4. Update the TLS secret
   - Update the secret used by the Sealed Secrets controller to unseal secrets with the new key pair. This involves updating the sealed-secrets-key.yaml secret manifest.
5. Restart the Sealed Secrets controller
   - Redeploy or restart the controller so it picks up the new key and can unseal all secrets going forward.
        ```bash
        kubectl -n sealed-secrets rollout restart deploy/sealed-secrets
        ```

### Using the Key Rotation Script
Alternatively, the key rotation process can be automated using the provided `scripts/rotate-seal-key.sh` script. The script automates steps 1-3 and also backups up files. 
Specifically:
  - The old key pair, along with the newly generated key pair, is stored inside the `.sealed-secrets-rotation` folder.

  - The secret manifest containing the old key pair is moved to the `.sealed-secrets-rotation` folder 

  - All existing sealed secret files are backed up in-place by creating a `*.bak` version in the same directory as the original.


> **Note**: Rotating the un/seal key pair only changes the encryption used for sealed secrets.
It does not rotate the underlying Kubernetes Secret data itself. For full security, actual credentials contained within each secret should also be rotated after completing the resealing process.

## Resources:

- [Sealed Secrets Github](https://github.com/bitnami-labs/sealed-secrets)