participant_name = "labsp"
location         = "eastus"

# ========== COST OPTIMIZATION SETTINGS ==========

# Environment & tagging
environment = "dev"

# VM sizing (RIGHT-SIZED for dev/test)
vm_size         = "Standard_B1s"  # Reduced from Standard_B2ms (saves 30-35%)
windows_vm_size = "Standard_B1s"  # Reduced from Standard_B2s (saves 25-30%)

# Auto-shutdown (ENABLED by default - saves 45% of compute costs)
enable_auto_shutdown         = true
auto_shutdown_time           = "1900"  # 19:00 UTC (end of business day)
auto_shutdown_timezone       = "UTC"   # Change to your local timezone
enable_shutdown_notifications = true

# Azure Bastion (DISABLED by default - saves $45-100/month)
enable_bastion     = false
bastion_scale_units = 1

# Storage optimization
storage_tier         = "Cool"  # Reduced from Hot (saves 50% on storage access)
windows_disk_size_gb = 60      # Reduced from 128GB

# Cost monitoring & alerts
monthly_budget_limit           = 250     # USD, adjust per environment
budget_alert_threshold_percent = 80      # Alert when 80% of budget spent
owner_email                    = "devops@example.com"

# Resource tags for cost allocation
tags = {
  environment       = "dev"
  cost_center       = "engineering"
  owner             = "devops-team"
  project           = "ailab"
  application       = "training"
  terraform_managed = "true"
  cost_optimization = "enabled"
}