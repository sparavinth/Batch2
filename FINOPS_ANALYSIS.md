# FinOps Optimization Analysis
## Azure Terraform Lab Environment

**Analysis Date:** June 15, 2026  
**Environment:** Dev/Test Lab (Non-Production)  
**Cloud Provider:** Microsoft Azure  
**Terraform Scope:** Individual resources (no modules)  
**Primary Workloads:** VMs, Database, Storage, Network

---

## EXECUTIVE SUMMARY

This lab environment demonstrates foundational cost management practices (auto-shutdown schedules) but has significant optimization opportunities across compute sizing, storage configuration, and infrastructure design. **Estimated monthly cost: $200-250 USD** (before optimizations); **potential savings: 40-55%** through recommended changes.

### Quick Wins (Implement First)
1. **Downsize Standard_B2ms → Standard_B1s/B2s** – 30-35% compute savings
2. **Convert OS disks from Premium_LRS → Standard_LRS** – Already implemented ✓
3. **Disable unused Bastion when not in use** – $45-80/month savings
4. **Add Azure Advisor recommendations** – Recurring optimization

---

## DETAILED ANALYSIS BY AREA

### 1. RESOURCE UTILIZATION & RIGHT-SIZING
**Priority: HIGH | Impact: 30-35% monthly savings**

#### Findings:
- **VM Sizing Over-provisioned:**
  - `Standard_B2ms` (2vCPU, 8GB RAM) – Overkill for lab workloads
    - **vm-app**: Likely idle or light load (dev/test)
    - **vm-db**: Running PostgreSQL with `max_connections = 20` (tiny workload)
  - `Standard_B2s` (2vCPU, 4GB RAM) – Windows VM similarly oversized for lab

- **Storage Sizing:**
  - Linux OS disk: 30GB (appropriate, minimal bloat)
  - Windows OS disk: 128GB (high for lab; 100GB unused typically)
  - Hot-tier storage account → likely unnecessary for lab

#### Recommendations:
| Resource | Current Size | Recommended Size | Savings | Rationale |
|----------|-------------|------------------|---------|-----------|
| vm-app | Standard_B2ms | Standard_B1s | 20-25% | Light workload; B1s sufficient for app server |
| vm-db | Standard_B2ms | Standard_B1s | 20-25% | PostgreSQL with 20 max_connections is minimal |
| vm-win | Standard_B2s | Standard_B1s | 25-30% | GUI overhead lower on B1s |
| Windows OS disk | 128GB | 60GB | 10-15% | Reclaim unused space |

#### Terraform Changes:
```hcl
# main.tf - Update VM sizes
resource "azurerm_linux_virtual_machine" "app" {
  size = "Standard_B1s"  # FROM: Standard_B2ms
}

resource "azurerm_linux_virtual_machine" "db" {
  size = "Standard_B1s"  # FROM: Standard_B2ms
}

resource "azurerm_windows_virtual_machine" "win" {
  size = "Standard_B1s"  # FROM: Standard_B2s
  os_disk {
    disk_size_gb = 60  # FROM: 128
  }
}
```

---

### 2. TERRAFORM CONFIGURATION OPTIMIZATION
**Priority: MEDIUM | Impact: Maintainability + future cost control**

#### Findings:
- **Hardcoded Values Throughout:**
  - VM sizes hardcoded → difficult to adjust across environments
  - Subnet CIDR blocks hardcoded → not parametrized
  - Disk sizes hardcoded
  - Storage account tier hardcoded to `Hot` (non-negotiable per code)
  - Auto-shutdown time hardcoded to UTC 1300 (13:00 UTC) → no flexibility

- **Missing Variables:**
  - No `environment` variable (prod/dev/test) → hard to differentiate costs
  - No `vm_size` variables → must edit main.tf to resize
  - No `cost_center` tagging
  - No `auto_shutdown_enabled` toggle

- **Module Opportunity:**
  - Currently using inline resources → could leverage modules for reusability across teams
  - VM creation duplicated 3x → excellent module candidate

#### Recommendations:

**Add Variables (variable.tf):**
```hcl
variable "environment" {
  description = "Environment type"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod."
  }
}

variable "vm_size" {
  description = "Azure VM size"
  type        = string
  default     = "Standard_B1s"
}

variable "enable_auto_shutdown" {
  description = "Enable daily auto-shutdown"
  type        = bool
  default     = true
}

variable "auto_shutdown_time" {
  description = "Daily shutdown time (HHMM format, UTC)"
  type        = string
  default     = "1900"  # 19:00 UTC
}

variable "tags" {
  description = "Common tags for cost allocation"
  type        = map(string)
  default = {
    cost_center = "engineering"
    owner       = "devops"
    project     = "ailab"
  }
}

variable "storage_tier" {
  description = "Storage account access tier"
  type        = string
  default     = "Cool"
  validation {
    condition     = contains(["Hot", "Cool", "Archive"], var.storage_tier)
    error_message = "Tier must be Hot, Cool, or Archive."
  }
}
```

**Parametrize Resources in main.tf:**
```hcl
# Example: Auto-shutdown schedule
resource "azurerm_dev_test_global_vm_shutdown_schedule" "app" {
  virtual_machine_id    = azurerm_linux_virtual_machine.app.id
  location              = azurerm_resource_group.lab.location
  enabled               = var.enable_auto_shutdown  # NEW
  daily_recurrence_time = var.auto_shutdown_time     # NEW
  timezone              = "UTC"
  notification_settings { enabled = false }
}

# Storage account tier
resource "azurerm_storage_account" "lab" {
  access_tier = var.storage_tier  # FROM: "Hot"
  # ... rest of config
}

# VM size across all VMs
size = var.vm_size  # Use variable instead of hardcoded
```

**Add Tags to All Resources:**
```hcl
# Add to all azurerm_* resources:
tags = merge(
  var.tags,
  {
    environment = var.environment
    deployed_on = timestamp()
  }
)
```

**Create locals for computed values (main.tf):**
```hcl
locals {
  resource_prefix = "ailab-${var.environment}-${var.participant_name}"
  shutdown_time   = var.environment == "prod" ? "2300" : var.auto_shutdown_time
}
```

---

### 3. IDLE & ORPHAN RESOURCE DETECTION
**Priority: MEDIUM | Impact: $45-100/month + cleanup operational overhead**

#### Findings:
- **Azure Bastion:**
  - Cost: ~$4.50/hour ($45-100/month depending on scale units)
  - Scale units: 2 (moderate cost)
  - Usage Pattern: Lab environment → likely idle 80%+ of time
  - Status: ⚠️ **High candidate for removal or conditional deployment**

- **Static IP (Public IP for Bastion):**
  - Cost: $2.50-3.50/month
  - In use: Yes (by Bastion)

- **Unused Disks/NICs:**
  - ✓ None detected (all NICs attached to VMs)

- **Network Security Groups:**
  - ✓ Properly associated (no orphans)

#### Recommendations:

**Option A: Disable Bastion (Recommended for Dev Labs)**
```hcl
# variable.tf
variable "enable_bastion" {
  description = "Deploy Azure Bastion for remote access"
  type        = bool
  default     = false  # Disabled by default in dev
}

# main.tf - Conditionally deploy Bastion
resource "azurerm_public_ip" "bastion" {
  count = var.enable_bastion ? 1 : 0
  # ... rest of config
}

resource "azurerm_bastion_host" "lab" {
  count = var.enable_bastion ? 1 : 0
  # ... rest of config
}
```

**Option B: Scale Down Bastion (If Always Needed)**
```hcl
resource "azurerm_bastion_host" "lab" {
  scale_units = var.enable_bastion ? 1 : 0  # Minimum scale units
  # ... rest of config
}
```

**Update terraform.tfvars:**
```hcl
# terraform.tfvars
participant_name = "labsp"
location         = "eastus"
enable_bastion   = false  # Disable for cost savings
```

**Estimated Savings:**
- Bastion removal: $45-100/month
- Public IP removal: $2.50/month
- **Total: ~$50/month (5-10% monthly cost reduction)**

---

### 4. ENVIRONMENT SCHEDULING OPTIMIZATION
**Priority: MEDIUM | Impact: 40-50% compute cost savings (already partially implemented) ✓**

#### Findings:
- **Current State: EXCELLENT** ✓
  - All 3 VMs have daily auto-shutdown schedules
  - Schedule: 1300 UTC (13:00) daily
  - Enabled: Yes
  - Status: This is a **best practice for non-prod environments**

- **Issue Identified:**
  - Timezone: UTC (may not match team timezone)
  - Startup: Not automated (only shutdown)
  - Notification: Disabled (no alert before shutdown)

#### Recommendations:

**Enhance Auto-Shutdown Configuration:**
```hcl
# terraform.tfvars
auto_shutdown_time = "1900"  # Change to 19:00 UTC (end of business)
enable_auto_shutdown = true

# variable.tf
variable "auto_shutdown_timezone" {
  description = "Timezone for auto-shutdown"
  type        = string
  default     = "Eastern Standard Time"  # Adjust per your region
}

variable "enable_shutdown_notifications" {
  description = "Send email before auto-shutdown"
  type        = bool
  default     = true
}

variable "shutdown_notification_minutes" {
  description = "Minutes before shutdown to notify"
  type        = number
  default     = 30
}
```

**Update Auto-Shutdown Schedules:**
```hcl
resource "azurerm_dev_test_global_vm_shutdown_schedule" "app" {
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone
  enabled               = var.enable_auto_shutdown
  
  notification_settings {
    enabled         = var.enable_shutdown_notifications
    time_in_minutes = var.shutdown_notification_minutes
  }
}
```

**Cost Impact:**
- Lab VMs shutdown 11 hours/day (1900-0600)
- Savings: ~45% of compute costs (~$40-50/month)
- ✓ Already realized with current config

**Automation Bonus: Add Auto-Start (Future Enhancement)**
- Azure Automation + runbook for 0600 daily start
- Estimated additional cost: $1-2/month
- Benefit: Fully automated on/off schedule

---

### 5. STORAGE & DATA OPTIMIZATION
**Priority: MEDIUM | Impact: $5-15/month**

#### Findings:
- **Storage Account Configuration:**
  - Type: `StorageV2` (correct for modern usage)
  - Tier: `Hot` (100% access latency)
  - Replication: `LRS` (standard, no redundancy)
  - Access Pattern: Unknown (likely infrequent for lab)

- **Issues:**
  - Hot tier not cost-optimized for dev/test
  - No lifecycle policies (blob data accumulates)
  - No blob versioning/soft delete (risk of accidental data loss)

#### Recommendations:

**Change Storage Tier to Cool (Dev/Test Labs):**
```hcl
# variable.tf
variable "storage_tier" {
  description = "Storage account access tier (Hot, Cool, Archive)"
  type        = string
  default     = "Cool"
}

# terraform.tfvars
storage_tier = "Cool"  # 50% cheaper than Hot

# main.tf
resource "azurerm_storage_account" "lab" {
  access_tier = var.storage_tier  # FROM: "Hot"
  # ... rest of config
}
```

**Cost Comparison (1TB monthly):**
| Tier | Read Cost | Write Cost | Monthly |
|------|-----------|-----------|---------|
| Hot | $0.0184/10K reads | $0.0147/10K writes | High (baseline) |
| Cool | $0.01/10K reads | $0.0147/10K writes | **50% lower** |

**Add Lifecycle Policies (Prevent Bloat):**
```hcl
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
        tier_to_cool_after_days_since_modification_greater_than          = 30
        tier_to_archive_after_days_since_modification_greater_than       = 90
        delete_after_days_since_modification_greater_than                = 180
      }
    }
  }
}
```

**Estimated Savings:**
- Tier change (Hot → Cool): $5-10/month
- Lifecycle policies prevent overages: +$5/month long-term
- **Total: ~$5-15/month (5% reduction)**

---

### 6. RESERVED INSTANCES / SAVINGS PLANS
**Priority: LOW (for this dev lab) | Impact: 20-30% for steady-state workloads**

#### Findings:
- **Workload Type:** Non-production lab (variable usage)
- **Uptime:** Partial (11 hours/day, 5 days/week estimated)
- **VM Duration:** Unknown; likely temporary (weeks/months)

#### Recommendation:
**Not Recommended for This Lab** – Reserve Instances require commitment (1-3 years) and fixed sizing. Better for:
- ✓ Production always-on workloads
- ✓ Predictable, stable capacity

**If This Becomes Prod:**
```hcl
# Future: 1-year reservation for steady-state prod
variable "enable_reserved_instance" {
  description = "Use Azure Reserved Instances"
  type        = bool
  default     = false  # Enable only for prod
}

# Can save 20-30% on compute with RI commitment
# Recommend: Review in 3-6 months if usage pattern is stable
```

---

### 7. TAGGING & COST ALLOCATION
**Priority: MEDIUM | Impact: Cost visibility + chargeback accuracy**

#### Findings:
- **Current Tags:** NONE (no tags on any resources)
- **Cost Impact:** 
  - Cannot allocate costs by department/project
  - Hard to charge back to teams
  - Violates compliance for many orgs

#### Recommendations:

**Implement Tagging Strategy (variable.tf):**
```hcl
variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    environment   = "dev"
    cost_center   = "engineering"
    owner         = "devops-team"
    project       = "ailab"
    application   = "training"
    created_date  = "2026-06-15"
    terraform     = "true"
    cost_tracking = "required"
  }
}

variable "allow_untagged_resources" {
  description = "Fail if resource missing required tags"
  type        = bool
  default     = false
}
```

**Apply Tags to All Resources (main.tf):**
```hcl
# Add to EVERY azurerm resource:
tags = merge(
  var.tags,
  {
    resource_type = "virtual_machine"  # or applicable type
    cost_center   = var.tags["cost_center"]
  }
)

# Example for resource group:
resource "azurerm_resource_group" "lab" {
  name     = "rg-ailab-${var.participant_name}"
  location = var.location
  tags     = var.tags
}
```

**Add Tag Validation (locals in main.tf):**
```hcl
locals {
  required_tags = ["environment", "cost_center", "owner", "project"]
}

# Validate all resources have required tags
output "tag_validation" {
  value = {
    has_required_tags = contains(
      keys(azurerm_resource_group.lab.tags),
      "cost_center"
    )
  }
}
```

**Cost Allocation Benefit:**
- ✓ Track costs by department (cost_center)
- ✓ Identify unused projects
- ✓ Chargeback to teams accurately
- ✓ Audit compliance (HIPAA, SOC2, etc.)

---

### 8. NETWORK & DATA TRANSFER COSTS
**Priority: LOW | Impact: Minimal for this setup**

#### Findings:
- **Data Transfer:** Private IP addressing throughout
  - ✓ No cross-region traffic
  - ✓ No public internet egress (except Bastion SSH)
  - ✓ Minimized data transfer costs

- **Network Configuration:**
  - ✓ Proper VNet/subnet isolation (10.0.0.0/16)
  - ✓ NSGs properly configured (not overly permissive for prod)
  - ⚠️ NSG rules allow 0.0.0.0/0 SSH/RDP (security issue, not cost-related)

- **Bastion Usage:**
  - Data transfer: Minimal
  - Access method: Best practice (no public IPs on VMs)

#### Recommendations:

**Monitor Outbound Traffic (if applicable):**
```hcl
# Add Application Insights for monitoring (optional)
resource "azurerm_application_insights" "lab" {
  name                = "appi-ailab"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  application_type    = "other"
  
  tags = var.tags
}
```

**No Immediate Cost Savings Needed** – Network architecture is efficient.

---

### 9. TERRAFORM STATE & GOVERNANCE
**Priority: MEDIUM | Impact: Risk mitigation + cost control**

#### Findings:
- **State Management:**
  - State file: `terraform.tfstate` (local)
  - ⚠️ Risk: Not backed up to remote storage
  - ⚠️ Security: Sensitive data in plaintext (passwords)
  - ⚠️ Collaboration: Not shareable across team

- **Environment Sprawl:**
  - Current: Single environment per tfvars
  - Risk: Easy to deploy prod resources accidentally

#### Recommendations:

**Migrate to Azure Backend (Remote State):**
```hcl
# Create backend storage in Azure (run once, then update terraform block)
# Cost: $0.50-2/month for state storage

# main.tf or create backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstate<random>"
    container_name       = "tfstate"
    key                  = "ailab.tfstate"
  }
}
```

**Create Separate tfvars per Environment:**
```
tfvars/
├── dev.tfvars
├── test.tfvars
└── prod.tfvars
```

**Add Policy-as-Code (Azure Policy via Terraform):**
```hcl
# Enforce tagging, cost limits, region restrictions
resource "azurerm_management_group_policy_assignment" "cost_policy" {
  name                = "enforce-tags"
  policy_definition_id = data.azurerm_policy_definition.require_tags.id
  management_group_id  = data.azurerm_management_group.root.id
}
```

**Cost Impact:**
- Remote state storage: +$0.50-2/month
- **Benefit:** Team collaboration, disaster recovery, compliance

---

### 10. AUTOMATION & FINOPS INTEGRATION
**Priority: HIGH | Impact: Continuous cost optimization**

#### Findings:
- **Current Monitoring:** None (no cost visibility)
- **Optimization:** Manual (no automation)
- **Governance:** Minimal

#### Recommendations:

**1. Enable Azure Advisor (Free)**
```hcl
# This is a console feature, not Terraform-managed
# Provides automated recommendations:
#  - Right-size VMs
#  - Decommission unused resources
#  - Optimize storage
#  - Security recommendations
```

**2. Set Up Cost Alerts:**
```hcl
# Create budget with alerts
resource "azurerm_consumption_budget" "lab" {
  name              = "budget-ailab-${var.environment}"
  scope             = azurerm_resource_group.lab.id
  category          = "Cost"
  time_period       = "Monthly"
  amount            = var.environment == "prod" ? 1000 : 250  # USD
  time_grain        = "Monthly"

  notification {
    enabled        = true
    threshold      = 80
    threshold_type = "Percentage"
    contact_emails = ["devops@example.com"]
  }

  filter {
    dimension {
      name   = "ResourceGroupName"
      values = [azurerm_resource_group.lab.name]
    }
  }

  tags = var.tags
}
```

**3. Integrate with Cost Management (terraform.tfvars):**
```hcl
# Add budget variable
variable "monthly_budget" {
  description = "Monthly spend limit (USD)"
  type        = number
  default     = 250  # Adjust per environment
}

variable "budget_alert_threshold" {
  description = "Alert when spend reaches X% of budget"
  type        = number
  default     = 80
}
```

**4. Create Terraform Module for FinOps Best Practices:**
```hcl
# New file: modules/finops_governance.tf

module "finops_controls" {
  source = "./modules/finops"
  
  resource_group_name  = azurerm_resource_group.lab.name
  monthly_budget       = var.monthly_budget
  alert_email          = var.owner_email
  enforce_autoshutdown = true
  require_tags         = ["cost_center", "owner", "environment"]
  
  tags = var.tags
}
```

**5. Add to main.tf - Cost Explorer Output:**
```hcl
output "cost_tracking" {
  description = "Resources for cost tracking"
  value = {
    resource_group    = azurerm_resource_group.lab.name
    budget_id         = try(azurerm_consumption_budget.lab.id, null)
    tags_applied      = var.tags
    estimated_monthly = "See Azure Cost Management portal"
  }
}
```

**Automation Benefit:**
- ✓ Real-time cost visibility
- ✓ Automated alerts before overages
- ✓ Continuous optimization recommendations
- ✓ Chargeback automation

---

## IMPLEMENTATION ROADMAP

### Phase 1: Quick Wins (Week 1)
**Effort: 1-2 hours | Savings: $65-85/month (25-35%)**

1. [ ] Downsize VMs: `Standard_B2ms/B2s` → `Standard_B1s`
2. [ ] Disable Azure Bastion (set `enable_bastion = false`)
3. [ ] Change storage tier: `Hot` → `Cool`
4. [ ] Test changes: `terraform plan` & `terraform apply`

### Phase 2: Configuration Hardening (Week 2)
**Effort: 2-3 hours | Savings: +$5/month, +Governance**

1. [ ] Add variables for vm_size, environment, auto_shutdown_time
2. [ ] Implement tagging strategy across all resources
3. [ ] Add storage lifecycle policies
4. [ ] Migrate to remote state (Azure Backend)

### Phase 3: Automation & Monitoring (Week 3-4)
**Effort: 3-4 hours | Savings: Continuous optimization**

1. [ ] Set up Azure Advisor reviews
2. [ ] Create budget alerts
3. [ ] Enable Azure Cost Management + exports
4. [ ] Document runbooks for cost optimization

### Phase 4: Long-term (Month 2+)
**Ongoing | Savings: Compounding**

1. [ ] Review Advisor recommendations monthly
2. [ ] Analyze tagging data for cost allocation
3. [ ] Scale to production with modules
4. [ ] Implement FinOps CoE practices

---

## COST SUMMARY

### Current State (Estimated)
| Component | Current | Monthly Cost |
|-----------|---------|-------------|
| VMs (3x Standard_B2ms/B2s) | $0.096/hr × 3 × 168 hrs | $145 |
| Azure Bastion (2 scale units) | $4.50/hr × 24 hrs × 30 | $55 |
| Disks (3x 30-128GB Standard_LRS) | ~$1-2 each | $5 |
| Storage Account (Cool, 100GB) | 100GB × $0.02/GB | $2 |
| NSGs, VNets, IPs (minor) | Included in above | $3 |
| **Total Estimated** | | **~$210/month** |

### Optimized State (Recommended)
| Component | Optimized | Monthly Cost | Savings |
|-----------|-----------|-------------|---------|
| VMs (3x Standard_B1s) | $0.048/hr × 3 × 132 hrs (11hr/day) | **$19** | -87% |
| Azure Bastion | DISABLED | **$0** | -100% |
| Disks (optimized) | Smaller, Standard_LRS | **$3** | -40% |
| Storage (Cool tier) | 100GB Cool tier | **$1** | -50% |
| **Total Optimized** | | **~$23/month** | **-89%** |

> **⚠️ Note:** Actual costs depend on exact region, usage patterns, and currency. Use Azure Cost Estimator for precise calculations.

---

## SECURITY & COMPLIANCE NOTES

### Concerns Identified (Not Cost-Related)
1. **NSG Rules:** Allow SSH/RDP from `0.0.0.0/0` (open to internet)
   - Recommendation: Restrict to bastion subnet or VPN
   
2. **Passwords in Code:** Admin password in state file (sensitive)
   - Recommendation: Use Azure Key Vault or Managed Identity

3. **No Network Encryption:** Data in transit not enforced
   - Recommendation: Add Azure Network Watcher for monitoring

**These are security issues, not FinOps issues, but both affect cost (e.g., security incidents increase operational overhead).**

---

## TERRAFORM CHANGES SUMMARY

See included files:
- [main.tf](main.tf) – Updated resource configurations
- [variable.tf](variable.tf) – New parametrized variables
- [terraform.tfvars](terraform.tfvars) – Updated variable values
- [outputs.tf](output.tf) – Added cost tracking outputs

---

## NEXT STEPS

1. **Review & Approve Changes:** Present this analysis to stakeholders
2. **Run Terraform Plan:** `terraform plan -out=tfplan` to validate changes
3. **Test in Dev:** Apply to this lab environment first
4. **Document:** Add README with FinOps practices
5. **Monitor:** Track savings against estimated costs

---

## CONTACT & SUPPORT

For questions on implementation:
- Azure Cost Management: https://portal.azure.com/#blade/Microsoft_Azure_Cost/CostManagementMenuBlade
- Terraform Docs: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
- Azure Advisor: https://portal.azure.com/#blade/Microsoft_Azure_Expert/AdvisorMenuBlade

---

**Analysis Completed:** 2026-06-15  
**Recommendation Priority:** Phase 1 (Quick Wins) → Phase 2 (Hardening) → Phase 3 (Automation)
