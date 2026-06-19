# ---------------------------------------------------------------------------
# Public IP Addresses -- one per VM
# ---------------------------------------------------------------------------

output "vm1_public_ip" {
  description = "Public IP address of capstone-vm-1."
  value       = azurerm_public_ip.pip[0].ip_address
}

output "vm2_public_ip" {
  description = "Public IP address of capstone-vm-2."
  value       = azurerm_public_ip.pip[1].ip_address
}

# ---------------------------------------------------------------------------
# Ready-to-use SSH connection commands
# ---------------------------------------------------------------------------

output "vm1_ssh_command" {
  description = "Copy-paste SSH command to connect to capstone-vm-1."
  value       = "ssh -i ~/.ssh/id_rsa ${var.admin_username}@${azurerm_public_ip.pip[0].ip_address}"
}

output "vm2_ssh_command" {
  description = "Copy-paste SSH command to connect to capstone-vm-2."
  value       = "ssh -i ~/.ssh/id_rsa ${var.admin_username}@${azurerm_public_ip.pip[1].ip_address}"
}

# ---------------------------------------------------------------------------
# Resource Group name (useful for follow-up az CLI commands)
# ---------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the resource group that contains all deployed resources."
  value       = azurerm_resource_group.rg.name
}