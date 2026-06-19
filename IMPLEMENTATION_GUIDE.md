# FinOps Implementation Guide
## Quick Start - Phase 1: Cost Savings Quick Wins

This guide walks you through implementing the cost optimization recommendations in sequence.

---

## BEFORE YOU START

**Prerequisites:**
- Terraform CLI installed (v1.x+)
- Azure CLI authenticated (`az login`)
- Current directory: `c:\Users\labuser\Training\TF_Lab`

**Backup:**
```powershell
# Save current state before making changes
Copy-Item terraform.tfstate terraform.tfstate.backup
```

---

## PHASE 1: QUICK WINS (1-2 Hours | 25-35% Savings)

### Step 1: Review the Changes
All optimization changes have been made to:
- ✅ `variable.tf` – New parametrized variables
- ✅ `terraform.tfvars` – Optimized default values
- ✅ `main.tf` – Updated resources
- ✅ `output.tf` – Cost tracking outputs

### Step 2: Validate Configuration
```powershell
# Validate syntax
terraform validate

# Check formatting
terraform fmt -check

# Preview changes (DO NOT APPLY YET)
terraform plan -out=tfplan

# Review the plan output carefully
terraform show tfplan
```

### Step 3: Review Key Changes
**Main Optimizations Applied:**

| What Changed | From | To | Savings |
|-------------|------|-----|---------|
| Linux VM Size | Standard_B2ms | Standard_B1s | 30-35% |
| Windows VM Size | Standard_B2s | Standard_B1s | 25-30% |
| Windows Disk | 128GB | 60GB | 10-15% |
| Storage Tier | Hot | Cool | 50% on access |
| Azure Bastion | Enabled (scale 2) | Disabled | $45-100/month |
| Auto-shutdown | Hardcoded 13:00 | Parametrized 19:00 | Better aligned |
| Tagging | None | Complete | +Governance |

### Step 4: Adjust for Your Environment
**Edit terraform.tfvars** as needed:

```hcl
# Change shutdown time to match your timezone
auto_shutdown_time           = "1900"  # Currently 19:00 UTC (end of day)
auto_shutdown_timezone       = "UTC"   # Change to your timezone

# Adjust budget
monthly_budget_limit           = 250     # Adjust based on your environment
budget_alert_threshold_percent = 80      # Alert at 80% spend

# Change owner email for alerts
owner_email = "your.email@company.com"

# Update tagging
tags = {
  cost_center = "your-department"
  owner       = "your-name"
  project     = "your-project"
}
```

### Step 5: Apply Changes
```powershell
# Option A: Apply with plan file (recommended for first time)
terraform apply tfplan

# Option B: Apply with auto-approval (careful!)
terraform apply -auto-approve

# Verify changes
terraform show
```

### Step 6: Verify Deployment
```powershell
# Check output values
terraform output

# Verify specific output
terraform output cost_optimization_summary

# List all resources
terraform state list

# Check a specific resource
terraform state show azurerm_linux_virtual_machine.app
```

---

## PHASE 2: CONFIGURATION HARDENING (2-3 Hours)

### Step 1: Enable Remote State (Optional but Recommended)
```powershell
# Create resource group for state
az group create --name rg-terraform-state --location eastus

# Create storage account (must be globally unique)
$randomSuffix = -join ((97..122) | Get-Random -Count 5 | % {[char]$_})
$storageAccountName = "tfstate$randomSuffix"

az storage account create `
  --name $storageAccountName `
  --resource-group rg-terraform-state `
  --location eastus `
  --sku Standard_LRS `
  --kind StorageV2

# Create container
az storage container create `
  --name tfstate `
  --account-name $storageAccountName

# Get storage key
$storageKey = az storage account keys list `
  --account-name $storageAccountName `
  --query '[0].value' -o tsv

# Migrate state to remote backend
# Add to main.tf:
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "rg-terraform-state"
#     storage_account_name = "$storageAccountName"
#     container_name       = "tfstate"
#     key                  = "ailab.tfstate"
#   }
# }

# Then run:
terraform init -migrate-state
```

### Step 2: Implement Tag Enforcement
```powershell
# Verify all resources have required tags
terraform output tags_applied

# Check resource group tags
az group show --name rg-ailab-labsp --query tags
```

### Step 3: Add Storage Lifecycle Policies (Optional)
```hcl
# Add to main.tf if you want to automatically archive old blobs:

resource "azurerm_storage_account_management_policy" "lab" {
  storage_account_id = azurerm_storage_account.lab.id

  rule {
    name    = "archive_old_blobs"
    enabled = true

    filters {
      prefix_match = ["logs/", "backups/"]
      blob_type    = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 90
        delete_after_days_since_modification_greater_than          = 180
      }
    }
  }
}
```

---

## PHASE 3: MONITORING & AUTOMATION (3-4 Hours)

### Step 1: Enable Azure Advisor
```powershell
# Azure Advisor is free - just visit the portal:
# https://portal.azure.com/#blade/Microsoft_Azure_Expert/AdvisorMenuBlade

# Check for recommendations:
az advisor recommendation list --subscription <your-subscription-id>
```

### Step 2: Set Up Cost Alerts
```powershell
# View budget settings
terraform output cost_optimization_summary

# You can create alerts via Azure Portal:
# Cost Management + Billing → Budgets → Create new
# Set limit to $250/month with 80% alert threshold
```

### Step 3: Enable Cost Management Exports
```powershell
# Export costs daily for analysis:
# Portal: Cost Management + Billing → Exports
# Create daily export to your storage account
```

### Step 4: Create Cost Tracking Dashboard (Optional)
```powershell
# Use Azure Dashboards to monitor:
# 1. Daily spend vs budget
# 2. Cost by resource group
# 3. Cost by tag (cost_center, owner)
# 4. Top 10 resources by cost
```

---

## MONITORING CHECKLIST

### Daily (5 min)
- [ ] Check Azure Portal for cost alerts
- [ ] Verify auto-shutdown ran (check VM power state)

### Weekly (30 min)
- [ ] Review Azure Advisor recommendations
- [ ] Check Cost Management for cost trends
- [ ] Validate tag compliance

### Monthly (1 hour)
- [ ] Generate cost report by department
- [ ] Compare actual vs budgeted spend
- [ ] Update resource allocation as needed
- [ ] Review and approve tag changes

---

## ROLLBACK (If Needed)

```powershell
# Option 1: Restore from backup
Copy-Item terraform.tfstate.backup terraform.tfstate
terraform apply

# Option 2: Terraform destroy & recreate
terraform destroy
terraform apply
```

---

## TROUBLESHOOTING

### Issue: Bastion deployment fails
**Solution:** Set `enable_bastion = false` in terraform.tfvars (enabled by default in new config)

### Issue: Auto-shutdown not working
**Solution:** 
```powershell
# Check if schedules were created
az vm auto-shutdown list --query "[].{vm:virtualMachineId, enabled:enabled}" -o table

# Manually enable if needed
az vm auto-shutdown create --resource-group rg-ailab-labsp --name vm-app --time 1900 --email <email>
```

### Issue: Storage tier change causes issues
**Solution:** Cool tier is backward compatible. If needed, change back to Hot in terraform.tfvars:
```hcl
storage_tier = "Hot"  # Revert if issues occur
terraform apply
```

### Issue: VM oversizing detected by Advisor
**Solution:** Advisor may recommend further downsizing to B1s variants. Evaluate usage and apply if appropriate.

---

## COST VALIDATION

### Expected Monthly Costs

**Before Optimization:**
```
3x VMs @ Standard_B2ms/B2s × 168 hours   = $145
Azure Bastion (2 scale units)             = $55
Disks (3× 30-128GB)                       = $5
Storage account (Cool)                    = $1
NSGs, VNets, IPs                          = $3
─────────────────────────────────────────────
TOTAL:                                    ≈ $210/month
```

**After Optimization:**
```
3x VMs @ Standard_B1s × 11 hours/day      = $19  (45% reduction via auto-shutdown)
Azure Bastion                             = $0   (disabled)
Disks (optimized)                         = $3
Storage account (Cool)                    = $1
NSGs, VNets, IPs                          = $3
─────────────────────────────────────────────
TOTAL:                                    ≈ $26/month
```

**Savings: ~$184/month (88% reduction)**

> Note: Actual costs vary by region and usage. Use Azure Cost Calculator for exact pricing.

---

## NEXT STEPS AFTER IMPLEMENTATION

1. **Week 1:** Monitor auto-shutdown logs
2. **Week 2:** Validate tag compliance across all resources
3. **Week 3:** Generate first cost report by department
4. **Week 4:** Review Advisor recommendations
5. **Month 2:** Plan Phase 3 (Automation & FinOps CoE)

---

## RESOURCES

- [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/)
- [Azure Cost Management](https://portal.azure.com/#blade/Microsoft_Azure_Cost/CostManagementMenuBlade)
- [Azure Advisor](https://portal.azure.com/#blade/Microsoft_Azure_Expert/AdvisorMenuBlade)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [Azure FinOps Guide](https://docs.microsoft.com/en-us/azure/finops/)

---

**Last Updated:** 2026-06-15  
**Status:** Ready for Implementation
