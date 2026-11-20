output "slo_ids" {
  description = "Datadog SLO IDs, keyed by SLO name."
  value       = { for k, v in datadog_service_level_objective.this : k => v.id }
}

output "burn_rate_monitor_ids" {
  description = "Burn-rate monitor IDs, keyed by <slo>.<tier>."
  value       = { for k, v in datadog_monitor.burn_rate : k => v.id }
}

output "heartbeat_monitor_ids" {
  description = "Heartbeat monitor IDs, keyed by SLO name."
  value       = { for k, v in datadog_monitor.heartbeat : k => v.id }
}

output "rendered" {
  description = "What each SLO resolved to: type, queries and target. Useful in plan output."
  value = { for k, s in local.slo : k => {
    recipe      = s.recipe
    category    = s.category
    mode        = s.mode
    target      = s.target
    alerting    = s.alerting
    numerator   = s.numerator
    denominator = s.denominator
    queries     = s.queries
    good_when   = s.mode == "time_slice" ? "${s.formula} ${s.comparator} ${s.threshold}" : null
  } }
}

output "burn_rate_alerts" {
  description = "Burn-rate alert settings per <slo>.<tier>: severity, windows, threshold and who is notified."
  value = { for k, m in local.burn_monitors : k => {
    severity = m.severity
    long     = m.long
    short    = m.short
    rate     = m.rate
    alerting = m.alerting
  } }
}
