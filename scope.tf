################################################################################
# MODULE: single_assignment_pim
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

###############################################################################
# Scope Configuration Variable
###############################################################################
variable "scope_config" {
  description = <<EOT
An object describing the target scope.
{
  scope_level         = string  # "subscription", "resource_group", or "resource"
  subscription_name   = string  # The subscription display name to use (must match one of your subscriptions)
  resource_group_name = optional(string)  # Required if scope_level is "resource_group" or "resource"
  resource_name       = optional(string)  # Required if scope_level is "resource"
}
EOT
  type = object({
    scope_level         = string
    subscription_name   = string
    resource_group_name = optional(string)
    resource_name       = optional(string)
  })
}

###############################################################################
# Principal Variables (Separate)
###############################################################################
variable "principal_name" {
  description = "The name of the principal (Group or ServicePrincipal)."
  type        = string
}

variable "principal_type" {
  description = "The type of the principal. Must be either 'Group' or 'ServicePrincipal'."
  type        = string
}

variable "pim_approver_group_name" {
  description = "Optional: The name of the group to be used as the PIM approver (only needed if eligible roles are provided and approval is required)."
  type        = string
  default     = null
}

###############################################################################
# Assignment Object: Roles, Policy, etc.
###############################################################################
variable "assignment" {
  description = <<EOT
An object containing configuration for roles and policy settings.

Active (RBAC) Config:
  - active_active_description: Description applied to all active role assignments.
  - active_rbac_admin_condition: (Optional) Condition to apply if a restricted role is assigned.
  - active_roles: List(string) of role names for always-active RBAC assignments.

Eligible (PIM) Config:
  - pim_roles: List(string) of role names for PIM-eligible assignments.
  - eligible_justification: (Optional) Justification for PIM assignments.
  - eligible_ticket_number: (Optional) Ticket number for PIM assignments.
  - eligible_ticket_system: (Optional) Ticket system for PIM assignments.
  - eligible_start_date_time: (Optional) Start time for the eligible schedule.
  - eligible_expiration_days: (Optional) Expiration in days for the eligible schedule.
  - eligible_expiration_hours: (Optional) Expiration in hours for the eligible schedule.
  - eligible_end_date_time: (Optional) End time for the eligible schedule.

Policy Settings – Active:
  - policy_active_expiration_required: (Optional) Boolean.
  - policy_active_expire_after: (Optional) ISO8601 duration (e.g. "P365D").
  - policy_active_require_justification: (Optional) Boolean.
  - policy_active_require_multifactor_authentication: (Optional) Boolean.
  - policy_active_require_ticket_info: (Optional) Boolean.

Policy Settings – Eligible:
  - policy_eligible_expiration_required: (Optional) Boolean.
  - policy_eligible_expire_after: (Optional) ISO8601 duration (e.g. "P180D").

Policy Activation (for Eligible Roles):
  - policy_activation_maximum_duration: (Optional) ISO8601 duration (e.g. "PT8H").
  - policy_activation_require_approval: (Optional) Boolean.
  - policy_activation_require_justification: (Optional) Boolean.
  - policy_activation_require_multifactor_authentication: (Optional) Boolean.
  - policy_activation_require_ticket_info: (Optional) Boolean.

Policy Notifications:
  - policy_notify_active_assignments_notification_level: (Optional) String.
  - policy_notify_eligible_assignments_notification_level: (Optional) String.
  - policy_notify_eligible_activations_notification_level: (Optional) String.

Restricted Roles:
  - rbac_restricted_roles: (Optional) List(string) of active role names to be restricted. The module will automatically build an ABAC condition string for these roles.

Example:
{
  active_active_description  = "Active roles for MyGroup"
  active_rbac_admin_condition = "Some condition for admin roles"
  active_roles               = ["Reader", "Role Based Access Control Administrator"]

  eligible_justification     = "Elevate when needed"
  eligible_ticket_number     = "CHG-1234"
  eligible_ticket_system     = "ServiceNow"
  eligible_start_date_time   = "2025-01-01T00:00:00Z"
  eligible_expiration_days   = 7
  eligible_expiration_hours  = null
  eligible_end_date_time     = null
  pim_roles                  = ["Contributor"]

  policy_active_expiration_required  = false
  policy_active_expire_after         = "P365D"
  policy_active_require_justification = true
  policy_active_require_multifactor_authentication = false
  policy_active_require_ticket_info  = true

  policy_eligible_expiration_required = false
  policy_eligible_expire_after         = "P180D"

  policy_activation_maximum_duration   = "PT8H"
  policy_activation_require_approval   = true
  policy_activation_require_justification = true
  policy_activation_require_multifactor_authentication = true
  policy_activation_require_ticket_info = true

  policy_notify_active_assignments_notification_level   = "Critical"
  policy_notify_eligible_assignments_notification_level = "All"
  policy_notify_eligible_activations_notification_level = "All"

  rbac_restricted_roles = ["Role Based Access Control Administrator"]
}
EOT

  type = object({
    active_active_description  = optional(string)
    active_rbac_admin_condition= optional(string)
    active_roles               = list(string)

    eligible_justification     = optional(string)
    eligible_ticket_number     = optional(string)
    eligible_ticket_system     = optional(string)
    eligible_start_date_time   = optional(string)
    eligible_expiration_days   = optional(number)
    eligible_expiration_hours  = optional(number)
    eligible_end_date_time     = optional(string)
    pim_roles                  = list(string)

    policy_active_expiration_required  = optional(bool)
    policy_active_expire_after         = optional(string)
    policy_active_require_justification = optional(bool)
    policy_active_require_multifactor_authentication = optional(bool)
    policy_active_require_ticket_info  = optional(bool)

    policy_eligible_expiration_required = optional(bool)
    policy_eligible_expire_after         = optional(string)

    policy_activation_maximum_duration                 = optional(string)
    policy_activation_require_approval                 = optional(bool)
    policy_activation_require_justification            = optional(bool)
    policy_activation_require_multifactor_authentication = optional(bool)
    policy_activation_require_ticket_info              = optional(bool)

    policy_notify_active_assignments_notification_level   = optional(string)
    policy_notify_eligible_assignments_notification_level = optional(string)
    policy_notify_eligible_activations_notification_level = optional(string)

    rbac_restricted_roles = optional(list(string))
  })
}

################################################################################
# Locals: Union of Role Sets
################################################################################

locals {
  active_set = toset(var.assignment.active_roles)
  pim_set    = toset(var.assignment.pim_roles)
  union_list = concat(var.assignment.active_roles, var.assignment.pim_roles)
  union_set  = toset(local.union_list)
}

################################################################################
# Scope Calculation: Determine the full scope ID using scope_config and subscription lookup
################################################################################

data "azurerm_subscriptions" "all" {}

locals {
  subscription_match = [
    for s in data.azurerm_subscriptions.all.subscriptions : s
    if s.display_name == var.scope_config.subscription_name
  ]
  subscription_id = length(local.subscription_match) > 0 ? local.subscription_match[0].subscription_id : null
}

data "azurerm_resource_group" "rg" {
  count = var.scope_config.scope_level == "resource_group" || var.scope_config.scope_level == "resource" ? 1 : 0
  name  = var.scope_config.resource_group_name
  subscription_id = local.subscription_id
}

data "azurerm_resources" "res_list" {
  count               = var.scope_config.scope_level == "resource" ? 1 : 0
  resource_group_name = var.scope_config.resource_group_name
  subscription_id = local.subscription_id
}

locals {
  calculated_scope = (
    var.scope_config.scope_level == "subscription" ? "/subscriptions/${local.subscription_id}" :
    var.scope_config.scope_level == "resource_group" ? data.azurerm_resource_group.rg[0].id :
    var.scope_config.scope_level == "resource" ? lookup(
      { for r in data.azurerm_resources.res_list[0].resources : r.name => r.id },
      var.scope_config.resource_name,
      null
    ) : null
  )
}

################################################################################
# Lookup Role Definitions for Union of Roles
################################################################################

data "azurerm_role_definition" "all_defs" {
  for_each = local.union_set
  name     = each.value
  scope    = local.calculated_scope
}

################################################################################
# Lookup Role Definitions for Restricted Roles (for condition)
################################################################################

data "azurerm_role_definition" "restricted_defs" {
  for_each = toset(var.rbac_restricted_roles)
  name     = each.value
  scope    = local.calculated_scope
}

locals {
  restricted_ids = [for r in data.azurerm_role_definition.restricted_defs : r.role_definition_id]
  restricted_ids_str = format("{%s}", join(", ", [for id in local.restricted_ids : tostring(id)]))
  rbac_condition_string = length(var.rbac_restricted_roles) > 0 ? <<EOT
(
 (
  !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
 )
 OR 
 (
  @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals ${local.restricted_ids_str}
  AND
  @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal', 'Group'}
 )
)
AND
(
 (
  !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
 )
 OR 
 (
  @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals ${local.restricted_ids_str}
  AND
  @Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {'ServicePrincipal', 'Group'}
 )
)
EOT
  : null
}

################################################################################
# Lookup Principal (Group or ServicePrincipal) using separate variables
################################################################################

data "azuread_group" "principal_grp" {
  count        = var.principal_type == "Group" ? 1 : 0
  display_name = var.principal_name
}
data "azuread_service_principal" "principal_sp" {
  count        = var.principal_type == "ServicePrincipal" ? 1 : 0
  display_name = var.principal_name
}

locals {
  principal_id = var.principal_type == "Group"
    ? data.azuread_group.principal_grp[0].object_id
    : data.azuread_service_principal.principal_sp[0].id
}

################################################################################
# Lookup PIM Approver Group (if eligible roles exist and name provided)
################################################################################

data "azuread_group" "pim_approver" {
  count        = (length(var.assignment.pim_roles) > 0 && var.pim_approver_group_name != null) ? 1 : 0
  display_name = var.pim_approver_group_name
}

locals {
  pim_approver_group_id = length(data.azuread_group.pim_approver) > 0 ? data.azuread_group.pim_approver[0].object_id : null
}

################################################################################
# 1) ACTIVE: Create azurerm_role_assignment for roles in active_set
################################################################################

resource "azurerm_role_assignment" "normal" {
  for_each = { for k, v in data.azurerm_role_definition.all_defs : k => v if contains(local.active_set, k) }

  scope         = local.calculated_scope
  principal_id  = local.principal_id
  principal_type = var.principal_type

  role_definition_id = each.value.role_definition_resource_id
  description        = var.assignment.active_active_description

  condition = contains(var.rbac_restricted_roles, each.key) ? rbac_condition_string : null
  condition_version = contains(var.rbac_restricted_roles, each.key) ? "2.0" : null
}

################################################################################
# 2) ELIGIBLE: Create azurerm_pim_eligible_role_assignment for roles in pim_set
################################################################################

resource "azurerm_pim_eligible_role_assignment" "eligible" {
  for_each = { for k, v in data.azurerm_role_definition.all_defs : k => v if contains(local.pim_set, k) }

  scope         = local.calculated_scope
  principal_id  = local.principal_id
  role_definition_id = each.value.role_definition_resource_id
  justification = var.assignment.eligible_justification

  schedule {
    start_date_time = var.assignment.eligible_start_date_time

    expiration {
      duration_days  = var.assignment.eligible_expiration_days
      duration_hours = var.assignment.eligible_expiration_hours
      end_date_time  = var.assignment.eligible_end_date_time
    }
  }

  ticket {
    number = var.assignment.eligible_ticket_number
    system = var.assignment.eligible_ticket_system
  }
}

################################################################################
# 3) POLICY for Active Roles: Create azurerm_role_management_policy for each role in active_set
################################################################################

resource "azurerm_role_management_policy" "active_policy" {
  for_each = { for k, v in data.azurerm_role_definition.all_defs : k => v if contains(local.active_set, k) }

  scope              = local.calculated_scope
  role_definition_id = each.value.role_definition_resource_id

  active_assignment_rules {
    expiration_required = coalesce(var.assignment.policy_active_expiration_required, false)
    expire_after        = var.assignment.policy_active_expire_after != null ? var.assignment.policy_active_expire_after : null
    require_justification = coalesce(var.assignment.policy_active_require_justification, false)
    require_multifactor_authentication = coalesce(var.assignment.policy_active_require_multifactor_authentication, false)
    require_ticket_info = coalesce(var.assignment.policy_active_require_ticket_info, false)
  }

  notification_rules {
    active_assignments {
      admin_notifications {
        notification_level    = coalesce(var.assignment.policy_notify_active_assignments_notification_level, "Critical")
        default_recipients    = false
        additional_recipients = []
      }
    }
  }
}

################################################################################
# 4) POLICY for Eligible Roles: Create azurerm_role_management_policy for each role in pim_set
################################################################################

resource "azurerm_role_management_policy" "pim_policy" {
  for_each = { for k, v in data.azurerm_role_definition.all_defs : k => v if contains(local.pim_set, k) }

  scope              = local.calculated_scope
  role_definition_id = each.value.role_definition_resource_id

  eligible_assignment_rules {
    expiration_required = coalesce(var.assignment.policy_eligible_expiration_required, false)
    expire_after        = var.assignment.policy_eligible_expire_after != null ? var.assignment.policy_eligible_expire_after : null
  }

  activation_rules {
    maximum_duration = coalesce(var.assignment.policy_activation_maximum_duration, "PT8H")
    require_approval = coalesce(var.assignment.policy_activation_require_approval, false)
    require_justification = coalesce(var.assignment.policy_activation_require_justification, false)
    require_multifactor_authentication = coalesce(var.assignment.policy_activation_require_multifactor_authentication, false)
    require_ticket_info = coalesce(var.assignment.policy_activation_require_ticket_info, false)

    dynamic "approval_stage" {
      for_each = coalesce(var.assignment.policy_activation_require_approval, false) ? [1] : []
      content {
        primary_approver {
          object_id = local.pim_approver_group_id
          type      = "Group"
        }
      }
    }
  }

  notification_rules {
    eligible_assignments {
      approver_notifications {
        notification_level    = coalesce(var.assignment.policy_notify_eligible_assignments_notification_level, "Critical")
        default_recipients    = false
        additional_recipients = []
      }
    }
    eligible_activations {
      assignee_notifications {
        notification_level    = coalesce(var.assignment.policy_notify_eligible_activations_notification_level, "All")
        default_recipients    = true
        additional_recipients = []
      }
    }
  }
}

################################################################################
# 5) Outputs
################################################################################

output "active_role_assignment_ids" {
  description = "IDs of all normal RBAC assignments."
  value       = [for ra in azurerm_role_assignment.normal : ra.id]
}

output "eligible_role_assignment_ids" {
  description = "IDs of all PIM-eligible role assignments."
  value       = [for e in azurerm_pim_eligible_role_assignment.eligible : e.id]
}

output "active_policy_ids" {
  description = "IDs of the role management policies for active roles."
  value       = [for p in azurerm_role_management_policy.active_policy : p.id]
}

output "pim_policy_ids" {
  description = "IDs of the role management policies for eligible roles."
  value       = [for p in azurerm_role_management_policy.pim_policy : p.id]
}
