################################################################################
# MODULE: single_assignment_pim
#
# Creates azurerm_role_assignment for active roles,
# azurerm_pim_eligible_role_assignment for PIM roles,
# and azurerm_role_management_policy for each role definition,
# including active_assignment_rules (if in active list),
# eligible_assignment_rules+activation_rules (if in pim list),
# minimal notification_rules.
################################################################################

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.50.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.28.0"
    }
  }
}

variable "assignment" {
  description = <<EOT
A single assignment set for one principal at one scope.

- principal_name + principal_type (Group or ServicePrincipal) for principal
- pim_approver_group_name (optional) if pim_roles exist & approval needed
- active_roles + pim_roles => each list of role names
- one azurerm_role_management_policy per unique role name with:
    - active_assignment_rules if role is in active list
    - eligible_assignment_rules + activation_rules if role is in pim list
    - minimal notification_rules

Additionally:
- "active_expiration_required" or "active_expire_after"
- "eligible_expiration_required" or "eligible_expire_after"
- "activation_maximum_duration", "activation_require_approval", etc.
- minimal notifications for active/eligible/activation

We do not support "User" principal_type.
EOT

  type = object({
    ############################################################################
    # Basic info
    ############################################################################
    scope          = string
    principal_name = string
    principal_type = string   # "Group" or "ServicePrincipal"

    pim_approver_group_name = optional(string) # used if activation_require_approval = true

    ############################################################################
    # Simple RBAC fields
    ############################################################################
    active_description   = optional(string)
    rbac_admin_condition = optional(string)

    # Lists of roles by name
    active_roles = list(string)
    pim_roles    = list(string)

    ############################################################################
    # Role Management Policy Config (Active)
    ############################################################################
    active_expiration_required            = optional(bool)
    active_expire_after                  = optional(string) # "P365D", etc.
    active_require_justification         = optional(bool)
    active_require_multifactor_authentication = optional(bool)
    active_require_ticket_info           = optional(bool)

    ############################################################################
    # Role Management Policy Config (Eligible)
    ############################################################################
    eligible_expiration_required = optional(bool)
    eligible_expire_after       = optional(string) # e.g. "P180D"

    ############################################################################
    # Role Management Policy Config (Activation for PIM)
    ############################################################################
    activation_maximum_duration                 = optional(string) # e.g. "PT8H"
    activation_require_approval                 = optional(bool)
    activation_require_justification            = optional(bool)
    activation_require_multifactor_authentication = optional(bool)
    activation_require_ticket_info              = optional(bool)

    ############################################################################
    # Minimal Notification config
    ############################################################################
    notify_active_assignments_notification_level    = optional(string) # "All" or "Critical"
    notify_eligible_assignments_notification_level  = optional(string)
    notify_eligible_activations_notification_level  = optional(string)

    ############################################################################
    # PIM-Eligible Schedule Fields
    ############################################################################
    pim_justification    = optional(string)
    pim_ticket_number    = optional(string)
    pim_ticket_system    = optional(string)
    pim_start_date_time  = optional(string)
    pim_expiration_days  = optional(number)
    pim_expiration_hours = optional(number)
    pim_end_date_time    = optional(string)
  })
}

locals {
  a = var.assignment

  has_pim_roles = length(local.a.pim_roles) > 0
  has_pim_group = local.a.pim_approver_group_name != null
}

################################################################################
# 1) Lookup principal (Group or SP)
################################################################################

data "azuread_group" "principal_grp" {
  count        = local.a.principal_type == "Group" ? 1 : 0
  display_name = local.a.principal_name
}
data "azuread_service_principal" "principal_sp" {
  count        = local.a.principal_type == "ServicePrincipal" ? 1 : 0
  display_name = local.a.principal_name
}

locals {
  principal_id = local.a.principal_type == "Group" ? data.azuread_group.principal_grp[0].object_id : data.azuread_service_principal.principal_sp[0].id
}

################################################################################
# 2) Lookup PIM Approver Group if needed
################################################################################

data "azuread_group" "pim_approver" {
  count        = local.has_pim_roles && local.has_pim_group ? 1 : 0
  display_name = local.a.pim_approver_group_name
}
locals {
  pim_approver_group_id = (length(data.azuread_group.pim_approver) > 0) ? data.azuread_group.pim_approver[0].object_id : null
}

################################################################################
# 3) Convert active_roles & pim_roles to sets
################################################################################

locals {
  active_set = toset(local.a.active_roles)
  pim_set    = toset(local.a.pim_roles)
  union_list = concat(local.a.active_roles, var.assignment.pim_roles)
  union_set  = toset(local.union_list)
  # union_set => all unique roles across both lists
}

################################################################################
# 4) Lookup role definitions for each unique role name
################################################################################

data "azurerm_role_definition" "all_defs" {
  for_each = local.union_set
  name  = each.value
  scope = local.a.scope
}

################################################################################
# 5) Normal RBAC Assignments -> azurerm_role_assignment for each role in active_set
################################################################################

resource "azurerm_role_assignment" "normal" {
  for_each = data.azurerm_role_definition.all_defs
    # only create assignment if role is in active_set
    if contains(local.active_set, each.key)

  scope        = local.a.scope
  principal_id = local.principal_id
  principal_type = local.a.principal_type

  role_definition_id = each.value.role_definition_resource_id
  description        = local.a.active_description

  # If role is "Role Based Access Control Administrator" => apply condition
  condition = (
    lower(each.key) == "role based access control administrator"
    && local.a.rbac_admin_condition != null
  ) ? local.a.rbac_admin_condition : null

  condition_version = (
    lower(each.key) == "role based access control administrator"
    && local.a.rbac_admin_condition != null
  ) ? "2.0" : null
}

################################################################################
# 6) PIM-Eligible Assignments -> azurerm_pim_eligible_role_assignment
################################################################################

resource "azurerm_pim_eligible_role_assignment" "pim" {
  for_each = data.azurerm_role_definition.all_defs
    # only create PIM assignment if role is in pim_set
    if contains(local.pim_set, each.key)

  scope        = local.a.scope
  principal_id = local.principal_id
  role_definition_id = each.value.role_definition_resource_id

  justification = local.a.pim_justification

  schedule {
    start_date_time = local.a.pim_start_date_time

    expiration {
      duration_days  = local.a.pim_expiration_days
      duration_hours = local.a.pim_expiration_hours
      end_date_time  = local.a.pim_end_date_time
    }
  }

  ticket {
    number = local.a.pim_ticket_number
    system = local.a.pim_ticket_system
  }
}

################################################################################
# 7) Role Management Policy -> azurerm_role_management_policy
#    One per role in union_set. The policy sets:
#      - active_assignment_rules (if in active_set)
#      - eligible_assignment_rules + activation_rules (if in pim_set)
#      - minimal notification_rules
################################################################################

resource "azurerm_role_management_policy" "policy" {
  for_each = data.azurerm_role_definition.all_defs

  scope              = local.a.scope
  role_definition_id = each.value.role_definition_resource_id

  # 7A) Active Assignment Rules
  dynamic "active_assignment_rules" {
    for_each = contains(local.active_set, each.key) ? [1] : []
    content {
      # if user did not supply either 'active_expire_after' or 'active_expiration_required',
      # we must provide one. We'll default to 'expiration_required = false'
      expiration_required = coalesce(local.a.active_expiration_required, false)

      # If user sets 'active_expire_after', we prefer that:
      # The doc says "One of expiration_required or expire_after must be provided."
      expire_after = local.a.active_expire_after != null ? local.a.active_expire_after : null

      require_justification            = coalesce(local.a.active_require_justification, false)
      require_multifactor_authentication = coalesce(local.a.active_require_multifactor_authentication, false)
      require_ticket_info              = coalesce(local.a.active_require_ticket_info, false)
    }
  }

  # 7B) Eligible Assignment Rules (for PIM)
  dynamic "eligible_assignment_rules" {
    for_each = contains(local.pim_set, each.key) ? [1] : []
    content {
      expiration_required = coalesce(local.a.eligible_expiration_required, false)
      expire_after        = local.a.eligible_expire_after != null ? local.a.eligible_expire_after : null
    }
  }

  # 7C) Activation Rules (for PIM
}
