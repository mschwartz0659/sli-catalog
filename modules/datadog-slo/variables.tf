variable "slo_file" {
  description = "Path to the team's slo.yaml, usually \"$${path.root}/slo.yaml\"."
  type        = string

  validation {
    condition     = fileexists(var.slo_file)
    error_message = "slo_file does not exist. Pass the path to your slo.yaml, e.g. \"$${path.root}/slo.yaml\"."
  }
}

variable "source_repo" {
  description = "Where the slo.yaml lives (e.g. a repo URL). Shown in each SLO's description so people know where to edit it."
  type        = string
  default     = ""
}

variable "extra_tags" {
  description = "Additional Datadog tags (key:value) added to every SLO and monitor."
  type        = list(string)
  default     = []
}

variable "catalog_dir" {
  description = "Override the recipe directory. Leave null to use the catalog shipped with this module version."
  type        = string
  default     = null
}
