| Date | Decision | Who | Why |
|------|----------|-----|-----|
| 2026-11-19 | Repo named sli-catalog. It holds SLI recipes and tooling; SLOs (targets) live in each team's slo.yaml. | owner | "SLO repo" is not a standard term; the shared part is the SLI specification. |
| 2026-11-19 | Datadog is the only backend; alerts reach PagerDuty through Datadog @pagerduty handles. | owner | Datadog is the org-wide platform. Prometheus/Grafana and CloudWatch are out of scope. |
| 2026-11-19 | No generator: the Terraform module reads slo.yaml directly (Cloud Posse pattern). | owner | One fewer artifact to drift or forget to regenerate. |
| 2026-11-19 | Trunk-based: main is the only long-lived branch; short-lived branches merge to main by PR. Releases are semver tags. | owner | Single small team; teams consume pinned tags, not a branch. |
| 2026-11-19 | Burn tiers: page 14.4x at 1h/5m and 6x at 6h/30m; ticket 3x at 24h/2h (30d). Workbook's 1x at 3d/6h tier dropped. | owner | 1x adds little over the ticket tier; 72h long window may exceed Datadog's limit (open item). |
| 2026-11-19 | Tiers are defined as share of budget spent (2%/5%/10%) and scaled to the window; tiers at <=1x are skipped. | owner | Keeps 7d and 90d windows meaningful instead of reusing 30d multipliers. |
| 2026-11-19 | Latency recipes are time-slice (good minutes under threshold), not good-request counts. | owner | APM latency is a distribution, giving per-minute percentiles, not counts under a threshold. |
| 2026-11-19 | New SLOs default to alerting: observe (monitors exist, notify no one) until the team switches to live. | owner | Workbook: set targets from measured data. Two weeks of observation before paging anyone. |
| 2026-11-19 | Alerting values are observe/live/none, not off. | owner | YAML 1.1 parsers read a bare off as false, so off would break some tools silently. |
| 2026-11-19 | All thresholds are in the metric's own unit (seconds by default); recipes do no unit conversion. | owner | The module's renderer substitutes text only; arithmetic would need templatestring (TF 1.9+) and hides units. |
| 2026-11-19 | data.freshness adds a no-data heartbeat monitor. | owner | A stopped job stops reporting, and silence must not read as fresh. Datadog's no-data handling in time-slice SLOs is an open item. |
| 2026-11-19 | All recipes start as status: draft and become verified only after checking against real data in our org. | owner | Metric and tag names from docs and memory are assumptions until seen in our Datadog. |
| 2026-11-19 | Validation runs twice: sli.py in CI for fast feedback, module preconditions at plan as the authority. | owner | Teams without the reusable workflow still get the checks; one authority avoids drift. |
