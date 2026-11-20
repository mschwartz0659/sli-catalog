# Run from modules/datadog-slo:  terraform init -backend=false && terraform test
# The mock provider means no Datadog credentials are needed: these tests check what the
# module would create, not that Datadog accepts it. Datadog acceptance is checked by
# applying to a scratch scope (docs/plan.md).

mock_provider "datadog" {}

run "full_fixture_renders" {
  command = plan

  variables {
    slo_file = "../../tests/fixtures/valid/full.yaml"
  }

  assert {
    condition     = length(datadog_service_level_objective.this) == 7
    error_message = "Expected one Datadog SLO per entry in full.yaml."
  }

  assert {
    condition     = datadog_service_level_objective.this["api-availability"].type == "metric"
    error_message = "An events-mode recipe must become a metric-based SLO."
  }

  assert {
    condition     = datadog_service_level_objective.this["api-latency"].type == "time_slice"
    error_message = "A time_slice-mode recipe must become a time-slice SLO."
  }

  assert {
    condition     = output.rendered["api-availability"].numerator == "sum:trace.express.request.hits{service:example-dashboard,env:prod}.as_count() - sum:trace.express.request.errors{service:example-dashboard,env:prod}.as_count()"
    error_message = "request.availability numerator did not render as expected."
  }

  assert {
    condition     = output.rendered["hydrator-freshness"].good_when == "query1 <= 1800"
    error_message = "data.freshness threshold did not render from max_age_seconds."
  }

  assert {
    condition     = output.rendered["api-availability-quiet-hours"].good_when == "1 - query1 / query2 >= 0.95"
    error_message = "A team param must override the recipe default."
  }

  # Burn-rate queries embed the SLO id, unknown at plan, so tiers are checked
  # through output.burn_rate_alerts instead of the monitor query.

  # reconciliation has alerting: none, so 6 alerting SLOs x 3 tiers.
  assert {
    condition     = length(datadog_monitor.burn_rate) == 18
    error_message = "Expected 3 burn-rate monitors for each SLO whose alerting is not none."
  }

  assert {
    condition     = output.burn_rate_alerts["api-availability.page_fast"].long == "1h" && output.burn_rate_alerts["api-availability.page_fast"].short == "5m" && output.burn_rate_alerts["api-availability.page_fast"].rate == "14.40"
    error_message = "30d page_fast tier must be 14.4x over 1h/5m."
  }

  assert {
    condition     = output.burn_rate_alerts["api-availability.ticket"].long == "24h" && output.burn_rate_alerts["api-availability.ticket"].short == "2h" && output.burn_rate_alerts["api-availability.ticket"].rate == "3.00"
    error_message = "30d ticket tier must be 3x over 24h/2h."
  }

  assert {
    condition     = strcontains(datadog_monitor.burn_rate["api-availability.page_fast"].message, "@pagerduty-example-team-apps")
    error_message = "A live page alert must notify the PagerDuty service."
  }

  assert {
    condition     = strcontains(datadog_monitor.burn_rate["api-availability.ticket"].message, "@pagerduty-example-team-low")
    error_message = "A live ticket alert must notify the ticket handles."
  }

  assert {
    condition     = !strcontains(datadog_monitor.burn_rate["api-availability-quiet-hours.page_fast"].message, "@pagerduty")
    error_message = "An observe-mode SLO must not notify anyone."
  }

  assert {
    condition     = length(datadog_monitor.heartbeat) == 1 && datadog_monitor.heartbeat["hydrator-freshness"].notify_no_data
    error_message = "data.freshness must add a no-data heartbeat monitor."
  }

  assert {
    condition     = contains(datadog_service_level_objective.this["api-latency"].tags, "managed-by:sli-catalog")
    error_message = "Every SLO must carry managed-by:sli-catalog."
  }
}

run "minimal_defaults_to_observe" {
  command = plan

  variables {
    slo_file = "../../tests/fixtures/valid/minimal.yaml"
  }

  assert {
    condition     = alltrue([for m in datadog_monitor.burn_rate : !strcontains(m.message, "@pagerduty")])
    error_message = "With no alerting set, monitors must default to observe and notify no one."
  }
}

run "missing_param_is_rejected" {
  command = plan

  variables {
    slo_file = "../../tests/fixtures/invalid/missing-param.yaml"
  }

  expect_failures = [datadog_service_level_objective.this]
}

run "unknown_recipe_is_rejected" {
  command = plan

  variables {
    slo_file = "../../tests/fixtures/invalid/unknown-recipe.yaml"
  }

  expect_failures = [datadog_service_level_objective.this]
}

run "unknown_param_is_rejected" {
  command = plan

  variables {
    slo_file = "../../tests/fixtures/invalid/unknown-param.yaml"
  }

  expect_failures = [datadog_service_level_objective.this]
}

run "unsupported_mode_is_rejected" {
  command = plan

  variables {
    slo_file = "../../tests/fixtures/invalid/unsupported-mode.yaml"
  }

  expect_failures = [datadog_service_level_objective.this]
}
