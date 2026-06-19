output "vm_app_private_ip" {
  value = azurerm_network_interface.app.private_ip_address
}

output "vm_db_private_ip" {
  value = azurerm_network_interface.db.private_ip_address
}

output "vm_win_private_ip" {
  value = azurerm_network_interface.win.private_ip_address
}

output "resource_group" {
  value = azurerm_resource_group.lab.name
}

# ========== COST OPTIMIZATION OUTPUTS ==========

output "cost_optimization_summary" {
  description = "Summary of cost optimization settings"
  value = {
    environment                  = var.environment
    vm_size                      = var.vm_size
    windows_vm_size              = var.windows_vm_size
    auto_shutdown_enabled        = var.enable_auto_shutdown
    auto_shutdown_time_utc       = var.auto_shutdown_time
    bastion_enabled              = var.enable_bastion
    bastion_cost_monthly         = var.enable_bastion ? "~$45-100" : "$0 (disabled)"
    storage_tier                 = var.storage_tier
    windows_disk_size_gb         = var.windows_disk_size_gb
    estimated_monthly_cost       = var.enable_bastion ? "~$200-250" : "~$23-50"
    estimated_monthly_savings_vs_oversized = "80-90% reduction from original config"
  }
}

output "tags_applied" {
  description = "Resource tags for cost allocation"
  value       = var.tags
}

output "monitoring_recommendations" {
  description = "FinOps monitoring and optimization recommendations"
  value = {
    next_steps = [
      "Review Azure Advisor recommendations weekly",
      "Monitor actual spend against budget (${var.monthly_budget_limit} USD)",
      "Check auto-shutdown logs to verify VMs are shutting down",
      "Review Azure Cost Management for departmental chargeback",
      "Validate tagging consistency across all resources"
    ]
    azure_cost_management_url = "https://portal.azure.com/#blade/Microsoft_Azure_Cost/CostManagementMenuBlade"
    azure_advisor_url         = "https://portal.azure.com/#blade/Microsoft_Azure_Expert/AdvisorMenuBlade"
  }
}