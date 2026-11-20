# Sources

What this repo is built on, and which parts are our own design. Anything in the catalog,
module or docs that depends on how an outside system behaves should trace to a row here,
or be listed as unverified in [plan.md](plan.md#open-items-unverified-assumptions).

Last reviewed: 2026-11-19.

## What is industry standard and what is ours

| Part | Standard or ours | Basis |
|---|---|---|
| SLI = good events ÷ valid events | Standard | SRE Book ch. 4; SRE Workbook, "Implementing SLOs" |
| The SLI types (availability, latency, quality, freshness, correctness, coverage, throughput, durability) | Standard | SRE Workbook, "Implementing SLOs" (SLI menu by system type) |
| SLO = SLI + target + window; error budget = 100% − target | Standard | SRE Book ch. 4 |
| Multi-window, multi-burn-rate alerting | Standard | SRE Workbook, "Alerting on SLOs" |
| Written error-budget policy | Standard | SRE Workbook, appendix "Example Error Budget Policy" |
| SLOs kept as code in version control | Common practice | Thoughtworks Technology Radar; OpenSLO; Sloth |
| SLO definitions in YAML, applied by a Terraform module from a catalog | Common practice | Cloud Posse `terraform-datadog-platform` (closest prior art) |
| Recipe format, `slo.yaml` schema, the menu grid, observe/live/none, repo layout | Ours | Designed for this repo; see [decisions.md](decisions.md) |
| Burn-rate tiers expressed as share of budget spent, scaled to the window | Ours, derived from standard | Workbook tiers, re-expressed so 7d/90d windows work |

## Standards

| Source | What we use it for | Link |
|---|---|---|
| Google, *Site Reliability Engineering*, ch. 4 "Service Level Objectives" | Definitions of SLI, SLO, error budget | https://sre.google/sre-book/service-level-objectives/ |
| Google, *The Site Reliability Workbook*, "Implementing SLOs" | SLI menu by system type; specification vs implementation; starting targets from measured data | https://sre.google/workbook/implementing-slos/ |
| Google, *The Site Reliability Workbook*, "Alerting on SLOs" | Burn-rate tiers (14.4x/1h, 6x/6h, 3x/1d, 1x/3d for 30 days) and the two-window pattern | https://sre.google/workbook/alerting-on-slos/ |
| Google, *The Site Reliability Workbook*, "Example Error Budget Policy" | Structure of [error-budget-policy.md](error-budget-policy.md) | https://sre.google/workbook/error-budget-policy/ |
| OpenSLO specification | Vendor-neutral SLO-as-code format; shape reference for `slo.yaml` | https://github.com/OpenSLO/OpenSLO |
| Thoughtworks Technology Radar, "SLIs and SLOs as code" | Industry endorsement of the approach | https://thoughtworks.com/radar/techniques/slis-and-slos-as-code |

## Datadog

| Source | What we use it for | Link |
|---|---|---|
| Service Level Objectives (overview) | SLO types: metric-based, monitor-based, time-slice | https://docs.datadoghq.com/service_level_objectives/ |
| Time Slice SLOs | Good-minutes SLOs for latency, freshness and low-traffic services | https://docs.datadoghq.com/service_level_objectives/time_slice/ |
| SLO alert monitors | Burn-rate and error-budget alerts; which SLO types support them | https://docs.datadoghq.com/monitors/types/slo/ |
| Error budget alerts | `error_budget(...)` query form; Terraform `slo alert` monitors | https://docs.datadoghq.com/service_level_objectives/error_budget |
| Software Catalog, entity model v3 | Entity kinds (service, datastore, queue, system, api); planned catalog entries | https://docs.datadoghq.com/internal_developer_portal/software_catalog/entity_model/entity_types |
| Unified service tagging | Why `service`, `env`, `version` are the required tags | https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging/ |
| Trace metrics | `trace.<operation>.hits` / `.errors` / latency distribution names used by APM recipes | https://docs.datadoghq.com/tracing/metrics/metrics_namespace/ |
| Custom metrics billing | Why the cardinality rule in [conventions.md](conventions.md) exists | https://docs.datadoghq.com/account_management/billing/custom_metrics/ |

## Terraform

| Source | What we use it for | Link |
|---|---|---|
| Datadog provider: `datadog_service_level_objective` | Metric and time-slice SLO resource shape | https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/service_level_objective |
| Datadog provider: `datadog_monitor` | `slo alert` burn-rate monitors; no-data heartbeat monitors | https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/monitor |
| Terraform `test` and `mock_provider` | Module tests without Datadog credentials | https://developer.hashicorp.com/terraform/language/tests |

## Prior art we looked at

| Project | Take from it | Not taking | Link |
|---|---|---|---|
| Cloud Posse `terraform-datadog-platform` (`slo` submodule) | YAML catalog read directly by a Terraform module; metric and monitor SLOs | Its Atmos-based stack layout | https://github.com/cloudposse/terraform-datadog-platform |
| Google `slo-generator` | Kubernetes-style YAML SLO shape; Datadog backend exists | Computing SLOs outside Datadog (we use Datadog's native SLOs) | https://github.com/google/slo-generator |
| Sloth | Uniform SLO specs, multi-window burn-rate generation, OpenSLO support | Prometheus as the backend | https://github.com/slok/sloth |
