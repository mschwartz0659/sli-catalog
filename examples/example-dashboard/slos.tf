# Add this to your existing Terraform. It runs in your own workspace, alongside
# everything else you manage there.

module "slos" {
  source = "git::https://github.com/mschwartz0659/sli-catalog.git//modules/datadog-slo?ref=v0.1.0"

  slo_file    = "${path.root}/slo.yaml"
  source_repo = "https://github.com/example-org/example-dashboard"
}

output "slo_ids" {
  value = module.slos.slo_ids
}
