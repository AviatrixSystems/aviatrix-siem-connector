# Status Sidecar — Deployment Integration

This document covers what needs to happen to deploy the status sidecar alongside Logstash in each deployment target.

## How the Sidecar Works

The sidecar is a Next.js standalone app (port 3000) that polls the Logstash monitoring API (`/_node/stats`, `/_node`, `/_node/hot_threads`) and serves a dashboard + API. It needs two things from Logstash:

| Dependency | How | Used For |
|---|---|---|
| Monitoring API | HTTP to `LOGSTASH_API_URL` (default `localhost:9600`) | Stats, health, hot threads, plugin metrics |
| Log file | Read from `LOGSTASH_LOG_PATH` (default `/var/log/logstash/logstash-plain.log`) | Download Logs button, support bundle |

## Sidecar Environment Variables

| Variable | Default | Description |
|---|---|---|
| `LOGSTASH_API_URL` | `http://localhost:9600` | Logstash monitoring API base URL |
| `LOGSTASH_LOG_PATH` | `/var/log/logstash/logstash-plain.log` | Path to Logstash log file (shared volume) |
| `LOG_PROFILE` | `all` | Which log types are forwarded (`all`, `security`, `networking`) — display only |
| `PORT` | `3000` | Port the sidecar listens on |

## Sidecar API Endpoints

| Endpoint | Purpose | Use as health check? |
|---|---|---|
| `GET /api/health` | Returns `{"status":"healthy\|degraded\|unhealthy","reasons":[...]}`. **200** if healthy/degraded, **503** if unhealthy. | Yes — use for LB health checks |
| `GET /api/stats` | Full metrics snapshot (pipeline, JVM, log types, config) | No |
| `GET /api/history?range=1h` | Time-series deltas. Range: `1h`, `6h`, `12h`, `24h` | No |
| `GET /api/logs?lines=1000&download=true` | Logstash log file tail | No |
| `GET /api/hot-threads` | Proxies `/_node/hot_threads` from Logstash | No |
| `GET /api/support-bundle` | Downloads `.tar.gz` diagnostic bundle | No |

## Docker Image

The sidecar image is built from `status-sidecar/Dockerfile` (multi-stage, `node:20-alpine`, ~150MB). It runs as non-root (uid 1001).

```bash
# Build
cd status-sidecar
docker build -t aviatrix-sidecar:latest .

# Push to registry (examples)
docker tag aviatrix-sidecar:latest <account>.dkr.ecr.<region>.amazonaws.com/aviatrix-sidecar:latest
docker push <account>.dkr.ecr.<region>.amazonaws.com/aviatrix-sidecar:latest

# Or ACR
docker tag aviatrix-sidecar:latest <registry>.azurecr.io/aviatrix-sidecar:latest
docker push <registry>.azurecr.io/aviatrix-sidecar:latest
```

### Image registry

The sidecar image needs to be published to a container registry accessible by the deployment target. Options:

- **AWS**: ECR (private), or public Docker Hub / GHCR
- **Azure**: ACR (the Azure deployments already use a custom registry for the Sentinel plugin image)

A CI step should build and push on tagged releases.

---

## Logstash Container Changes (All Platforms)

The Logstash container needs two changes regardless of platform:

### 1. Enable file logging

The Logstash Docker image only logs to stdout by default. The sidecar reads logs from a file. Add `--path.logs` to the Logstash command:

```
logstash -f /config/pipeline.conf --path.logs /var/log/logstash
```

This writes `logstash-plain.log` to the specified directory.

### 2. Expose the monitoring API

The Logstash monitoring API listens on port 9600 by default. When the sidecar runs in a separate container on the same host, this port must be reachable. Options:

- **Same Docker network**: Both containers on a shared network. Sidecar accesses `http://logstash:9600`.
- **Host port mapping**: Logstash maps `-p 9600:9600`. Sidecar accesses `http://localhost:9600` or `http://host.docker.internal:9600`.
- **Same container group** (Azure ACI): Containers share localhost. No port mapping needed.

### 3. Shared log volume

Mount a shared directory between both containers for log file access:

```
-v /var/log/logstash:/var/log/logstash
```

Both containers mount the same host path (AWS) or emptyDir/file share (Azure ACI).

---

## AWS EC2 Single Instance

### Current state

- `logstash_instance_init.tftpl` bootstraps the instance (installs Docker, downloads config from S3)
- Output-specific `docker_run.tftpl` runs Logstash as a single container
- Security group opens port 5000 (syslog) + 22 (SSH)

### Changes needed

**1. Security group — add port 3000**

In `deployments/modules/aws-logstash/main.tf`, add an ingress rule:

```hcl
variable "sidecar_port" {
  description = "Status sidecar dashboard port"
  type        = number
  default     = 3000
}

# In aws_security_group.default:
ingress {
  from_port   = var.sidecar_port
  to_port     = var.sidecar_port
  protocol    = "TCP"
  cidr_blocks = ["0.0.0.0/0"]  # Or restrict to operator subnet
}
```

**2. Init script — create shared log directory**

In `logstash_instance_init.tftpl`, add:

```bash
mkdir -p /var/log/logstash
```

**3. Docker run templates — add `--path.logs` and log volume**

Each `docker_run.tftpl` needs:
- `-v /var/log/logstash:/var/log/logstash` volume mount
- `--path.logs /var/log/logstash` appended to the Logstash command (or as a command override)
- Expose port 9600: `-p 9600:9600`

Example for `outputs/splunk-hec/docker_run.tftpl`:

```bash
# Logstash container
sudo docker run -d --restart=always --name logstash \
  -v /logstash/pipeline/:/usr/share/logstash/pipeline/ \
  -v /logstash/patterns:/usr/share/logstash/patterns \
  -v /var/log/logstash:/var/log/logstash \
  -e LOG_PROFILE=${log_profile} \
  -e SPLUNK_HEC_AUTH=${splunk_hec_auth} \
  -e SPLUNK_ADDRESS=${splunk_address} \
  -e SPLUNK_PORT=${splunk_port} \
  -e FLATTEN_SURICATA=true \
  -e XPACK_MONITORING_ENABLED=false \
  -p 5000:5000 \
  -p 9600:9600 \
  docker.elastic.co/logstash/logstash:8.16.2 \
  logstash -f /usr/share/logstash/pipeline/ --path.logs /var/log/logstash

# Status sidecar
sudo docker run -d --restart=always --name sidecar \
  -v /var/log/logstash:/var/log/logstash \
  -e LOGSTASH_API_URL=http://host.docker.internal:9600 \
  -e LOG_PROFILE=${log_profile} \
  -p 3000:3000 \
  ${sidecar_image}
```

> **Note on networking**: On Linux EC2, `host.docker.internal` may not resolve. Alternatives:
> - Use `--network host` for the sidecar (simplest on Linux)
> - Use `--add-host host.docker.internal:host-gateway`
> - Create a Docker network and use container names

**4. Template variable for sidecar image**

Add to the shared module's variables:

```hcl
variable "sidecar_image" {
  description = "Docker image URI for the status sidecar"
  type        = string
  default     = ""  # Empty = sidecar disabled
}
```

Pass through to the docker_run template. When empty, skip the sidecar `docker run` block.

**5. Terraform data trigger for sidecar updates**

The existing `replace_triggered_by` pattern (S3 ETag → `terraform_data` → instance refresh) should also trigger on sidecar image changes, so updating the sidecar image rolls the instance.

---

## AWS EC2 Autoscale

Same changes as single-instance, plus:

**1. NLB target group for sidecar health**

The current NLB health check targets port 5000 (syslog TCP). Consider adding a second target group for port 3000 with HTTP health check:

```hcl
resource "aws_lb_target_group" "sidecar" {
  name     = "avxlog-sidecar-${module.logstash.random_suffix}"
  port     = 3000
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    protocol = "HTTP"
    path     = "/api/health"
    port     = 3000
  }
}
```

This gives the ASG a real application-level health check: if Logstash is unhealthy (stuck pipeline, API unreachable), the sidecar reports 503, and the ASG can replace the instance.

**2. NLB listener for dashboard access**

If operators need to reach the dashboard through the NLB (instead of direct instance IP):

```hcl
resource "aws_lb_listener" "sidecar" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 3000
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sidecar.arn
  }
}
```

> **Consideration**: With multiple instances behind an NLB, each sidecar only monitors its own Logstash. The dashboard shows per-instance metrics, not aggregated. The NLB will route to one random instance. This is fine for troubleshooting but doesn't give a fleet-wide view.

---

## Azure ACI

### Current state

- Single `container` block in `azurerm_container_group.logstash`
- Azure File Shares for config and patterns (mounted as volumes)
- Containers in an ACI group share localhost networking

### Changes needed

**1. Add sidecar container block**

In `deployments/azure-aci/module/ai/0-main.tf`, add a second `container` block inside the `azurerm_container_group` resource:

```hcl
  container {
    name   = "status-sidecar"
    image  = var.sidecar_image
    cpu    = 0.5
    memory = 0.5

    ports {
      port     = 3000
      protocol = "TCP"
    }

    environment_variables = {
      LOGSTASH_API_URL   = "http://localhost:9600"
      LOGSTASH_LOG_PATH  = "/var/log/logstash/logstash-plain.log"
      LOG_PROFILE        = lookup(var.environment_variables, "LOG_PROFILE", "all")
    }

    volume {
      name       = "logstash-logs"
      mount_path = "/var/log/logstash"
      empty_dir  = true   # Shared tmpfs between containers in the group
    }
  }
```

**2. Add matching log volume to Logstash container**

Add a volume mount to the existing Logstash container block:

```hcl
    volume {
      name       = "logstash-logs"
      mount_path = "/var/log/logstash"
      empty_dir  = true
    }
```

And update the Logstash command to write logs there (via `command` override or environment variable).

**3. Expose port 3000**

ACI container groups already get a public IP. Add port 3000 to the exposed ports, or add a second `ports` block in the container group:

```hcl
  exposed_port {
    port     = 3000
    protocol = "TCP"
  }
```

**4. Variables**

```hcl
variable "sidecar_image" {
  description = "Docker image URI for the status sidecar (e.g. your-registry.azurecr.io/aviatrix-sidecar:1.0.0)"
  type        = string
  default     = ""
}

variable "sidecar_enabled" {
  description = "Whether to deploy the status sidecar"
  type        = bool
  default     = true
}
```

**5. ACI networking note**

Containers in an ACI container group share `localhost`. The sidecar reaches Logstash at `http://localhost:9600` with no port mapping or networking config needed. This is the simplest deployment.

---

## CI / Image Build

The sidecar image should be built and pushed as part of the release process.

### Suggested workflow

```
on push to main (or tag):
  1. cd status-sidecar
  2. docker build -t aviatrix-sidecar:$TAG .
  3. docker push to ECR/ACR/GHCR
  4. Update Terraform variable default or tfvars with new image tag
```

### Versioning

The sidecar version should track the engine version. Logstash config changes don't affect the sidecar (it discovers plugins dynamically), but sidecar code changes need a new image.

---

## Resource Sizing

The sidecar is lightweight:

| Resource | Recommended | Notes |
|---|---|---|
| CPU | 0.25–0.5 vCPU | Node.js single-threaded, mostly idle between polls |
| Memory | 256–512 MB | Next.js standalone + 720-sample circular buffer |
| Disk | Negligible | No persistent storage; reads Logstash log from shared volume |

For AWS EC2, the sidecar overhead is minimal on any `t3.small` or larger instance. For Azure ACI, add 0.5 CPU + 0.5 GB to the container group.

---

## Checklist

### Code changes

- [ ] Add `sidecar_image` variable to `deployments/modules/aws-logstash/variables.tf`
- [ ] Add port 3000 ingress rule to security group in `deployments/modules/aws-logstash/main.tf`
- [ ] Add `/var/log/logstash` directory creation to `logstash_instance_init.tftpl`
- [ ] Update each `docker_run.tftpl` (5 files) to:
  - [ ] Add `--path.logs /var/log/logstash` to Logstash command
  - [ ] Add `-v /var/log/logstash:/var/log/logstash` volume mount
  - [ ] Add `-p 9600:9600` port mapping
  - [ ] Add sidecar `docker run` block (conditional on `sidecar_image` being set)
- [ ] Update Azure ACI `0-main.tf` to add sidecar container block + shared log volume
- [ ] Add `sidecar_image` variable to root modules (`aws-ec2-single-instance`, `aws-ec2-autoscale`, `azure-aci`)
- [ ] Pass `sidecar_image` through to docker_run templates / ACI module

### CI / Registry

- [ ] Set up container registry (ECR, ACR, or GHCR)
- [ ] Add CI step to build + push `status-sidecar/Dockerfile`
- [ ] Tag images with version or git SHA

### Testing

- [ ] Test with `docker-compose.dev.yml` (already works)
- [ ] Test single-instance AWS deployment with sidecar
- [ ] Verify `/api/health` returns 200 after Logstash starts
- [ ] Verify "Download Logs" returns Logstash log content from shared volume
- [ ] Verify "Support Bundle" includes `logstash.log` with real data
- [ ] Verify dashboard shows log type breakdown with correct plugin mapping
- [ ] Test autoscale: verify sidecar health check drives instance replacement on Logstash failure
