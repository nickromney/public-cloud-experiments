variable "client_name" {
  description = "Client name/prefix for naming"
  type        = string
}

variable "environment" {
  description = "Project environment"
  type        = string
}

variable "stack" {
  description = "Project stack name"
  type        = string
}

variable "location" {
  description = "Azure region to use"
  type        = string
}
