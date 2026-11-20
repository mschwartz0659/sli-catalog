# Reads a team's slo.yaml, resolves each SLO against the recipe catalog, and creates:
#   - one Datadog SLO per entry (metric-based for mode "events", time-slice for "time_slice")
#   - multi-window burn-rate monitors per SLO (unless alerting is "none")
#   - a no-data heartbeat monitor for recipes that declare one
#
# scripts/sli.py mirrors this logic for fast CI feedback. This file is the authority:
# if they disagree, fix sli.py.

locals {
  # ------------------------------------------------------------- catalog
  catalog_dir  = coalesce(var.catalog_dir, "${path.module}/../../catalog/recipes")
  recipe_files = fileset(local.catalog_dir, "*.yaml")
  recipes      = { for f in local.recipe_files : trimsuffix(f, ".yaml") => yamldecode(file("${local.catalog_dir}/${f}")) }

  categories   = ["availability", "latency", "quality", "freshness", "correctness", "coverage", "throughput", "durability"]
  window_hours = { "7d" = 168, "30d" = 720, "90d" = 2160 }

  # Burn-rate tiers, defined by how much of the window's error budget is spent within
  # the long window (SRE Workbook, "Alerting on SLOs"). For a 30d window these give
  # 14.4x / 6x / 3x. Tiers whose burn rate would be <= 1 are skipped.
  burn_tiers = {
    page_fast = { severity = "page", long_hours = 1, short = "5m", budget = 0.02 }
    page_slow = { severity = "page", long_hours = 6, short = "30m", budget = 0.05 }
    ticket    = { severity = "ticket", long_hours = 24, short = "2h", budget = 0.10 }
  }

  # ------------------------------------------------------------- spec
  spec          = yamldecode(file(var.slo_file))
  service       = local.spec.service
  env           = local.spec.env
  window        = try(local.spec.window, "30d")
  hours         = lookup(local.window_hours, local.window, 720)
  spec_alerting = try(local.spec.alerting, "observe")
  page_handle   = "@pagerduty-${local.spec.routing.page}"
  ticket_hands  = try(local.spec.routing.ticket, [])
  runbook       = try(local.spec.links.runbook, "")

  base_tags = concat([
    "service:${local.service}",
    "env:${local.env}",
    "team:${local.spec.team}",
    "tier:${try(local.spec.tier, 3)}",
    "entity-kind:${try(local.spec.kind, "service")}",
    "managed-by:sli-catalog",
    "sli-catalog-schema:v1",
  ], var.extra_tags)

  # Duplicate names fail here with "Duplicate object key", which is the intent.
  slos = { for s in local.spec.slos : s.name => s }

  # ------------------------------------------------------------- resolution
  # Mode: explicit > recipe default > (custom) whichever block was given.
  mode = { for name, s in local.slos : name => try(
    s.mode,
    local.recipes[s.recipe].default_mode,
    try(s.events, null) != null ? "events" : "time_slice",
  ) }

  # Variables for ${...} substitution: recipe defaults < team params < built-ins.
  vars = { for name, s in local.slos : name => merge(
    { for k, p in try(local.recipes[s.recipe].params, {}) : k => tostring(p.default) if try(p.default, null) != null },
    { for k, v in try(s.params, {}) : k => tostring(v) },
    { service = local.service, env = local.env },
  ) }

  # The template for the chosen mode, plus the recipe's heartbeat (if any).
  src = { for name, s in local.slos : name => {
    block     = try(local.recipes[s.recipe].modes[local.mode[name]], s[local.mode[name]], null)
    heartbeat = try(local.recipes[s.recipe].heartbeat, null)
  } }

  # Substitute ${name} everywhere in one pass over the JSON form of the template.
  # Unknown names become <<MISSING:name>> and are reported by a precondition below.
  # (Param values are restricted by the schema to characters that are safe here.)
  rendered_json = { for name, src in local.src : name => join("", [
    for i, part in split("$${", jsonencode(src)) :
    i == 0 ? part : format("%s%s",
      try(local.vars[name][split("}", part)[0]], format("<<MISSING:%s>>", split("}", part)[0])),
      join("}", slice(split("}", part), 1, length(split("}", part))))
    )
  ]) }

  rendered = { for name, j in local.rendered_json : name => try(jsondecode(j), { block = null, heartbeat = null }) }
  missing  = { for name, j in local.rendered_json : name => distinct([for m in regexall("<<MISSING:([^>]+)>>", j) : m[0]]) }

  slo = { for name, s in local.slos : name => {
    recipe       = s.recipe
    known_recipe = s.recipe == "custom" || contains(keys(local.recipes), s.recipe)

    unknown_params = s.recipe == "custom" ? [] : tolist(setsubtract(
      keys(try(s.params, {})), keys(try(local.recipes[s.recipe].params, {}))
    ))
    category    = try(local.recipes[s.recipe].category, s.category, "unknown")
    summary     = try(local.recipes[s.recipe].summary, "")
    description = try(s.description, "")
    mode        = local.mode[name]
    target      = s.target
    warning     = try(s.warning, null)
    alerting    = try(s.alerting, local.spec_alerting)
    missing     = local.missing[name]

    numerator   = try(local.rendered[name].block.numerator, null)
    denominator = try(local.rendered[name].block.denominator, null)
    queries     = try(local.rendered[name].block.queries, {})
    formula     = try(local.rendered[name].block.formula, null)
    comparator  = try(local.rendered[name].block.comparator, null)
    threshold   = try(tonumber(local.rendered[name].block.threshold), null)
    interval    = try(tonumber(local.rendered[name].block.interval_seconds), 300)

    heartbeat_query     = try(local.rendered[name].heartbeat.query, null)
    heartbeat_threshold = try(tonumber(local.rendered[name].heartbeat.threshold), null)
    heartbeat_no_data   = try(tonumber(local.rendered[name].heartbeat.no_data_minutes), null)
  } }

  # ------------------------------------------------------------- alerts
  burn_monitors = merge({}, [
    for name, s in local.slo : {
      for tier, t in local.burn_tiers : "${name}.${tier}" => {
        slo        = name
        tier       = tier
        severity   = t.severity
        long       = "${t.long_hours}h"
        short      = t.short
        budget_pct = floor(t.budget * 100)
        rate       = format("%.2f", t.budget * local.hours / t.long_hours)
        alerting   = s.alerting
      } if t.budget * local.hours / t.long_hours > 1
    } if s.alerting != "none"
  ]...)

  heartbeats = { for name, s in local.slo : name => s if s.heartbeat_query != null && s.alerting != "none" }

  # Who hears about it. Only SLOs whose alerting is "live" include these handles;
  # "observe" creates the monitors but notifies no one.
  notify = {
    page   = local.page_handle
    ticket = join(" ", local.ticket_hands)
  }
}

resource "datadog_service_level_objective" "this" {
  for_each = local.slo

  name = "${local.service} - ${each.key}"
  type = each.value.mode == "events" ? "metric" : "time_slice"
  description = trimspace(join("\n\n", compact([
    each.value.summary,
    each.value.description,
    "Managed by sli-catalog (recipe: ${each.value.recipe}). Change it in ${var.source_repo != "" ? var.source_repo : "the team's"} slo.yaml; edits made in Datadog are reverted on the next apply.",
  ])))

  dynamic "query" {
    for_each = each.value.mode == "events" ? [1] : []
    content {
      numerator   = each.value.numerator
      denominator = each.value.denominator
    }
  }

  dynamic "sli_specification" {
    for_each = each.value.mode == "time_slice" ? [1] : []
    content {
      time_slice {
        query {
          formula {
            formula_expression = each.value.formula
          }
          dynamic "query" {
            for_each = each.value.queries
            iterator = q
            content {
              metric_query {
                name  = q.key
                query = q.value
              }
            }
          }
        }
        comparator             = each.value.comparator
        threshold              = each.value.threshold
        query_interval_seconds = each.value.interval
      }
    }
  }

  thresholds {
    timeframe = local.window
    target    = each.value.target
    warning   = each.value.warning
  }
  timeframe         = local.window
  target_threshold  = each.value.target
  warning_threshold = each.value.warning

  tags = concat(local.base_tags, [
    "slo-category:${each.value.category}",
    "sli-recipe:${each.value.recipe}",
  ])

  lifecycle {
    precondition {
      condition     = contains(keys(local.window_hours), local.window)
      error_message = "window must be one of 7d, 30d, 90d (got ${local.window})."
    }
    precondition {
      condition     = contains(["observe", "live", "none"], each.value.alerting)
      error_message = "SLO ${each.key}: alerting must be observe, live or none (got ${each.value.alerting})."
    }
    precondition {
      condition     = each.value.known_recipe
      error_message = "SLO ${each.key}: unknown recipe '${each.value.recipe}'. See docs/catalog.md for the menu."
    }
    precondition {
      condition     = length(each.value.unknown_params) == 0
      error_message = "SLO ${each.key}: recipe '${each.value.recipe}' has no param(s) ${jsonencode(each.value.unknown_params)}."
    }
    precondition {
      condition     = length(each.value.missing) == 0
      error_message = "SLO ${each.key}: recipe '${each.value.recipe}' needs param(s) ${jsonencode(each.value.missing)}."
    }
    precondition {
      condition = each.value.mode == "events" ? (each.value.numerator != null && each.value.denominator != null) : (
        each.value.formula != null && each.value.comparator != null && each.value.threshold != null && length(each.value.queries) > 0
      )
      error_message = "SLO ${each.key}: recipe '${each.value.recipe}' has no usable '${each.value.mode}' mode."
    }
    precondition {
      condition     = contains(local.categories, each.value.category)
      error_message = "SLO ${each.key}: category must be one of ${join(", ", local.categories)}."
    }
    precondition {
      condition     = each.value.target > 0 && each.value.target < 100 && (each.value.warning == null ? true : each.value.warning > each.value.target)
      error_message = "SLO ${each.key}: target must be between 0 and 100, and warning (if set) above target."
    }
  }
}

resource "datadog_monitor" "burn_rate" {
  for_each = local.burn_monitors

  name = "[SLO ${upper(each.value.severity)}] ${local.service} - ${each.value.slo}: burning budget ${each.value.rate}x (${each.value.long})"
  type = "slo alert"
  query = format(
    "burn_rate(\"%s\").over(\"%s\").long_window(\"%s\").short_window(\"%s\") > %s",
    datadog_service_level_objective.this[each.value.slo].id,
    local.window, each.value.long, each.value.short, each.value.rate,
  )

  message = trimspace(join("\n", compact([
    "{{#is_alert}}",
    "SLO **${each.value.slo}** on **${local.service}** (${local.env}) is spending its error budget ${each.value.rate}x faster than sustainable.",
    "At this rate ${each.value.budget_pct}% of the ${local.window} budget is gone within ${each.value.long}.",
    "Long window: {{long_window_burn_rate}}x. Short window: {{short_window_burn_rate}}x.",
    local.runbook != "" ? "Runbook: ${local.runbook}" : "",
    "{{/is_alert}}",
    each.value.alerting == "live" ? (each.value.severity == "page" ? local.notify.page : local.notify.ticket) : "",
  ])))

  monitor_thresholds {
    critical = tonumber(each.value.rate)
  }

  tags = concat(local.base_tags, [
    "slo-name:${each.value.slo}",
    "slo-alert:${each.value.tier}",
    "severity:${each.value.severity}",
    "alerting:${each.value.alerting}",
  ])
}

resource "datadog_monitor" "heartbeat" {
  for_each = local.heartbeats

  name  = "[SLO HEARTBEAT] ${local.service} - ${each.key}: data is stale or not reporting"
  type  = "metric alert"
  query = each.value.heartbeat_query
  message = trimspace(join("\n", compact([
    "{{#is_alert}}Data for **${each.key}** on **${local.service}** is older than allowed.{{/is_alert}}",
    "{{#is_no_data}}No freshness data for **${each.key}** on **${local.service}** for ${each.value.heartbeat_no_data} minutes. The job or the process reporting it may have stopped.{{/is_no_data}}",
    local.runbook != "" ? "Runbook: ${local.runbook}" : "",
    each.value.alerting == "live" ? local.notify.page : "",
  ])))

  monitor_thresholds {
    critical = each.value.heartbeat_threshold
  }
  notify_no_data      = true
  no_data_timeframe   = each.value.heartbeat_no_data
  require_full_window = false

  tags = concat(local.base_tags, [
    "slo-name:${each.key}",
    "slo-alert:heartbeat",
    "severity:page",
    "alerting:${each.value.alerting}",
  ])
}
