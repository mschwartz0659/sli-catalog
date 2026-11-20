# Skip this file if your workspace already configures the Datadog provider.
# Credentials come from the workspace's environment (a shared variable set), never from code:
#   DD_API_KEY, DD_APP_KEY  - a Datadog service account's keys
#   DD_HOST                 - your Datadog site's API URL, e.g. https://api.datadoghq.com/

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
