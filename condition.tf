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

################################################################################
# Variables
################################################################################

variable "assignment" {
  description = <<EOT
A single assignment set for one principal at one scope.

Basic Info:
  - scope: The target scope (e.g. subscription ID).
  - principal_name: The name of the principal (Group or ServicePrincipal).
  - principal_type: Must be "Group" or "ServicePrincipal" (User not supported).
  - pim_approver_group_name: (Optional) Name of the group that serves as the PIM approver (only needed if pim_roles are provided and policy_activation_require_approval is true).

Active (RBAC) Config:
  - active_active_description: A description applied to all active role assignments.
  - active_roles: List(string) of role names for always-active RBAC assignments.
  - active_rbac_admin_condition: (Optional) A condition to be applied if a role is restricted.

Eligible (PIM) Config:
  - pim_roles: List(string) of role names for PIM-eligible assignments.
  - eligible_justification: (Optional) Justification for PIM assignments.
  - eligible_ticket_number: (Optional) Ticket number for PIM assignments.
  - eligible_ticket_system: (Optional) Ticket system for PIM assignments.
  - eligible_start_date_time: (Optional) Start time for the eligible schedule.
  - eligible_expiration_days: (Optional) Expiration in days for the eligible schedule.
  - eligible_expiration_hours: (Optional) Expiration in hours for the eligible schedule.
  - eligible_end_date_time: (Optional) End time for the eligible schedule.

Policy Settings – Active Assignments:
  - policy_active_expiration_required: (Optional) Whether active assignments must expire.
  - policy_active_expire_after: (Optional) ISO8601 duration for active assignments (e.g. "P365D").
  - policy_active_require_justification: (Optional) Whether justification is required for active assignments.
  - policy_active_require_multifactor_authentication: (Optional) Whether MFA is required for active assignments.
  - policy_active_require_ticket_info: (Optional) Whether ticket info is required for active assignments.

Policy Settings – Eligible Assignments:
  - policy_eligible_expiration_required: (Optional) Whether eligible assignments must expire.
  - policy_eligible_expire_after: (Optional) ISO8601 duration for eligible assignments (e.g. "P180D").

Policy Activation (for Eligible Roles):
  - policy_activation_maximum_duration: (Optional) Maximum duration for activation (e.g. "PT8H").
  - policy_activation_require_approval: (Optional) Whether activation requires approval.
  - policy_activation_require_justification: (Optional) Whether justification is required upon activation.
  - policy_activation_require_multifactor_authentication: (Optional) Whether MFA is required upon activation.
  - policy_activation_require_ticket_info: (Optional) Whether ticket info is required upon activation.

Policy Notifications:
  - policy_notify_active_assignments_notification_level: (Optional) Notification level for active assignments ("All" or "Critical").
  - policy_notify_eligible_assignments_notification_level: (Optional) Notification level for eligible assignments.
  - policy_notify_eligible_activations_notification_level: (Optional) Notification level for eligible activations.

Restricted Roles (for condition):
  - rbac_restricted_roles: (Optional) List(string) of active role names for which a condition should be applied. The module will look up their IDs and automatically build the condition string.

Example structure:
{
  scope                      = "subscriptions/..."
  principal_name             = "MyGroup"
  principal_type             = "Group"
  pim_approver_group_name    = "PIMApprovers"   // Optional

  active_active_description  = "Active roles for MyGroup"
  active_rbac_admin_condition = "..."            // Optional
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

  policy_activation_maximum_duration                 = "PT8H"
  policy_activation_require_approval                 = true
  policy_activation_require_justification            = true
  policy_activation_require_multifactor_authentication = true
  policy_activation_require_ticket_info              = true

  policy_notify_active_assignments_notification_level   = "Critical"
  policy_notify_eligible_assignments_notification_level = "All"
  policy_notify_eligible_activations_notification_level = "All"

  rbac_restricted_roles = ["Role Based Access Control Administrator"]
}
EOT

  type = object({
    scope          = string
    principal_name = string
    principal_type = string

    pim_approver_group_name = optional(string)

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
# Locals for Role Union Sets
################################################################################

locals {
  active_set = toset(a.active_roles)
  pim_set    = toset(a.pim_roles)
  union_list = concat(a.active_roles, a.pim_roles)
  union_set  = toset(local.union_list)
}

################################################################################
# Lookup Role Definitions for Union of Roles
################################################################################

data "azurerm_role_definition" "all_defs" {
  for_each = local.union_set
  name  = each.value
  scope = a.scope
}

################################################################################
# Lookup Role Definitions for Restricted Roles (for condition)
################################################################################

data "azurerm_role_definition" "restricted_defs" {
  for_each = toset(var.rbac_restricted_roles)
  name  = each.value
  scope = a.scope
}

locals {
  restricted_ids = [for r in data.azurerm_role_definition.restricted_defs : r.role_definition_resource_id]
  restricted_ids_str = "{" + join(", ", local.restricted_ids) + "}"
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
# Lookup Principal (Group or ServicePrincipal)
################################################################################

data "azuread_group" "principal_grp" {
  count        = a.principal_type == "Group" ? 1 : 0
  display_name = a.principal_name
}
data "azuread_service_principal" "principal_sp" {
  count        = a.principal_type == "ServicePrincipal" ? 1 : 0
  display_name = a.principal_name
}

locals {
  principal_id = a.principal_type == "Group"
    ? data.azuread_group.principal_grp[0].object_id
    : data.azuread_service_principal.principal_sp[0].id
}

################################################################################
# Lookup PIM Approver Group (if eligible roles exist and group name provided)
################################################################################

data "azuread_group" "pim_approver" {
  count        = (length(a.pim_roles) > 0 && a.pim_approver_group_name != null) ? 1 : 0
  display_name = a.pim_approver_group_name
}

locals {
  pim_approver_group_id = length(data.azuread_group.pim_approver) > 0 ? data.azuread_group.pim_approver[0].object_id : null
}

################################################################################
# 1) Active Assignments: Create azurerm_role_assignment for roles in active_set
################################################################################

resource "azurerm_role_assignment" "normal" {
  for_each = {
    for k, v in data.azurerm_role_definition.all_defs : k => v if contains(local.active_set, k)
  }

  scope         = a.scope
  principal_id  = local.principal_id
  principal_type = a.principal_type

  role_definition_id = each.value.role_definition_resource_id
  description        = a.active_active_description

  condition = contains(var.rbac_restricted_roles, each.key) ? local.rbac_condition_string : null
  condition_version = contains(var.rbac_restricted_roles, each.key) ? "2.0" : null
}

################################################################################
# 2) Eligible (PIM) Assignments: Create azurerm_pim_eligible_role_assignment for roles in pim_set
################################################################################

resource "azurerm_pim_eligible_role_assignment" "eligible" {
  for_each = {
    for k, v in data.azurerm_role_definition.all_defs : k => v if contains(local.pim_set, k)
  }

  scope         = a.scope
  principal_id  = local.principal_id

  role_definition_id = each.value.role_definition_resource_id
  justification = a.eligible_justification

  schedule {
    start_date_time = a.eligible_start_date_time

    expiration {
      duration_days  = a.eligible_expiration_days
      duration_hours = a.eligible_expiration_hours
      end_date_time  = a.eligible_end_date_time
    }
  }

  ticket {
    number = a.eligible_ticket_number
    system = a.eligible_ticket_system
  }
}

################################################################################
# 3) Policy for Active Roles: Create azurerm_role_management_policy for each role in active_set
################################################################################

resource "azurerm_role_management_policy" "active_policy" {
  for_each = {
    for k, v in data.azurerm_role_definition.all_defs : k => v if contains(local.active_set, k)
  }

  scope              = a.scope
  role_definition_id = each.value.role_definition_resource_id

  active_assignment_rules {
    expiration_required = coalesce(a.policy_active_expiration_required, false)
    expire_after        = a.policy_active_expire_after != null ? a.policy_active_expire_after : null
    require_justification = coalesce(a.policy_active_require_justification, false)
    require_multifactor_authentication = coalesce(a.policy_active_require_multifactor_authentication, false)
    require_ticket_info = coalesce(a.policy_active_require_ticket_info, false)
  }

  notification_rules {
    active_assignments {
      admin_notifications {
        notification_level    = coalesce(a.policy_notify_active_assignments_notification_level, "Critical")
        default_recipients    = false
        additional_recipients = []
      }
    }
  }
}

################################################################################
# 4) Policy for Eligible Roles: Create azurerm_role_management_policy for each role in pim_set
################################################################################

resource "azurerm_role_management_policy" "pim_policy" {
  for_each = {
    for k, v in data.azurerm_role_definition.all_defs : k => v if contains(local.pim_set, k)
  }

  scope              = a.scope
  role_definition_id = each.value.role_definition_resource_id

  eligible_assignment_rules {
    expiration_required = coalesce(a.policy_eligible_expiration_required, false)
    expire_after        = a.policy_eligible_expire_after != null ? a.policy_eligible_expire_after : null
  }

  activation_rules {
    maximum_duration = coalesce(a.policy_activation_maximum_duration, "PT8H")
    require_approval = coalesce(a.policy_activation_require_approval, false)
    require_justification = coalesce(a.policy_activation_require_justification, false)
    require_multifactor_authentication = coalesce(a.policy_activation_require_multifactor_authentication, false)
    require_ticket_info = coalesce(a.policy_activation_require_ticket_info, false)

    dynamic "approval_stage" {
      for_each = coalesce(a.policy_activation_require_approval, false) ? [1] : []
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
        notification_level    = coalesce(a.policy_notify_eligible_assignments_notification_level, "Critical")
        default_recipients    = false
        additional_recipients = []
      }
    }
    eligible_activations {
      assignee_notifications {
        notification_level    = coalesce(a.policy_notify_eligible_activations_notification_level, "All")
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
