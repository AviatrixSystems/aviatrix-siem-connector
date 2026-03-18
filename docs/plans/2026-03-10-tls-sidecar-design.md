# TLS Sidecar Design — mTLS Syslog Ingestion

**Date**: 2026-03-10
**Status**: Approved

## Goal

Enable TLS encryption between Aviatrix gateways (syslog sources) and the SIEM connector container. Uses a stunnel sidecar container that terminates mTLS on port 6514 (RFC 5425) and forwards plaintext TCP to Logstash on localhost:5000. Terraform manages the full certificate lifecycle — generation, storage, and optional Aviatrix controller configuration.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| TLS proxy | stunnel sidecar container | Purpose-built for TLS termination, ~8MB, trivial config, cloud-agnostic |
| Auth mode | mTLS always (when TLS enabled) | We control both ends; prevents unauthorized syslog sources |
| Cert generation | Terraform `tls` provider | Zero external dependencies, fully automated |
| Cert storage | AWS Secrets Manager (Azure/GCP later) | Native ECS integration, IAM-based access |
| Cert delivery to sidecar | Env vars (from Secrets Manager) | No cloud CLI in image, ECS `secrets` block extracts JSON keys natively |
| TLS toggle | Deploy-time (`tls_enabled` variable) | Not a runtime toggle — conditionally includes/excludes sidecar container |
| Aviatrix config | Optional Terraform resource | Removable; future controller-aware management component can take over |
| EC2 TLS plumbing | Shared `modules/aws-logstash` | Existing pattern; both single-instance and autoscale call this module |
| Logstash changes | None | Input config, filters, outputs all untouched |

## Architecture

### TLS Disabled (default, unchanged)

```
Aviatrix Gateways
       │ syslog UDP/TCP
       ▼
┌──────────────┐
│   Logstash   │ :5000 UDP+TCP (exposed)
│   Container  │
└──────────────┘
```

### TLS Enabled

```
Aviatrix Gateways
       │ syslog-tls TCP (RFC 5425)
       ▼
┌──────────────┐
│   stunnel    │ :6514 TLS (exposed)
│   sidecar    │ verify = 2 (mTLS)
└──────┬───────┘
       │ plaintext TCP
       ▼
┌──────────────┐
│   Logstash   │ :5000 TCP (internal only)
│   Container  │
└──────────────┘
```

- Logstash input config (`00-syslog-input.conf`) is unchanged — always plain TCP/UDP on 5000
- When TLS is enabled, only port 6514 is exposed externally; port 5000 is internal-only
- The stunnel sidecar is conditionally deployed — when TLS is off, it doesn't exist
- UDP is not available in TLS mode (RFC 5425 is TCP-only, matching Aviatrix behavior)
- Both containers share localhost networking (ECS awsvpc, docker compose default network)

## Certificate Lifecycle

### Generation (Terraform `tls` Provider)

```
terraform apply
       │
       ├─► tls_private_key (CA)            ─┐
       ├─► tls_self_signed_cert (CA)        ─┤ Long-lived (10 years)
       │                                     │
       ├─► tls_private_key (server)         ─┤
       ├─► tls_locally_signed_cert (server) ─┘ Short-lived (1 year)
       │
       ├─► tls_private_key (client)         ─┐
       ├─► tls_locally_signed_cert (client) ─┘ Short-lived (1 year)
       │
       ├─► aws_secretsmanager_secret ◄── server cert + key + CA cert
       │
       └─► outputs: ca_cert_pem, client_cert_pem, client_key_pem
```

### Certificate Roles

| Cert | Lifetime | Purpose | Stored In |
|------|----------|---------|-----------|
| CA cert | 10 years | Signs server + client certs; both sides validate against it | Secrets Manager + Terraform output |
| CA key | 10 years | Signs new certs on rotation | Terraform state |
| Server cert + key | 1 year | stunnel presents to gateways | Secrets Manager |
| Client cert + key | 1 year | Gateways present to stunnel | Aviatrix controller (pushed to gateways) |

One CA, one trust root. stunnel runs with `verify = 2` (require valid client cert signed by the CA).

### Rotation Flow

1. `terraform apply` (after cert expiry or manual taint of server/client cert resources)
2. New server cert generated, signed by same long-lived CA
3. New client cert generated, signed by same CA
4. Secrets Manager secret updated
5. Sidecar container restarts, picks up new server cert
6. Aviatrix `remote_syslog` resource updated with new client cert
7. Controller pushes new client cert to gateways
8. No trust chain changes — same CA throughout

### Aviatrix Integration

**Full automation** (with Aviatrix Terraform provider):

```hcl
resource "aviatrix_remote_syslog" "siem" {
  index                = var.aviatrix_syslog_profile_index
  name                 = "SIEM Connector"
  server               = module.siem_connector.syslog_endpoint
  port                 = 6514
  protocol             = "TCP"
  ca_certificate_file  = module.tls[0].ca_cert_pem
  public_certificate   = module.tls[0].client_cert_pem
  private_key          = module.tls[0].client_key_pem
}
```

**Manual** (without Aviatrix provider):

```bash
terraform output -raw tls_ca_certificate_pem > ca.pem
terraform output -raw tls_client_certificate_pem > client.crt
terraform output -raw tls_client_private_key_pem > client.key
# Upload all three in Aviatrix UI → Create Profile → Custom
```

### Future: Controller-Managed Certs

The current design stores certs at a well-known Secrets Manager path. A future management component (with Aviatrix controller API credentials) can take over cert generation and Aviatrix configuration by:

1. Removing `tls.tf` and `aviatrix-syslog.tf` from the deployment
2. Having the management component write certs to the same Secrets Manager path
3. stunnel sidecar is unchanged — reads from the same location

No design changes needed. The `tls.tf` and `aviatrix-syslog.tf` files are leaf files with no dependencies flowing back into the core deployment.

## stunnel Sidecar Container

### Dockerfile

```dockerfile
FROM alpine:3.21
RUN apk add --no-cache stunnel
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

### entrypoint.sh

```bash
#!/bin/sh
set -e

mkdir -p /etc/stunnel/certs
echo "$TLS_SERVER_CERT" > /etc/stunnel/certs/server.crt
echo "$TLS_SERVER_KEY"  > /etc/stunnel/certs/server.key
echo "$TLS_CA_CERT"     > /etc/stunnel/certs/ca.crt
chmod 600 /etc/stunnel/certs/server.key

cat > /etc/stunnel/stunnel.conf <<EOF
foreground = yes
[syslog-tls]
accept = ${TLS_PORT:-6514}
connect = 127.0.0.1:5000
cert = /etc/stunnel/certs/server.crt
key = /etc/stunnel/certs/server.key
CAfile = /etc/stunnel/certs/ca.crt
verify = 2
EOF

exec stunnel /etc/stunnel/stunnel.conf
```

Image is ~8MB. Cloud-agnostic — consumes env vars, doesn't care who populated them.

### Secrets Manager Layout

Single JSON secret:

```json
{
  "server_cert": "-----BEGIN CERTIFICATE-----\n...",
  "server_key": "-----BEGIN PRIVATE KEY-----\n...",
  "ca_cert": "-----BEGIN CERTIFICATE-----\n..."
}
```

## Deployment Integration

### ECS Fargate

Task definition gains a conditional second container:

```
ECS Task (awsvpc — shared localhost)
┌─────────────────────────────────────────────┐
│  stunnel (essential)        Logstash         │
│  :6514 TLS ──────────►     :5000 TCP        │
│                             :9600 API        │
│  secrets:                                    │
│    TLS_SERVER_CERT ◄── arn:...::server_cert  │
│    TLS_SERVER_KEY  ◄── arn:...::server_key   │
│    TLS_CA_CERT     ◄── arn:...::ca_cert      │
└─────────────────────────────────────────────┘
         ▲
    NLB listener :6514 TCP
```

ECS `secrets` block extracts JSON keys from Secrets Manager using `arn::json_key::` syntax. NLB listener changes from TCP_UDP:5000 to TCP:6514.

### EC2 (Single Instance + Autoscale)

Both use the shared `modules/aws-logstash` module. When TLS is enabled, `user_data` fetches certs from Secrets Manager and starts docker compose instead of a single `docker run`:

```yaml
services:
  stunnel:
    image: ghcr.io/aviatrixsystems/siem-connector-tls:latest
    ports:
      - "6514:6514"
    environment:
      - TLS_SERVER_CERT
      - TLS_SERVER_KEY
      - TLS_CA_CERT
    depends_on:
      - logstash

  logstash:
    image: ghcr.io/aviatrixsystems/siem-connector:latest
    environment:
      - OUTPUT_TYPE=${OUTPUT_TYPE}
      - LOG_PROFILE=${LOG_PROFILE}
      # ... output-specific env vars
```

Port 5000 is not exposed on the logstash service — only reachable via stunnel on the compose network. The `logstash_instance_init.tftpl` is modified to conditionally fetch certs and use `docker compose up` instead of `docker run`.

Security group rules change from port 5000 to port 6514 when TLS is enabled.

## Terraform Variables

Added to deployment modules:

```hcl
variable "tls_enabled" {
  description = "Enable mTLS syslog ingestion (port 6514) instead of plaintext (port 5000)"
  type        = bool
  default     = false
}

variable "tls_cert_validity_hours" {
  description = "Server/client cert validity period. CA validity is 10x this value."
  type        = number
  default     = 8760  # 1 year
}

variable "tls_secret_name" {
  description = "Secrets Manager secret name for TLS certs. Auto-generated if not specified."
  type        = string
  default     = ""
}

variable "aviatrix_controller_ip" {
  description = "Aviatrix controller IP for auto-configuring remote syslog. Leave empty to configure manually."
  type        = string
  default     = ""
}

variable "aviatrix_syslog_profile_index" {
  description = "Remote syslog profile index (0-9)"
  type        = number
  default     = 0
}
```

## Terraform Outputs

```hcl
output "syslog_endpoint" {
  value = var.tls_enabled ? "${endpoint}:6514" : "${endpoint}:5000"
}

output "syslog_protocol" {
  value = var.tls_enabled ? "TCP+TLS (mTLS)" : "UDP/TCP"
}

output "tls_ca_certificate_pem" {
  description = "Upload to Aviatrix as 'Server CA Certificate'"
  value       = var.tls_enabled ? module.tls[0].ca_cert_pem : null
  sensitive   = true
}

output "tls_client_certificate_pem" {
  description = "Upload to Aviatrix as 'Client Certificate'"
  value       = var.tls_enabled ? module.tls[0].client_cert_pem : null
  sensitive   = true
}

output "tls_client_private_key_pem" {
  description = "Upload to Aviatrix as 'Client Private Key'"
  value       = var.tls_enabled ? module.tls[0].client_key_pem : null
  sensitive   = true
}
```

## File Layout

```
tls-sidecar/                                # NEW — stunnel sidecar
  Dockerfile
  entrypoint.sh
  build.sh

modules/
  tls-certs/                                # NEW — cert generation module
    main.tf                                 #   CA + server + client cert resources
    secrets.tf                              #   Secrets Manager storage
    variables.tf
    outputs.tf

  aws-logstash/                             # EXISTING — modified
    main.tf                                 #   Conditional SG rules (6514 vs 5000)
    variables.tf                            #   Add tls_enabled, tls_secret_arn
    outputs.tf                              #   Add syslog_port, syslog_protocol
    logstash_instance_init.tftpl            #   Conditional cert fetch + compose
    docker-compose.tftpl                    # NEW — TLS mode compose template

deployments/
  aws-ecs-fargate/
    main.tf                                 #   Conditional stunnel container in task def
    tls.tf                                  # NEW — calls tls-certs module
    aviatrix-syslog.tf                      # NEW — optional, removable
    nlb.tf                                  #   Conditional 6514 vs 5000
    security-groups.tf                      #   Conditional port rules

  aws-ec2-single-instance/
    main.tf                                 #   Pass tls vars to shared module
    tls.tf                                  # NEW — calls tls-certs module
    aviatrix-syslog.tf                      # NEW — optional, removable

  aws-ec2-autoscale/
    main.tf                                 #   Pass tls vars to shared module
    tls.tf                                  # NEW — calls tls-certs module
    aviatrix-syslog.tf                      # NEW — optional, removable
```

Zero changes to `logstash-configs/` (inputs, filters, outputs, patterns).

## Security Considerations

- **mTLS enforced**: `verify = 2` — connections without a valid client cert signed by the CA are refused
- **Cert isolation**: Server private key stored in Secrets Manager with IAM access controls, never in Terraform outputs
- **CA key in state**: The CA private key lives in Terraform state only — state file must be secured (S3 backend + encryption recommended)
- **No plaintext exposure**: When TLS is enabled, port 5000 is not exposed externally; only reachable on localhost between containers
- **Rotation without downtime**: Server cert rotation updates the secret and restarts only the stunnel sidecar; Logstash continues processing buffered events

## Out of Scope

- **SPIRE / "Aviatrix (Default)" certificate mode**: Uses internal PKI with pinned SAN `topo.obs.aviatrix.com`. Can be added later by generating a server cert with that SAN.
- **Azure Key Vault / GCP Secret Manager**: Same sidecar image; only Terraform wiring differs. Add when Azure ACI or GCP deployments are needed.
- **Controller-aware management component**: Future feature for auto-rotation, ingress IP restriction, API enrichment. Current design is forward-compatible.
- **DTLS (UDP + TLS)**: RFC 5425 is TCP-only. Aviatrix only supports TLS over TCP.
