# CLAUDE.md — sli-catalog

## What this is

A shared catalog of SLI recipes plus a Terraform module that turns a team's `slo.yaml`
into Datadog SLOs, burn-rate monitors and heartbeat monitors, routed to PagerDuty through
Datadog. Teams own their SLOs (targets); this repo owns what can be measured and how.
Datadog is the only backend. Owner: @mschwartz0659.

Plan of record: `docs/plan.md`. Why things are as they are: `docs/decisions.md`.
External facts and their sources: `docs/sources.md`.

## Layout

| Path | What |
|---|---|
| `catalog/recipes/<id>.yaml` | One recipe per file; file stem == `id` |
| `schema/slo.v1.schema.json` | What a team's slo.yaml may contain |
| `modules/datadog-slo/` | The Terraform module (authority) + `tests/*.tftest.hcl` |
| `scripts/sli.py` | Validator, renderer, catalog lint, doc generator, self-test (mirror of the module) |
| `tests/fixtures/` | `valid/` must pass, `invalid/` and `bad-recipes/` must fail with the `# expect:` text on line 1 |
| `templates/slo.yaml` | Starter file teams copy |
| `examples/`, `registry/` | Team usage example; registry-mode root (`_`-prefixed folders are skipped) |
| `docs/catalog.md` | **Generated** from recipes. Never edit by hand |

## Commands

```bash
pip install -r scripts/requirements.txt
python3 scripts/sli.py self-test               # catalog lint + fixtures (must pass before any commit)
python3 scripts/sli.py catalog-doc             # regenerate docs/catalog.md after recipe changes
python3 scripts/sli.py validate FILE --render  # check a slo.yaml and print the queries
cd modules/datadog-slo && terraform init -backend=false && terraform test
terraform fmt -recursive
```

## Rules

1. **The module is the authority; `sli.py` mirrors it.** Any change to resolution,
   rendering, defaults or burn tiers is made in both, with a fixture or `tftest` assertion
   that covers it. If they disagree, the module is right and `sli.py` is the bug.
2. **Recipes never change meaning within a major version.** A change to what a recipe
   counts is a new recipe id; mark the old one `status: deprecated`. Wording, notes and
   new optional params with defaults that keep current output are fine.
3. **A recipe is `draft` until checked against real data in our Datadog org.** Don't mark
   `verified` without that. Don't state an unverified metric or tag name as fact in docs;
   list it under "Open items" in `docs/plan.md`.
4. **Every detector can fail.** New validation rules ship with a fixture in
   `tests/fixtures/invalid/` or `bad-recipes/` proving they catch the defect.
5. **Units are the metric's own unit; no arithmetic in templates.** The module's renderer
   substitutes `${name}` text only.
6. **The module never configures providers** and never reads credentials. Callers do, via
   workspace env vars (`DD_API_KEY`, `DD_APP_KEY`, `DD_HOST`).
7. **Ask before guessing org specifics** (Datadog site, PagerDuty service names, TFE org or
   workspace names). Never invent them; use obvious fakes (`example-*`, `example.test`) in
   fixtures and examples.
8. **No secrets or real personal data in any committed file.**
9. **Outside facts get a source.** A claim about Datadog, Terraform or SRE practice either
   cites a row in `docs/sources.md` (add one) or is listed as unverified.

## Git

Trunk-based. `main` is the only long-lived branch and is protected. Work on a short-lived
branch (`feature/<what>`, `fix/<what>`), open a PR to `main`, squash-merge. Releases are
semver tags on `main` (`vX.Y.Z`); teams pin tags. Check the current branch before
committing. Commit messages say what changed and why. Each PR names its `docs/plan.md`
item or says `off-plan:` with a reason and adds the item.

## Docs

`CLAUDE.md` and `README.md` live at the root; every other `.md` goes in `docs/`
(`.github/` files excepted). Docs change in the same PR as the code that invalidates them.
`docs/decisions.md` is a table only: one row per decision, one line, ≤300 characters,
append-only; a decision that changes a rule edits the rule here or in the README in the
same commit. Keep this file short: anything only some sessions need goes in `docs/`.
