# Telemetry conventions

This page is the only thing every team must follow. Recipes find your data by these exact
names and tags. You can send the data any way you like (DogStatsD, OpenTelemetry, the
Datadog Agent), in any language.

## Do you need to write any code?

| You want | Code needed? |
|---|---|
| Request availability or latency | No. Turn on Datadog APM; Datadog names these metrics itself. |
| Database, queue, ECS or other AWS signals | No. Datadog's AWS integration already collects them. |
| A metric you already send under another name | No. Use `recipe: custom` and point at it. |
| Job runs, data freshness, dependency calls, checks, coverage, deliveries, probes | Yes, a few lines. Emit the metric from the table below. |

New metrics should use these names, so every team's numbers line up.

## Required tags on every metric

| Tag | Value | Why |
|---|---|---|
| `service` | Same as `service` in your slo.yaml | Recipes filter on it |
| `env` | Same as `env` in your slo.yaml | Recipes filter on it |
| `version` | Your build or release version | Datadog unified service tagging; lets you compare releases |

APM and the Datadog Agent add these for you when `DD_SERVICE`, `DD_ENV` and `DD_VERSION`
are set.

## The metrics

Values in `outcome` are lowercase and exactly as written.

| Metric | Type | Extra tags | Emit when | Used by |
|---|---|---|---|---|
| `slo.job.runs` | count | `job`, `outcome:success\|failure` | A job run finishes | `job.availability` |
| `slo.freshness.age_seconds` | gauge, every 60s | `dataset` | Continuously, from a long-running process | `data.freshness` |
| `slo.dependency.calls` | count | `dependency`, `outcome:success\|failure` | Each outbound call completes | `dependency.availability` |
| `slo.dependency.duration` | distribution, seconds | `dependency` | Each outbound call completes | `dependency.latency` |
| `slo.delivery.events` | count | `destination`, `outcome:delivered\|failed\|dead_lettered` | A message or push reaches a final state | `queue.availability` |
| `slo.delivery.duration` | distribution, seconds | `destination` | A message is delivered (enqueue to delivery) | `queue.latency` |
| `slo.check.results` | count | `check`, `outcome:passed\|failed\|not_performed` | A check is due, whether or not it could run | `checks.correctness`, `checks.durability` |
| `slo.coverage.expected` | count | `dataset` | You learn how many records exist upstream | `data.coverage` |
| `slo.coverage.processed` | count | `dataset` | Records are processed | `data.coverage` |
| `slo.probe.results` | count | `target`, `outcome:success\|failure` | Each probe completes | `network.availability` |
| `slo.probe.duration` | distribution, seconds | `target` | Each probe completes | `network.latency` |
| `slo.storage.ops` | count | `volume`, `outcome:success\|failure` | Each read or write completes | `storage.availability` |

### Rules that keep the numbers honest

- **Freshness comes from a process that keeps running.** Compute `slo.freshness.age_seconds`
  from your sync-state table (now minus last successful sync) in the server or worker, not
  in the job. If it came from the job, a dead job would simply stop reporting.
- **A check that could not run is `not_performed`.** Never `passed`, never skipped.
- **Coverage counts expected records from the source**, not from what you happened to fetch.
- **Durations are seconds.** Thresholds in slo.yaml are in seconds too.

## Cardinality rule

Tag values must come from a small, fixed set. Never use a user ID, request ID, ticket
number, timestamp, URL with IDs in it, or error message as a tag. Datadog bills custom
metrics by the number of distinct tag combinations, so one unbounded tag can multiply the
bill, and it makes the SLO queries slow.

`job`, `dataset`, `dependency`, `check`, `destination`, `target` and `volume` are names
you choose once and keep. Use lowercase with hyphens: `jira-hydrator`, not `JiraHydrator_v2`.

## Examples

**Node (dd-trace):**

```js
const tracer = require('dd-trace').init();   // DD_SERVICE, DD_ENV, DD_VERSION set in the task

tracer.dogstatsd.increment('slo.job.runs', 1, { job: 'jira-hydrator', outcome: 'success' });
tracer.dogstatsd.gauge('slo.freshness.age_seconds', ageSeconds, { dataset: 'jira-incidents' });
tracer.dogstatsd.distribution('slo.dependency.duration', seconds, { dependency: 'jira' });
```

**Python (datadog package):**

```python
from datadog import statsd   # DD_SERVICE, DD_ENV, DD_VERSION set in the task

statsd.increment("slo.check.results", tags=["check:jira-reconciliation", "outcome:not_performed"])
statsd.distribution("slo.dependency.duration", seconds, tags=["dependency:jira"])
```

**Java, C++, anything else:** any DogStatsD client, or an OpenTelemetry metrics exporter
to the Datadog Agent. Only the names and tags above matter.

## Finding your APM operation name

APM recipes need `operation`, the span name for incoming requests (for example
`express.request`, `http.request`, `fastapi.request`). Open the service in Datadog APM;
the operation is shown at the top of the service page.
