# AWS ECS Fargate Deployment

Deploys the Aviatrix SIEM Connector on ECS Fargate behind an NLB. Supports any output type (`splunk-hec`, `zabbix`, `dynatrace`, etc.) via the `output_type` variable.

## Architecture

```
Aviatrix Gateways/Controllers
         │
         ▼ syslog (TCP+UDP)
    ┌──────────┐
    │   NLB    │ ← Public, dual-protocol listeners
    └────┬─────┘
         ▼
    ┌──────────┐
    │ Fargate  │ ← Logstash container (config baked into image)
    │  Tasks   │
    └────┬─────┘
         ▼
    SIEM / Observability
    (Splunk, Zabbix, Dynatrace, etc.)
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.3
- Docker (for building container images)
- A VPC with subnets that have internet access (public subnets, or private with NAT gateway)

## Deployment Workflow

### Phase 1: Create Infrastructure

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: vpc_id, subnet_ids, output_type, logstash_config_variables
# Leave container_image = "" for now

terraform init
terraform apply
```

This creates: ECR repository, NLB, IAM roles, security groups, CloudWatch log group, ECS cluster, and a Secrets Manager secret (`avxlog-<suffix>-config`) holding `logstash_config_variables`.
The ECS service is **not** created yet (no image to run).

`logstash_config_variables` keys are uppercased into container env names (e.g. `splunk_address` → `SPLUNK_ADDRESS`), except for `azure-log-ingestion`, whose lowercase names are kept. They are injected as ECS `secrets`, not plaintext `environment`. `splunk_address` must include `https://`. Dynatrace takes full URLs: `https://<env>.apps.dynatrace.com/platform/classic/environment-api/v2/{metrics,logs}/ingest`.

### Phase 2: Build and Push Container Image

```bash
# Use the build command from terraform output
./container-build/build-and-push.sh \
  --output-type splunk-hec \
  --ecr-repo $(terraform output -raw ecr_repository_url) \
  --region us-east-2
```

The build script:
1. Always re-assembles the Logstash config
2. Creates a build context with the config and patterns baked in
3. Installs any required plugins (e.g., `logstash-output-zabbix` for Zabbix)
4. Builds and pushes to ECR with a content-addressed tag, `cfg-<sha256 of the build context and plugin list>` (override with `--tag`), and prints the image URI

### Phase 3: Deploy ECS Service

```bash
# Update terraform.tfvars with the URI printed by build-and-push.sh:
#   container_image = "<ecr-url>:cfg-<hash>"
# Avoid mutable tags such as :latest; an unchanged URI does not redeploy.

terraform apply
```

### Phase 4: Verify

```bash
# Check service status
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw ecs_service_name) \
  --query 'services[0].{status:status,running:runningCount,desired:desiredCount}'

# Send test logs
cd ../../test-tools/sample-logs
./generate-current-samples.sh -o /tmp/samples-now.log
./stream-logs.py -f /tmp/samples-now.log --target $(cd ../../deployments/aws-ecs-fargate && terraform output -raw nlb_dns_name)
```

## Updating Configuration

Config is baked into the container image. To update:

1. Edit filters/outputs in `logstash-configs/`
2. Re-run `build-and-push.sh` (re-assembles and rebuilds automatically); a config change yields a new `cfg-<hash>` tag
3. Set `container_image` to the new URI and `terraform apply`; the new task definition rolls the service

Changing `logstash_config_variables` updates the secret and pins its new version in the task definition, which also triggers a rolling deploy.

## Output Types and Plugins

| Output Type | Extra Plugin |
|---|---|
| `splunk-hec` | None (stock Logstash); the task sets `FLATTEN_SURICATA=true` |
| `webhook-test` | None |
| `dynatrace` / `dynatrace-logs` / `dynatrace-metrics` | None |
| `zabbix` | `logstash-output-zabbix` |
| `azure-log-ingestion` | `microsoft-sentinel-log-analytics-logstash-output-plugin` |

## Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-2` | AWS region |
| `vpc_id` | (required) | VPC ID |
| `subnet_ids` | (required) | Subnet IDs for NLB and tasks |
| `output_type` | `splunk-hec` | Logstash output type |
| `container_image` | `""` | ECR image URI (empty = skip ECS service) |
| `syslog_port` | `5000` | Syslog listener port (passed as `SYSLOG_PORT`; the image's assembled config must honor it) |
| `allowed_syslog_cidrs` | `["0.0.0.0/0"]` | Syslog/TLS source CIDRs |
| `log_profile` | `all` | Log types: all, security, networking |
| `logstash_config_variables` | `{}` | SIEM credentials etc. (sensitive; stored in Secrets Manager, injected as ECS secrets) |
| `desired_count` | `1` | Number of Fargate tasks |
| `cpu` | `512` | Task CPU units (512 = 0.5 vCPU) |
| `memory` | `1024` | Task memory in MiB; `LS_JAVA_OPTS` heap is set to half |
| `assign_public_ip` | `true` | Public IP for tasks (needed for ECR pull without NAT/VPC endpoints) |
| `enable_container_insights` | `true` | ECS Container Insights |
| `tls_enabled`, `tls_port`, `tls_cert_validity_hours`, `tls_secret_name`, `tls_sidecar_image`, `tls_server_dns_names` | `false`, `6514`, ... | mTLS via a stunnel sidecar |
| `tags` | `{App = "avx-log-integration"}` | Resource tags |

## Troubleshooting

### Tasks not starting

Check CloudWatch Logs:
```bash
aws logs tail /ecs/$(terraform output -raw ecs_cluster_name) --follow

# A task that fails with ResourceInitializationError usually cannot read the
# avxlog-<suffix>-config secret (check the execution role and network path to Secrets Manager)
```

### Targets unhealthy

NLB health checks use TCP on the syslog port. Verify Logstash is listening:
```bash
# Check task status
aws ecs describe-tasks \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --tasks $(aws ecs list-tasks --cluster $(terraform output -raw ecs_cluster_name) --query 'taskArns[0]' --output text)

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --names $(terraform output -raw ecs_cluster_name) --query 'TargetGroups[0].TargetGroupArn' --output text)
```

### ECR login issues

```bash
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-2.amazonaws.com
```

## Cleanup

```bash
terraform destroy
```

ECR repository has `force_delete = true`, so images are cleaned up automatically.
