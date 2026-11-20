# Registry mode

For teams that do not run their own Terraform (common for infra teams and vendor
products). Instead of adding the module to your workspace, you add your slo.yaml to this
repo, and the catalog owner's workspace applies it.

## How to join

1. Branch from `main`.
2. Create `registry/<your-team>/slo.yaml`. Start from [templates/slo.yaml](../templates/slo.yaml),
   or copy `registry/_example-team/slo.yaml`.
3. Run `python3 scripts/sli.py validate registry/<your-team>/slo.yaml --render`.
4. Open a PR to `main`. CI validates it; the Terraform plan in the registry workspace shows
   exactly what will be created.
5. Once merged and applied, your SLOs appear in Datadog tagged `team:<your-team>`.

## What stays the same

Everything in the README: the same recipes, the same alerting rules, the same file. Only
who runs `terraform apply` differs.

## Folders starting with `_`

They are examples and are never applied.

## Moving to your own workspace later

Add the module to your Terraform pointing at the same slo.yaml, then remove your folder
from `registry/`. Use `terraform state mv` or `import` blocks so the SLOs move without
being deleted and recreated (recreating resets their history).
