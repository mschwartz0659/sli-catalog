terraform {
  # 1.7+ for mock_provider in `terraform test`; 1.5+ for strcontains().
  required_version = ">= 1.7.0"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = ">= 3.40.0"
    }
  }
}
