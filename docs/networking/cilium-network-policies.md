# Cilium Network Policies

Cilium Network Policies provide fine-grained network control for pods in Kubernetes, allowing various types of enforcement and identity-based rules. Compared to standard Kubernetes NetworkPolicies, Cilium allows:

- Various Network Layers of policies 
- Entity-based policies (`world`, `kube-apiserver`, etc.)  
- Observability via Hubble  
- eBPF-powered enforcement for better performance
- Many more

## Table of contents
- [Cilium Network Policies](#cilium-network-policies)
  - [Table of contents](#table-of-contents)
  - [Common Network Policies](#common-network-policies)
    - [How to use them](#how-to-use-them)
    - [How to "import"](#how-to-import)
  - [Caveats for Enforcing Policies on CloudNativePG Cluster Pods](#caveats-for-enforcing-policies-on-cloudnativepg-cluster-pods)
    - [Egress from Application Pods to Database Pods (i.e. policies applied to application `pods`)](#egress-from-application-pods-to-database-pods-ie-policies-applied-to-application-pods)
    - [Applying policies to `pods` created from CloudNativePG `Cluster` resources](#applying-policies-to-pods-created-from-cloudnativepg-cluster-resources)
      - [Possible Approaches](#possible-approaches)
      - [Chosen Approach](#chosen-approach)
  - [Resources](#resources)

## Common Network Policies

The policies in [`common/cilium-network-policies/`](../../common/cilium-network-policies/) are the most basic and reusable ones. They are meant to be imported as needed, depending on which pods or namespaces require them.

There are also **dedicated policies for specific apps/workloads**, which are found in their respective folders. These should be used only for the apps they are designed for.  

### How to use them 

Each "common" policy can be applied to pods via **labels**. This allows the policy to selectively target only the pods that need it, without affecting other workloads.  

The following common policies are available in [`common/cilium-network-policies/`](../../common/cilium-network-policies/):

| Policy Name                      | Label to Apply                                      | Description                                                               |
| -------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------- |
| egress-deny.yaml                 | `netpol.cilium.io/egress-deny="true"`                 | Denies all egress traffic from the selected pods.                         |
| egress-to-cloudflare.yaml        | `netpol.cilium.io/egress-to-cloudflare="true"`        | Allows egress traffic to Cloudflare public IPs.                           |
| egress-to-gotify.yaml            | `netpol.cilium.io/egress-to-gotify="true"`            | Allows egress traffic to the cluster's Gotify server.                     |
| egress-to-host.yaml              | `netpol.cilium.io/egress-to-host="true"`              | Allows egress traffic to the host's local network.                        |
| egress-to-intra.yaml             | `netpol.cilium.io/egress-to-intra="true"`             | Allows egress traffic to all pods inside the same namespace.              |
| egress-to-kube-apiserver.yaml    | `netpol.cilium.io/egress-to-kube-apiserver="true"`    | Allows egress traffic to the Kubernetes API server.                       |
| egress-to-kube-dns.yaml          | `netpol.cilium.io/egress-to-kube-dns="true"`          | Allows egress traffic to the cluster DNS service.                         |
| egress-to-public-ips.yaml        | `netpol.cilium.io/egress-to-public-ips="true"`        | Allows egress traffic to public IP addresses (excludes private ranges).   |
| egress-to-remote-node.yaml       | `netpol.cilium.io/egress-to-remote-node="true"`       | Allows egress traffic to other nodes' local network.                      |
| egress-to-world.yaml             | `netpol.cilium.io/egress-to-world="true"`             | Allows egress traffic to any destination outside the cluster (private IPs also). |
| ingress-deny.yaml                | `netpol.cilium.io/ingress-deny="true"`                | Denies all ingress traffic to the selected pods.                          |
| ingress-from-host.yaml           | `netpol.cilium.io/ingress-from-host="true"`           | Allows ingress traffic from host's local network.                         |
| ingress-from-ingress.yaml        | `netpol.cilium.io/ingress-from-ingress="true"`        | Allows ingress traffic from ingress controllers or gateways APIs          |
| ingress-from-intra.yaml          | `netpol.cilium.io/ingress-from-intra="true"`          | Allows ingress traffic from other pods in the same namespace.             |
| ingress-from-kube-apiserver.yaml | `netpol.cilium.io/ingress-from-kube-apiserver="true"` | Allows ingress traffic from the Kubernetes API server.                    |
| ingress-from-prometheus.yaml     | `netpol.cilium.io/ingress-from-prometheus="true"`     | Allows ingress traffic from Prometheus monitoring pods.                   |
| ingress-from-remote-node.yaml    | `netpol.cilium.io/ingress-from-remote-node="true"`    | Allows ingress traffic from other nodes' local network.                   |
| ingress-from-world.yaml          | `netpol.cilium.io/ingress-from-world="true"`          | Allows ingress traffic from any external source.                          |

### How to "import"

These policies can be included in your apps/workloads manifests using **Kustomize** (`kustomization.yaml` files) in several ways:"

```yaml
resources:
  # All cilium network policies and whatever is in the common folder:
  - path/to/common/
  # All cilium network policies
  - path/to/common/cilium-network-policies/
  # Specific cilium network policies
  - path/to/common/cilium-network-policies/<name_of_file>
```

## Caveats for Enforcing Policies on CloudNativePG Cluster Pods

When enforcing network policies for traffic to/from `pods` created from CloudNativePG `Cluster` resources (i.e., the database `pods` and any `pods` accessing them), there are some important caveats to consider.

### Egress from Application Pods to Database Pods (i.e. policies applied to application `pods`)

Using **service-based policies** like the example below may not work as expected:
```yaml
egress:
  - toServices:
      - k8sService:
          serviceName: <cluster-name>-rw
          namespace: <cluster-namespace>
    toPorts:
      - ports:
          - port: "<cluster-database-port>"
            protocol: TCP
  ...
```

Instead, **endpoint-based** policies reliably work because they target `pods` directly based on their labels and namespace:
```yaml
egress:
  - toEndpoints:
      - matchLabels:
          io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name: <cluster-namespace>
          cnpg.io/cluster: <cluster-name>
    toPorts:
      - ports:
          - port: "<cluster-database-port>"
            protocol: TCP
```

### Applying policies to `pods` created from CloudNativePG `Cluster` resources

At this time, it is not possible to automatically propagate labels from a `Cluster` resource to the `pods` it creates, nor to directly add labels to these `pods`. While manually labeling the `pods` is technically possible, it would break the GitOps principle of declarative management. As such, it is currently impossible to apply the common network policies directly to these `pods`.

#### Possible Approaches

In theory, it is possible to propagate labels and/or annotations from the CloudNativePG `Cluster` resource to all resources it creates, including the `pods`. 

One or more labels or annotations can be defined in the cluster's metadata, and the operator can be configured to ensure they are inherited by all child resources. However, these propagated labels apply the same policies to all database `pods`. This prevents using a label to allow ingress specifically from the corresponding application pod to its respective database `pods`. 

Possible approaches include:
  1. **Propagate common policy labels** to all database `pods` and **create a smaller policy**, more targeted network policy to allow ingress from the application `pods` to the database `pods`. (This approach is theoretically possible but not tested in this setup.)
  2. **Create a larger policy** that targets all database `pods` in the cluster, defining both ingress and egress rules as required. This approach ensures network security while maintaining compatibility with GitOps workflows.

#### Chosen Approach

The chosen approach to solve this problem is to create a bigger `CiliumNetworkPolicy` that target all `pods` created from a specific CloudNativePG `Cluster` resource. For example:
  - All `pods` from `cluster1` receive the same policy `policy1`.
  - All `pods` from `cluster2` receive the same policy `policy2`.

The base `CiliumNetworkPolicy` [`default-database-netpol`](../../infrastructure/databases/db-cilium-netpols/default-db-netpol.yaml) serves as an example that can be customized per `Cluster` resource to define ingress and egress rules that enforce the required security while maintaining compatibility with GitOps workflows.

## Resources

- [Cilium Network Policy Overview](https://docs.cilium.io/en/latest/security/policy/)
- [CNPG Labels and Annotations](https://cloudnative-pg.io/docs/1.28/labels_annotations)