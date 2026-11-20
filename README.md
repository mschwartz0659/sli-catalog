# sli-catalog

A shared menu of reliability measurements (SLIs), and the tooling that turns a team's
choices into Datadog SLOs and PagerDuty alerts.

You write one file, `slo.yaml`, saying which measurements you want and what target you
promise. Your Terraform runs this repo's module, which creates the SLOs and burn-rate
alerts in Datadog and routes pages to your PagerDuty service. You never build SLOs or
alerts by hand.

**Status:** v0.1 — pilot. All recipes are `draft` until checked against real data
([plan](docs/plan.md)).

---

## Contents

- [The four words you need](#the-four-words-you-need)
- [How it works](#how-it-works)
- [Who does what](#who-does-what)
- [Quick start](#quick-start)
- [The menu](#the-menu)
- [slo.yaml reference](#sloyaml-reference)
- [Sending the data](#sending-the-data)
- [Alerts](#alerts)
- [Common questions](#common-questions)
- [Versions and upgrades](#versions-and-upgrades)
- [Contributing a recipe](#contributing-a-recipe)
- [Sources](#sources)

---

## The four words you need

| Word | Meaning | Example |
|---|---|---|
| **SLI** (indicator) | What you measure: good events divided by valid events. | Requests that didn't fail ÷ all requests. |
| **SLO** (objective) | An SLI plus a target over a time window. | 99.5% of requests succeed over 30 days. |
| **Error budget** | The failure the target allows: 100% minus the target. | 0.5% of requests over 30 days. |
| **Burn rate** | How fast you're spending the budget. 1x spends it exactly over the window. | 14.4x spends 2% of a 30-day budget in an hour. |

This repo is the **SLI catalog**: it defines what can be measured and how. Your
`slo.yaml` holds your **SLOs**: which of those you promise, and to what target.

## How it works

```
 your repo                          your Terraform workspace               Datadog              PagerDuty
┌───────────────┐   module reads   ┌──────────────────────────┐  creates  ┌──────────────┐ page ┌───────────┐
│ slo.yaml      │ ───────────────▶ │ module "slos" (from this │ ────────▶ │ SLOs         │ ───▶ │ your      │
│ (your picks + │                  │ repo, pinned to a tag)   │           │ burn-rate    │      │ service   │
│  targets)     │                  └──────────────────────────┘           │ monitors     │      └───────────┘
└───────────────┘                               ▲                         └──────────────┘
        │ PR check (optional)                   │ recipes
        ▼                                       │
 reusable workflow ── validates ──▶   catalog/recipes/*.yaml   ◀── this repo
```

1. You pick recipes from the [menu](docs/catalog.md) in your `slo.yaml` and set targets.
2. Your Terraform calls this repo's module and passes it the file.
3. On plan, the module checks the file against the catalog and shows exactly what it will create.
4. On apply, it creates the SLOs, burn-rate monitors and (where needed) heartbeat monitors in Datadog.
5. Alerts go to your PagerDuty service through Datadog's PagerDuty integration.

## Who does what

### The catalog owner (this repo)

| Provides | Where |
|---|---|
| The menu of SLI recipes | [`catalog/recipes/`](catalog/recipes), summarised in [docs/catalog.md](docs/catalog.md) |
| Naming and tagging rules for your telemetry | [docs/conventions.md](docs/conventions.md) |
| The schema that checks your slo.yaml | [`schema/slo.v1.schema.json`](schema/slo.v1.schema.json) |
| A starter slo.yaml | [`templates/slo.yaml`](templates/slo.yaml) |
| The Terraform module | [`modules/datadog-slo/`](modules/datadog-slo) |
| A reusable PR-check workflow | [`.github/workflows/validate-slo.yml`](.github/workflows/validate-slo.yml) |
| A home for teams without Terraform | [`registry/`](registry), see [docs/registry.md](docs/registry.md) |
| The error-budget policy | [docs/error-budget-policy.md](docs/error-budget-policy.md) |

### Your team

| Where | What you do |
|---|---|
| **Code** | Make sure your service reports to Datadog. For requests, turning on APM is usually enough. Add a few lines only for what Datadog can't see itself: job runs, data freshness, dependency calls, checks. See [Sending the data](#sending-the-data). |
| **Repo** | Add `slo.yaml` at the root. Start from the template, delete what doesn't apply, fill in params and targets. |
| **Terraform** | Add one `module` block to your existing workspace (below). Your workspace needs the Datadog provider credentials. |
| **CI** | Optional: add the reusable workflow so PRs that touch slo.yaml get checked and show what will be created. |
| **Datadog** | Nothing by hand. Check that the numbers look right after the first apply. |
| **PagerDuty** | Have a service with an on-call schedule, connected in Datadog's PagerDuty integration. Put its name in `routing.page`. |
| **Process** | Run in `observe` for about two weeks. Set targets from what you see. Switch to `live`. Review targets every quarter. Follow the [error-budget policy](docs/error-budget-policy.md). |

## Quick start

**1. Copy the starter file** ([`templates/slo.yaml`](templates/slo.yaml)) to the root of
your repo, by hand or with:

```bash
curl -fsSLo slo.yaml https://raw.githubusercontent.com/mschwartz0659/sli-catalog/v0.1.0/templates/slo.yaml
```

**2. Edit it.** Fill in `service`, `env`, `team`, `routing.page`. Delete the SLOs you don't
need. Fill in each remaining SLO's `params` and `target`. Leave `alerting: observe`.

**3. Check it locally** (optional but quick):

```bash
git clone --depth 1 --branch v0.1.0 https://github.com/mschwartz0659/sli-catalog.git /tmp/sli-catalog
pip install -r /tmp/sli-catalog/scripts/requirements.txt
python3 /tmp/sli-catalog/scripts/sli.py validate slo.yaml --render
```

`--render` prints every Datadog query that will be created, so you can paste them into
Datadog's metrics explorer and confirm they return data before you apply.

**4. Add the module** to your Terraform:

```hcl
module "slos" {
  source = "git::https://github.com/mschwartz0659/sli-catalog.git//modules/datadog-slo?ref=v0.1.0"

  slo_file    = "${path.root}/slo.yaml"
  source_repo = "https://github.com/<your-org>/<your-repo>"
}
```

Your workspace needs the Datadog provider. Its credentials come from environment
variables in the workspace (a shared variable set), never from code: `DD_API_KEY`,
`DD_APP_KEY`, and `DD_HOST` for your Datadog site. See
[examples/example-dashboard](examples/example-dashboard).

**5. Open a PR.** Your workspace's plan lists the SLOs and monitors it will create.
Merge and apply.

**6. Optional: add the PR check.** Create `.github/workflows/slo.yml`:

```yaml
name: slo
on:
  pull_request:
    paths: [slo.yaml]
jobs:
  validate:
    uses: mschwartz0659/sli-catalog/.github/workflows/validate-slo.yml@v0.1.0
    with:
      catalog-ref: v0.1.0
```

**7. After two weeks**, look at each SLO in Datadog, set targets just below what you
actually achieve, change `alerting` to `live`, and merge.

## The menu

Each recipe belongs to one of eight SLI types, from the SRE Workbook:
**availability, latency, quality, freshness, correctness, coverage, throughput, durability**.
What each means and how to pick: [docs/tenets.md](docs/tenets.md).

The full menu, with every param: **[docs/catalog.md](docs/catalog.md)**. The most used:

| Recipe | Type | Measures | Needs |
|---|---|---|---|
| `request.availability` | availability | Requests that didn't fail ÷ all requests | APM |
| `request.latency` | latency | Minutes with p95 latency under threshold ÷ all minutes | APM |
| `data.freshness` | freshness | Minutes the data was younger than the limit ÷ all minutes | `slo.freshness.age_seconds` |
| `job.availability` | availability | Job runs that succeeded ÷ all runs | `slo.job.runs` |
| `dependency.availability` | availability | Calls to a dependency that succeeded ÷ all calls | `slo.dependency.calls` |
| `checks.correctness` | correctness | Correctness checks that passed ÷ all due | `slo.check.results` |
| `datastore.aurora_replica_lag` | freshness | Minutes Aurora replica lag was under the limit ÷ all minutes | AWS integration |

Nothing on the menu fits? Use `recipe: custom` (below), and consider
[contributing a recipe](#contributing-a-recipe).

## slo.yaml reference

### Top level

| Field | Required | Default | Meaning |
|---|---|---|---|
| `apiVersion` | yes | | Always `sli-catalog/v1`. |
| `service` | yes | | Datadog `service` tag, exactly as your telemetry reports it. |
| `env` | yes | | Datadog `env` tag, e.g. `prod`. |
| `team` | yes | | Owning team. Added as a tag. |
| `routing.page` | yes | | PagerDuty service name as shown in Datadog's PagerDuty integration (no `@pagerduty-` prefix). |
| `routing.ticket` | no | `[]` | Datadog handles for lower-urgency alerts, e.g. `["@pagerduty-my-team-low"]`. Empty means ticket alerts notify no one. |
| `alerting` | no | `observe` | `observe`, `live` or `none`. See [Alerts](#alerts). |
| `window` | no | `30d` | `7d`, `30d` or `90d`. |
| `tier` | no | `3` | 1 (most critical) to 3. Added as a tag. |
| `kind` | no | `service` | `service`, `job`, `datastore`, `queue`, `network`, `storage`, `compute`, `system`. Added as a tag. |
| `description` | no | | What this is and who relies on it. |
| `links.runbook` | no | | Included in every alert. |
| `slos` | yes | | One or more SLOs (below). |

### Each SLO

| Field | Required | Meaning |
|---|---|---|
| `name` | yes | Lowercase, hyphens. Unique within the file. Don't rename it later: that deletes the SLO and its history. |
| `recipe` | yes | A recipe `id` from the menu, or `custom`. |
| `target` | yes | Percentage, e.g. `99.5`. |
| `warning` | no | A percentage above `target` where Datadog shows a warning. |
| `params` | depends | The recipe's params. Required ones are in bold in the menu. Values are letters, digits, `. _ : / -`, or numbers. |
| `mode` | no | `events` (count good events) or `time_slice` (count good minutes). Defaults to the recipe's default. Use `time_slice` for low-traffic services. |
| `alerting` | no | Overrides the top-level `alerting` for this SLO. |
| `description` | no | Shown on the SLO in Datadog. |

### Custom SLOs

For anything the menu doesn't cover. You still name the type, so it shows up in reports
with the rest:

```yaml
  - name: reconciliation
    recipe: custom
    category: correctness            # one of the eight types
    target: 99.9
    events:                          # or time_slice, not both
      numerator: "sum:my.reconciled{service:my-service,env:prod}.as_count()"
      denominator: "sum:my.ingested{service:my-service,env:prod}.as_count()"
```

A custom time-slice SLO:

```yaml
    time_slice:
      queries:
        query1: "p99:my.duration{service:my-service,env:prod}"
      formula: query1
      comparator: "<="               # >, >=, <, <=
      threshold: 3
      interval_seconds: 60           # 60 or 300
```

**Units:** thresholds use the metric's own unit. For every `slo.*` metric and every APM
duration that is seconds. Integration metrics say their unit in the param name
(`max_lag_ms`).

## Sending the data

Full rules and examples in [docs/conventions.md](docs/conventions.md). In short:

- **Requests:** turn on Datadog APM. No other code. Find your `operation` name on the
  service's APM page.
- **AWS resources** (Aurora, SQS, ECS): already collected by Datadog's AWS integration.
- **Jobs, freshness, dependencies, checks, deliveries:** emit the `slo.*` metric from the
  conventions table, in any language, with `service` and `env` tags.
- **Already sending something similar?** Point a `custom` SLO at it instead.

Two rules matter most: freshness is reported by a process that keeps running (so a dead
job shows up as stale), and a check that could not run is reported as `not_performed`,
never `passed`.

## Alerts

### Modes

| `alerting` | Monitors created? | Who is notified |
|---|---|---|
| `observe` (default) | Yes | No one. Use for the first two weeks while you calibrate targets. |
| `live` | Yes | Page alerts go to `routing.page`; ticket alerts go to `routing.ticket`. |
| `none` | No | No one. For SLOs you track but never alert on, such as a vendor dependency. |

### Burn-rate alerts

Each alerting SLO gets three monitors. They fire on how fast the error budget is being
spent, measured over a long window and confirmed over a short one so they stop quickly
once the problem is fixed. For the default 30-day window:

| Severity | Fires when | Long / short window | Budget spent in the long window |
|---|---|---|---|
| Page | Burning 14.4x | 1h / 5m | 2% |
| Page | Burning 6x | 6h / 30m | 5% |
| Ticket | Burning 3x | 24h / 2h | 10% |

For 7d and 90d windows the burn rates are recalculated to keep the same budget shares;
tiers that would fall to 1x or below are skipped.

### Heartbeat

`data.freshness` also creates a heartbeat monitor that pages when the freshness metric
stops reporting, because a job that has stopped can't report that it's stale.

## Common questions

**We already have our own Terraform.** Good. Add the module block to it. That's the
intended path.

**We already have SLOs in Datadog.** Keep them, or bring them under this module: recreate
them in slo.yaml and delete the old ones, or reference their metrics from a `custom` SLO.
SLOs created by this module are tagged `managed-by:sli-catalog`, so you can tell them apart.

**We don't use Terraform.** Use [registry mode](docs/registry.md): put your slo.yaml in
this repo under `registry/<your-team>/`, and the catalog owner's workspace applies it.

**Can I edit an SLO in the Datadog UI?** You can, but the next apply reverts it. Change
`slo.yaml` instead.

**Can I skip this module entirely?** Yes; nothing forces you to use it. You lose the shared
recipes, the consistent alerting, and the comparability with other teams.

**Our service isn't Node or Python.** The language doesn't matter. Recipes read Datadog
metrics; send them however you like. See [docs/conventions.md](docs/conventions.md).

**Our "service" is a database, network or storage.** Same file. Set `kind` and use the
`datastore.*`, `network.*`, `storage.*` or `checks.durability` recipes. Many need no code
because Datadog's integrations already collect the data.

**What creates the SLOs, exactly?** Your Terraform workspace, when it applies. This repo
only supplies the module and the recipes it reads.

**Why "minutes" for latency instead of requests?** Datadog's APM latency data gives
percentiles per minute, not a count of requests under a threshold, so latency SLOs count
good minutes. See [docs/decisions.md](docs/decisions.md).

## Versions and upgrades

- Releases are git tags: `v0.1.0`, `v0.2.0`, … Always pin a tag, both in the module
  `source` (`?ref=`) and in the reusable workflow (`@` and `catalog-ref`).
- **Recipes never change meaning within a major version.** A fix that would change what a
  recipe measures becomes a new recipe id; the old one is marked `deprecated`. So upgrading
  a minor version never silently moves your numbers.
- New recipes and new optional fields are minor releases. Breaking schema changes become
  `apiVersion: sli-catalog/v2`.

## Contributing a recipe

1. Branch from `main`.
2. Add `catalog/recipes/<area>.<what>.yaml`. Copy a similar recipe for the shape.
3. Run `python3 scripts/sli.py self-test` and `python3 scripts/sli.py catalog-doc`.
4. Open a PR to `main` with an example slo.yaml using it, and a link to where the metric
   names come from.
5. New recipes start as `draft`. They become `verified` once someone has checked the
   queries against real data in Datadog.

## Sources

What's industry standard here and what's our own design, with links:
[docs/sources.md](docs/sources.md). Why things are the way they are:
[docs/decisions.md](docs/decisions.md).
