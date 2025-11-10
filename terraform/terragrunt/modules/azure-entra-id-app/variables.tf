# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "display_name" {
  description = "Display name for the app registration"
  type        = string
}

# -----------------------------------------------------------------------------
# App Registration Configuration
# -----------------------------------------------------------------------------

variable "sign_in_audience" {
  description = "Who can sign in (AzureADMyOrg, AzureADMultipleOrgs, AzureADandPersonalMicrosoftAccount)"
  type        = string
  default     = "AzureADMyOrg"

  validation {
    condition = contains([
      "AzureADMyOrg",
      "AzureADMultipleOrgs",
      "AzureADandPersonalMicrosoftAccount",
      "PersonalMicrosoftAccount"
    ], var.sign_in_audience)
    error_message = "Invalid sign_in_audience value"
  }
}

variable "additional_owners" {
  description = "Additional owner object IDs (current user is automatically added)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Redirect URIs
# -----------------------------------------------------------------------------

variable "web_redirect_uris" {
  description = "Web redirect URIs (for server-side web apps, Azure App Service EasyAuth)"
  type        = list(string)
  default     = []
}

variable "spa_redirect_uris" {
  description = "SPA redirect URIs (for single-page applications using PKCE)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Implicit Grant Settings
# -----------------------------------------------------------------------------

variable "implicit_grant_access_token_enabled" {
  description = "Enable implicit grant flow for access tokens"
  type        = bool
  default     = true
}

variable "implicit_grant_id_token_enabled" {
  description = "Enable implicit grant flow for ID tokens"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Token Configuration
# -----------------------------------------------------------------------------

variable "requested_access_token_version" {
  description = "Access token version (1 or 2)"
  type        = number
  default     = 2

  validation {
    condition     = contains([1, 2], var.requested_access_token_version)
    error_message = "Access token version must be 1 or 2"
  }
}

# -----------------------------------------------------------------------------
# API Exposure (for APIM)
# -----------------------------------------------------------------------------

variable "identifier_uris" {
  description = "Application ID URIs (audience for token validation). Format: api://{client-id} or https://{custom-domain}/api"
  type        = list(string)
  default     = []
}

variable "oauth2_permission_scopes" {
  description = "OAuth2 permission scopes (delegated permissions) exposed by this API"
  type = list(object({
    id                         = string
    admin_consent_description  = string
    admin_consent_display_name = string
    enabled                    = optional(bool, true)
    type                       = optional(string, "User")
    user_consent_description   = optional(string)
    user_consent_display_name  = optional(string)
    value                      = string
  }))
  default = []
}

variable "app_roles" {
  description = "App roles (application permissions) for RBAC"
  type = list(object({
    id                   = string
    allowed_member_types = list(string)
    description          = string
    display_name         = string
    enabled              = optional(bool, true)
    value                = string
  }))
  default = []
}

# -----------------------------------------------------------------------------
# API Permissions
# -----------------------------------------------------------------------------

variable "add_microsoft_graph_user_read" {
  description = "Add Microsoft Graph User.Read delegated permission"
  type        = bool
  default     = true
}

variable "required_resource_access" {
  description = "Custom API permissions beyond User.Read"
  type = list(object({
    resource_app_id = string
    resource_access = list(object({
      id   = string
      type = string
    }))
  }))
  default = []
}

# -----------------------------------------------------------------------------
# Service Principal Configuration
# -----------------------------------------------------------------------------

variable "app_role_assignment_required" {
  description = "Require app role assignment for users/groups"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Client Secret Configuration
# -----------------------------------------------------------------------------

variable "create_client_secret" {
  description = "Create a client secret for the app"
  type        = bool
  default     = true
}

variable "client_secret_display_name" {
  description = "Display name for the client secret"
  type        = string
  default     = "terraform-generated"
}

variable "client_secret_end_date" {
  description = "Expiration date for client secret (RFC3339 format, e.g., 2025-12-31T23:59:59Z). Defaults to 1 year from creation."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Key Vault Integration
# -----------------------------------------------------------------------------

variable "key_vault_id" {
  description = "Key Vault ID to store client secret (optional)"
  type        = string
  default     = null
}

variable "client_secret_kv_name" {
  description = "Key Vault secret name for client secret (defaults to display_name-client-secret)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to Key Vault secret (if stored)"
  type        = map(string)
  default     = {}
}
