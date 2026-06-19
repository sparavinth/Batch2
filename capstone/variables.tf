# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------

variable "prefix" {
  type        = string
  description = "Short prefix applied to every resource name (e.g. 'capstone')."
}

variable "location" {
  type        = string
  description = "Azure region where all resources will be deployed (e.g. 'East US')."
  default     = "East US"
}

variable "tags" {
  type        = map(string)
  description = "Key/value tags applied to every resource for identification and cost tracking."
  default = {
    environment = "capstone"
    managed_by  = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vnet_address_space" {
  type        = string
  description = "CIDR block for the Virtual Network."
  default     = "10.0.0.0/16"
}

variable "subnet_address_prefix" {
  type        = string
  description = "CIDR block for the single subnet carved from the VNet."
  default     = "10.0.1.0/24"
}

# ---------------------------------------------------------------------------
# Virtual Machines
# ---------------------------------------------------------------------------

variable "vm_size" {
  type        = string
  description = "Azure VM SKU applied to both Linux virtual machines."
  default     = "Standard_B1s"
}

variable "admin_username" {
  type        = string
  description = "OS-level administrator username created on each VM."
  default     = "azureuser"
}

variable "admin_password" {
  type        = string
  description = "Password for the VM admin user. Supply via TF_VAR_admin_password environment variable."
  sensitive   = true
}