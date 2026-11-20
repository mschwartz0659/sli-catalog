# Credentials come from the workspace environment (DD_API_KEY, DD_APP_KEY, DD_HOST).
# The workspace for this root is an open item in docs/plan.md; until it exists, add a
# `cloud {}` block here pointing at it.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = ">= 3.40.0"
    }
  }
}

provider "datadog" {}
