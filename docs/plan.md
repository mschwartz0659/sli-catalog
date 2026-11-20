# Plan of record

Every PR names the item it implements, or says `off-plan:` with one line of why and adds
the item here in the same PR.

## Phase 0 — scaffold (done: v0.1.0 candidate)

- [x] P0.1 Recipe catalog (18 recipes, all `draft`), schema v1, starter template
- [x] P0.2 Terraform module `modules/datadog-slo` with `terraform test` suite (mock provider)
- [x] P0.3 `scripts/sli.py`: validate, render, catalog lint, catalog doc, self-test
- [x] P0.4 CI for this repo; reusable `validate-slo` workflow for teams; registry root
- [x] P0.5 README, CLAUDE.md, docs (sources, decisions, conventions, tenets, policy, registry)
- [ ] P0.6 First CI run green on GitHub (Terraform has not been run yet; see open items)
- [ ] P0.7 Tag `v0.1.0`

## Phase 1 — pilot on one app

- [ ] P1.1 Datadog service account for Terraform; API/app keys in a TFE variable set (`DD_API_KEY`, `DD_APP_KEY`, `DD_HOST`)
- [ ] P1.2 Confirm the Datadog PagerDuty integration has a service for the pilot, and its exact name
- [ ] P1.3 Pick the pilot app; turn on APM; find its real operation names
- [ ] P1.4 Add the convention metrics the pilot needs (`slo.freshness.age_seconds`, `slo.job.runs`)
- [ ] P1.5 Apply in `observe`; check each SLO's numbers in Datadog by hand
- [ ] P1.6 Mark `request.availability`, `request.latency`, `data.freshness`, `job.availability` as `verified` (or fix them)
- [ ] P1.7 After two weeks: set targets from observed data, switch to `live`, test one page end to end

## Phase 2 — second app and a second language

- [ ] P2.1 Onboard the Python MCP; verify `dependency.*` recipes
- [ ] P2.2 Agree the error-budget policy with stakeholders; remove its draft marker
- [ ] P2.3 Decide whether to publish the module in the TFE private registry (see open items)

## Phase 3 — beyond our apps

- [ ] P3.1 One infra team in registry mode; verify an integration recipe (`datastore.aurora_replica_lag` or `queue.sqs_freshness`)
- [ ] P3.2 Generate Datadog Software Catalog entries (`kind`, owner, PagerDuty, links) from slo.yaml
- [ ] P3.3 Recipe for Datadog Synthetics network tests
- [ ] P3.4 Optional helper libraries (Node, Python) that emit the convention metrics

## Open items (unverified assumptions)

Each is something the design relies on that has not been checked against our Datadog org
or tooling. Close one by checking it, then update the recipe/module and add a decisions row.

| # | Assumption | Where it matters | How to check |
|---|---|---|---|
| U1 | Terraform module plans cleanly (written without a local terraform binary) | everything | P0.6 CI run |
| U2 | Datadog metric SLO numerators accept `a - b` arithmetic | `request.availability`, `datastore.availability` | Apply in observe (P1.5) |
| U3 | Time-slice SLOs accept multi-query formulas such as `1 - query1 / query2` | time-slice modes with two queries | Apply in observe |
| U4 | Burn-rate long window of 24h is allowed; 72h may not be | burn tiers | Datadog docs / apply |
| U5 | How time-slice SLOs treat minutes with no data | `data.freshness` (heartbeat added as a guard) | Datadog docs / test |
| U6 | APM trace metric names per tracer (`trace.<op>.hits`, `.errors`, `trace.<op>` distribution with percentiles) | APM recipes | Pilot (P1.3) |
| U7 | AWS integration names: `aws.rds.aurora_replica_lag` (ms, `dbclusteridentifier`), `aws.sqs.approximate_age_of_oldest_message` (`queuename`), `aws.ecs.service.running/desired` (`clustername`, `servicename`) | integration recipes | Metrics explorer in our org |
| U8 | Current Datadog provider version supports `sli_specification.time_slice` with our block layout | module | U1 + apply |
| U9 | TFE private registry can publish a module from a subdirectory of this repo | module distribution | TFE admin / docs |
| U10 | Teams' TFE workspaces can fetch this repo over git (VCS credentials) | module source | Pilot |
