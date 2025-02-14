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

variable "assignment" {
  description = <<EOT
A single assignment set for one principal at one scope.
EOT

  type = object({
    scope          = string
    principal_name = string
    principal_type = string   # "Group" or "ServicePrincipal"

    pim_approver_group_name = optional(string)

    active_roles_description   = optional(string)
    rbac_admin_condition       = optional(string)

    pim_maximum_duration                 = optional(string)
    pim_require_approval                 = optional(bool)
    pim_require_justification            = optional(bool)
    pim_require_multifactor_authentication = optional(bool)
    pim_require_ticket_info              = optional(bool)

    pim_justification    = optional(string)
    pim_ticket_number    = optional(string)
    pim_ticket_system    = optional(string)
    pim_start_date_time  = optional(string)
    pim_expiration_days  = optional(number)
    pim_expiration_hours = optional(number)
    pim_end_date_time    = optional(string)

    active_roles = list(string)
    pim_roles    = list(string)
  })

  #
  # Validation 1: principal_type can only be "Group" or "ServicePrincipal".
  #
  validation {
    condition = (
      var.assignment.principal_type == "Group"
      || var.assignment.principal_type == "ServicePrincipal"
    )
    error_message = "Supported principal_type values are only 'Group' or 'ServicePrincipal'."
  }

  #
  # Validation 2: If pim_require_approval = true, pim_approver_group_name must not be null.
  #
  validation {
    condition = (
      var.assignment.pim_require_approval == false
      || (
        var.assignment.pim_require_approval == true
        && var.assignment.pim_approver_group_name != null
      )
    )
    error_message = "If pim_require_approval is true, pim_approver_group_name must not be null."
  }

  #
  # Validation 3: Restrict active_roles to the allowed set.
  #
  validation {
    condition = alltrue([for r in var.assignment.active_roles : (r in ["Role Based Access Control Administrator", "Storage Blob Data Contributor" ])])
    error_message = "active_roles must be among: [\"Role Based Access Control Administrator\", \"Storage Blob Data Contributor\"]."
  }

  #
  # Validation 4: Restrict pim_roles to the allowed set.
  #
  validation {
    condition = alltrue([for r in var.assignment.pim_roles : (r in ["Key Vault Administrator", "Contributor"])])
    error_message = "pim_roles must be among: [\"Key Vault Administrator\", \"Contributor\"]."
  }
}

locals {
  a = var.assignment

  has_pim_roles = length(local.a.pim_roles) > 0
  has_pim_group = local.a.pim_approver_group_name != null
}

################################################################################
# 1) Look up principal object by name (Group or ServicePrincipal)
################################################################################

data "azuread_group" "principal_grp" {
  count        = local.a.principal_type == "Group" ? 1 : 0
  display_name = local.a.principal_name
}

data "azuread_service_principal" "principal_sp" {
  count         = local.a.principal_type == "ServicePrincipal" ? 1 : 0
  display_name  = local.a.principal_name
}

locals {
  principal_id = local.a.principal_type == "Group"
    ? data.azuread_group.principal_grp[0].object_id
    : data.azuread_service_principal.principal_sp[0].id
}

################################################################################
# 2) Look up PIM Approver Group (only if pim_roles exist & require_approval = true)
################################################################################

data "azuread_group" "pim_approver" {
  count        = local.has_pim_roles && local.has_pim_group ? 1 : 0
  display_name = local.a.pim_approver_group_name
}

locals {
  pim_approver_group_id = local.has_pim_roles && local.has_pim_group
    ? data.azuread_group.pim_approver[0].object_id
    : null
}

################################################################################
# 3) Convert active_roles & pim_roles to sets
################################################################################

locals {
  active_roles_set = toset(local.a.active_roles)
  pim_roles_set    = toset(local.a.pim_roles)
}

################################################################################
# 4) Look up role definitions by name
################################################################################

data "azurerm_role_definition" "active_defs" {
  for_each = local.active_roles_set
  name     = each.value
  scope    = local.a.scope
}

data "azurerm_role_definition" "pim_defs" {
  for_each = local.pim_roles_set
  name     = each.value
  scope    = local.a.scope
}

################################################################################
# 5) Normal RBAC Assignments -> azurerm_role_assignment
################################################################################

resource "azurerm_role_assignment" "normal" {
  for_each = data.azurerm_role_definition.active_defs

  scope          = local.a.scope
  principal_id   = local.principal_id
  principal_type = local.a.principal_type

  role_definition_id = each.value.role_definition_resource_id
  description        = local.a.active_roles_description

  condition = (
    lower(each.key) == "role based access control administrator"
    && local.a.rbac_admin_condition != null
  )
    ? local.a.rbac_admin_condition
    : null

  condition_version = (
    lower(each.key) == "role based access control administrator"
    && local.a.rbac_admin_condition != null
  )
    ? "2.0"
    : null
}

################################################################################
# 6) PIM-Eligible Assignments -> azurerm_pim_eligible_role_assignment
################################################################################

resource "azurerm_pim_eligible_role_assignment" "pim" {
  for_each = data.azurerm_role_definition.pim_defs

  scope        = local.a.scope
  principal_id = local.principal_id

  role_definition_id = each.value.role_definition_resource_id
  justification      = local.a.pim_justification

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
# 7) Role Management Policy -> azurerm_role_management_policy (Only if PIM roles exist)
################################################################################

resource "azurerm_role_management_policy" "pim_policy" {
  for_each = local.has_pim_roles ? data.azurerm_role_definition.pim_defs : {}

  scope              = local.a.scope
  role_definition_id = each.value.role_definition_resource_id

  activation_rules {
    maximum_duration                   = coalesce(local.a.pim_maximum_duration, "PT8H")
    require_approval                   = coalesce(local.a.pim_require_approval, false)
    require_justification             = coalesce(local.a.pim_require_justification, false)
    require_multifactor_authentication = coalesce(local.a.pim_require_multifactor_authentication, false)
    require_ticket_info                = coalesce(local.a.pim_require_ticket_info, false)

    dynamic "approval_stage" {
      for_each = local.a.pim_require_approval ? [1] : []
      content {
        primary_approver {
          object_id = local.pim_approver_group_id
          type      = "Group"
        }
      }
    }
  }
}



module "rbac_only" {
  source = "./modules/single_assignment_pim"

  assignment = {
    scope          = data.azurerm_subscription.primary.id
    principal_name = "MyGroup"
    principal_type = "Group"

    active_description = "RBAC roles only for MyGroup"
    rbac_admin_condition = null

    active_roles = ["Reader", "Contributor"]
    pim_roles    = []  # No PIM roles => PIM settings are ignored
  }
}


module "pim_only" {
  source = "./modules/single_assignment_pim"

  assignment = {
    scope          = data.azurerm_subscription.primary.id
    principal_name = "MyServicePrincipal"
    principal_type = "ServicePrincipal"

    pim_approver_group_name = "PIMApprovalGroup"

    pim_maximum_duration                 = "PT8H"
    pim_require_approval                 = true
    pim_require_justification            = true
    pim_require_multifactor_authentication = true
    pim_require_ticket_info              = true

    pim_justification   = "PIM access required for elevated actions"
    pim_ticket_number   = "CHG-56789"
    pim_ticket_system   = "ServiceNow"
    pim_start_date_time = "2025-01-01T00:00:00Z"
    pim_expiration_days  = 7
    pim_expiration_hours = null
    pim_end_date_time    = null

    active_roles = []  # No always-active RBAC roles
    pim_roles    = ["Contributor", "User Access Administrator"]
  }
}



module "rbac_and_pim" {
  source = "./modules/single_assignment_pim"

  assignment = {
    scope          = data.azurerm_subscription.primary.id
    principal_name = "MyAdminGroup"
    principal_type = "Group"

    pim_approver_group_name = "PIMApprovalGroup"

    active_description = "Always-active RBAC roles for admins"
    rbac_admin_condition = <<-EOT
      (
        @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] StringEqualsIgnoreCase '00000000-0000-0000-0000-000000000000'
      )
    EOT

    pim_maximum_duration                 = "PT8H"
    pim_require_approval                 = true
    pim_require_justification            = true
    pim_require_multifactor_authentication = true
    pim_require_ticket_info              = true

    pim_justification   = "PIM access for critical admin actions"
    pim_ticket_number   = "CHG-99999"
    pim_ticket_system   = "ServiceNow"
    pim_start_date_time = "2025-01-01T00:00:00Z"
    pim_expiration_days  = 7
    pim_expiration_hours = null
    pim_end_date_time    = null

    active_roles = ["Reader", "Role Based Access Control Administrator"]
    pim_roles    = ["Contributor", "Owner"]
  }
}


module "rbac_admin_with_condition" {
  source = "./modules/single_assignment_pim"

  assignment = {
    scope          = data.azurerm_subscription.primary.id
    principal_name = "RBACAdminsGroup"
    principal_type = "Group"

    active_description = "RBAC roles for Admins with condition on RBAC Admin role"
    
    rbac_admin_condition = <<-EOT
      (
        (
          !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
        )
        OR
        (
          @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {'00000000-0000-0000-0000-000000000000'}
        )
      )
      AND
      (
        (
          !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
        )
        OR
        (
          @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {'00000000-0000-0000-0000-000000000000'}
        )
      )
    EOT

    active_roles = ["Reader", "Role Based Access Control Administrator"]
    pim_roles    = []  # No PIM roles in this example
  }
}
