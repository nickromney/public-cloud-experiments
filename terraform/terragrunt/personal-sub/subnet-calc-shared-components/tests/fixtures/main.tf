# Test fixtures - generates random UUIDs for testing
# Prevents gitleaks false positives from hardcoded UUIDs

terraform {
  required_version = ">= 1.8.0"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

resource "random_uuid" "tenant_id" {}
resource "random_uuid" "subscription_id" {}
resource "random_uuid" "client_id" {}
resource "random_uuid" "object_id" {}
