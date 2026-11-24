# AWS Quickstart (ECS Fargate, pre-built image)

One-command deployment of the SIEM Connector on ECS Fargate behind an NLB, using the
pre-built image `ghcr.io/aviatrixsystems/aviatrix-siem-connector:<release-tag>`. Run it
from AWS CloudShell or any shell with AWS credentials (bash 3.2+, `curl`).

```bash
curl -fsSL https://github.com/AviatrixSystems/aviatrix-siem-connector/releases/latest/download/quickstart.sh | bash -s -- \
  --output-type splunk-hec \
  --vpc-id vpc-xxx --subnets subnet-aaa,subnet-bbb \
  --allowed-cidrs 203.0.113.10/32 \
  --splunk-address https://splunk.example.com \
  --splunk-hec-token xxx
```

Use `--help` for all options, `--plan` to preview, and `--destroy` to tear down.

## What it does

1. Installs Terraform to `~/.local/bin` if missing (zip checked against HashiCorp `SHA256SUMS`).
2. Resolves `--image-tag latest` to the concrete release tag, so re-runs roll out new releases.
3. Downloads `quickstart-aws.tar.gz` from that release into `~/<--name>` (default `~/avx-siem-connector`).
4. Writes `terraform.tfvars` (mode 600) and runs `terraform apply`.

The SIEM settings (`logstash_config_variables`) are stored in a Secrets Manager secret
(`avxlog-<suffix>-config`) and injected into the task as ECS secrets. The task sets
`SYSLOG_PORT`, `LS_JAVA_OPTS` (half of `memory`) and, for `splunk-hec`, `FLATTEN_SURICATA=true`.

## Notes

- `--splunk-address` must include the scheme (`https://`).
- Dynatrace URLs are the full ingest URLs:
  `https://<env>.apps.dynatrace.com/platform/classic/environment-api/v2/{metrics,logs}/ingest`.
  See [docs/DYNATRACE_SETUP.md](../../docs/DYNATRACE_SETUP.md).
- `--allowed-cidrs` sets `allowed_syslog_cidrs` (default `0.0.0.0/0`). Restrict it to your
  gateway/controller egress IPs.
- `azure-log-ingestion` is not supported here; use [deployments/azure-aci](../azure-aci/).
- To customize the image, use [deployments/aws-ecs-fargate](../aws-ecs-fargate/).

## Terraform variables

`aws_region`, `vpc_id`, `subnet_ids`, `output_type`, `image_tag`, `syslog_port` (5000),
`allowed_syslog_cidrs`, `log_profile` (`all`), `logstash_config_variables` (env-var names, e.g.
`SPLUNK_ADDRESS`), `internal_nlb` (false), `desired_count` (1), `cpu` (512), `memory` (1024), `tags`.
See [terraform.tfvars.example](terraform.tfvars.example) and [variables.tf](variables.tf).

Outputs: `syslog_endpoint`, `nlb_dns_name`, `ecs_cluster_name`, `ecs_service_name`, `cloudwatch_log_group`.
