# Applications External Access

This document explains how to expose selected applications hosted on a k8s cluster through Cloudflare Tunnel and Cloudflare DNS, leveraging ExternalDNS.

## Tunnel Configuration

The Cloudflare Tunnel is configured to route traffic for all subdomains within the a domain

```yaml
hostname: "*.<domain>"
service: https://cilium-gateway-gateway.gateway.svc.cluster.local:443
```

This configuration means all requests to any subdomain are routed to the Gateway, effectively exposing all services behind it.

### Problem: Overexposure of Services

A wildcard tunnel provides convenience but lacks fine-grained control.
Every service routed through the Gateway becomes accessible, which is undesirable when some services are meant to remain private.

### Solution: Restricting Exposure with ExternalDNS

ExternalDNS can be used to automatically create DNS records only for services that are explicitly marked for external access.
This is achieved by applying the following label to Gateway API route resources (`HTTPRoute`, `TLSRoute`, `TCPRoute`, `UDPRoute`):

```yaml
labels:
    external-dns/enabled: "true"
```

ExternalDNS processes only the labeled routes and creates DNS entries for them, leaving other services inaccessible from the public internet.

#### Targeting the Cloudflare Tunnel

By default, ExternalDNS derives DNS targets from the Gateway’s status addresses, which in this setup is a private IP.
For traffic to pass through the Cloudflare Tunnel, DNS records must ultimately resolve to `<UUID>.cfargotunnel.com`.

#### CNAME Abstraction

To avoid exposing the tunnel UUID, an intermediate CNAME record is manually created in Cloudflare DNS, for example:
```bash
tunnel.<domain>  →  <UUID>.cfargotunnel.com  (proxied through Cloudflare)
```

ExternalDNS is then instructed to set the target of each public service record to `tunnel.<domain>`:
```yaml
annotations:
  external-dns.alpha.kubernetes.io/hostname: <service>.<domain>
  external-dns.alpha.kubernetes.io/target: tunnel.<domain>
```

## How it works

### Selective DNS Record Creation
1. ExternalDNS monitors Kubernetes Gateway API resources (HTTPRoute, TCPRoute, etc.).
2. Only resources labeled with `external-dns/enabled="true"` are processed.
3. For these resources, DNS records are created in Cloudflare mapping `<service>.<domain>` to `tunnel.<domain>`.

### DNS Resolution Path
- `tunnel.<domain>` is configured in Cloudflare as a proxied CNAME record pointing to `<UUID>.cfargotunnel.com`.
- This allows DNS queries for `<service>.<domain>` to resolve indirectly to the tunnel endpoint, without exposing the tunnel UUID in any Kubernetes manifests.

### Request Flow
 1. A client queries `<service>.<domain>`.
 2. Cloudflare DNS returns the CNAME chain: `<service>.<domain> → tunnel.<domain> → <UUID>.cfargotunnel.com`.
 3. Cloudflare routes the request through the established tunnel to the Kubernetes Gateway.
 4. The Gateway dispatches the request to the appropriate service based on route configuration.