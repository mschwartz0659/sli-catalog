# The eight SLI types

Every SLO in this catalog belongs to one of these types, taken from the SRE Workbook's SLI
menu ([sources](sources.md)). Each is still "good events ÷ valid events"; the type says
what kind of promise it is.

| Type | The question a user would ask | Good event, typically | Recipes |
|---|---|---|---|
| **Availability** | "Does it work?" | A request, run or call that succeeded | `request.availability`, `job.availability`, `dependency.availability`, `queue.availability`, `datastore.availability`, `network.availability`, `storage.availability`, `compute.ecs_availability` |
| **Latency** | "Is it fast enough?" | A minute (or request) under the time threshold | `request.latency`, `dependency.latency`, `queue.latency`, `datastore.latency`, `network.latency` |
| **Quality** | "Did I get the full answer, or a degraded one?" | A response served without falling back or dropping content | none yet; use `custom` |
| **Freshness** | "Is this data recent?" | A minute in which data was younger than the limit | `data.freshness`, `queue.sqs_freshness`, `datastore.aurora_replica_lag` |
| **Correctness** | "Is this data right?" | A check that passed | `checks.correctness` |
| **Coverage** | "Did it process everything it should have?" | A record processed out of those expected | `data.coverage` |
| **Throughput** | "Is it keeping up with the volume?" | A minute in which processing rate met the floor | none yet; use `custom` |
| **Durability** | "If I stored it, can I get it back?" | A restore or integrity check that passed | `checks.durability` |

## Picking types for a system

The Workbook suggests starting points by kind of system:

- **Request-serving** (APIs, UIs, MCP tools): availability, latency, quality.
- **Data processing** (jobs, hydrators, pipelines): freshness, correctness, coverage, throughput.
- **Storage** (databases, volumes, object stores): availability, latency, durability.

Start with one or two SLOs that match what users actually complain about. If the
complaint would be "I got the wrong answer", that is correctness; "I saw stale data" is
freshness. Choose the SLI from the user's failure, not from whichever metric is easiest.

## Correctness is the one you write

For availability, latency and freshness the catalog can supply the full definition. For
correctness (and durability), only you know what "right" means, so the recipe only fixes
the *shape*: emit `slo.check.results` with `outcome` of `passed`, `failed` or
`not_performed`. A check that could not run is `not_performed` and counts against you.
It is never reported as `passed`.
