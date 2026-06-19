variable "participant_name" {
  description = "labsp"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "admin_password" {
  description = "Admin password for all VMs"
  type        = string
  sensitive   = true
}

# ========== NEW VARIABLES FOR COST OPTIMIZATION ==========

variable "environment" {
  description = "Environment type (dev/test/prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod."
  }
}

variable "vm_size" {
  description = "Azure VM size for all VMs"
  type        = string
  default     = "Standard_B1s"  # RIGHT-SIZED from Standard_B2ms
}

variable "windows_vm_size" {
  description = "Azure VM size for Windows VMs"
  type        = string
  default     = "Standard_B1s"  # RIGHT-SIZED from Standard_B2s
}

variable "enable_auto_shutdown" {
  description = "Enable daily auto-shutdown for cost savings"
  type        = bool
  default     = true
}

variable "auto_shutdown_time" {
  description = "Daily shutdown time (HHMM format, UTC)"
  type        = string
  default     = "1900"  # 19:00 UTC (end of business day)

  validation {
    condition     = length(var.auto_shutdown_time) == 4 && tonumber(var.auto_shutdown_time) < 2400
    error_message = "Time must be in HHMM format (0000-2359)."
  }
}

variable "auto_shutdown_timezone" {
  description = "Timezone for auto-shutdown schedule"
  type        = string
  default     = "UTC"  # Change to your local timezone
}

variable "enable_shutdown_notifications" {
  description = "Send notification before auto-shutdown"
  type        = bool
  default     = true
}

variable "enable_bastion" {
  description = "Deploy Azure Bastion for remote access (costly)"
  type        = bool
  default     = false  # DISABLED by default to save costs
}

variable "bastion_scale_units" {
  description = "Number of scale units for Bastion (1-50)"
  type        = number
  default     = 1

  validation {
    condition     = var.bastion_scale_units >= 1 && var.bastion_scale_units <= 50
    error_message = "Scale units must be between 1 and 50."
  }
}

variable "storage_tier" {
  description = "Storage account access tier (Hot/Cool/Archive)"
  type        = string
  default     = "Cool"  # OPTIMIZED from Hot

  validation {
    condition     = contains(["Hot", "Cool", "Archive"], var.storage_tier)
    error_message = "Tier must be Hot, Cool, or Archive."
  }
}

variable "windows_disk_size_gb" {
  description = "Windows OS disk size in GB"
  type        = number
  default     = 60  # RIGHT-SIZED from 128GB
}

variable "tags" {
  description = "Common tags for cost allocation and tracking"
  type        = map(string)
  default = {
    environment       = "dev"
    cost_center       = "engineering"
    owner             = "devops"
    project           = "ailab"
    application       = "training"
    terraform_managed = "true"
    cost_optimization = "enabled"
  }
}

variable "monthly_budget_limit" {
  description = "Monthly spend limit in USD (for alerts)"
  type        = number
  default     = 250  # Adjust per environment
}

variable "budget_alert_threshold_percent" {
  description = "Alert threshold as percentage of budget"
  type        = number
  default     = 80
}

variable "owner_email" {
  description = "Email address for cost alerts"
  type        = string
  default     = "devops@example.com"
}