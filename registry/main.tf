# Registry mode: for teams without their own Terraform. Each team adds
# registry/<team>/slo.yaml by pull request; this root applies them all from the
# sli-catalog owner's workspace. Folders starting with "_" are examples and skipped.
# See docs/registry.md.

locals {
  files = toset([for f in fileset(path.module, "*/slo.yaml") : f if !startswith(f, "_")])
}

module "team" {
  for_each = local.files
  source   = "../modules/datadog-slo"

  slo_file    = "${path.module}/${each.value}"
  source_repo = "https://github.com/mschwartz0659/sli-catalog/tree/main/registry/${dirname(each.value)}"
}

output "slo_ids" {
  value = { for k, m in module.team : dirname(k) => m.slo_ids }
}
