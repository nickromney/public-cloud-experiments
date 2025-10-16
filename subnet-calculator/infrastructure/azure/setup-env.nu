#!/usr/bin/env nu
#
# Setup environment variables for Azure deployment (Nushell version)
#
# Usage:
#   source setup-env.nu
#   # or
#   overlay use setup-env.nu

# Colors for output
def log_info [message: string] {
    print $"(ansi green)[INFO](ansi reset) ($message)"
}

def log_warn [message: string] {
    print $"(ansi yellow)[WARN](ansi reset) ($message)"
}

def log_error [message: string] {
    print $"(ansi red)[ERROR](ansi reset) ($message)"
}

# Check if logged in to Azure
def check_azure_login [] {
    let result = (do { az account show } | complete)
    if $result.exit_code != 0 {
        log_error "Not logged in to Azure. Run 'az login'"
        return false
    }
    return true
}

# Main setup
def main [] {
    log_info "Azure Subnet Calculator - Environment Setup (Nushell)"
    print ""

    # Check Azure CLI login
    if not (check_azure_login) {
        return
    }

    # Get subscription info
    let subscription = (az account show | from json)
    let subscription_name = $subscription.name
    let subscription_id = $subscription.id
    let user_email = $subscription.user.name

    log_info $"Subscription: ($subscription_name)"
    log_info $"Subscription ID: ($subscription_id)"
    log_info $"User: ($user_email)"
    print ""

    # Auto-detect resource group
    let resource_groups = (az group list | from json)
    let rg_count = ($resource_groups | length)

    let resource_group = if $rg_count == 0 {
        log_error "No resource groups found in subscription"
        log_error "Create one with: az group create --name rg-subnet-calc --location uksouth"
        return
    } else if $rg_count == 1 {
        let rg = ($resource_groups | first)
        log_info $"Found single resource group: ($rg.name) (($rg.location))"
        log_info "This appears to be a sandbox or single-environment subscription."
        $rg.name
    } else {
        log_warn "Multiple resource groups found:"
        $resource_groups | each { |rg| print $"  - ($rg.name) (($rg.location))" }
        print ""

        # Prompt for selection
        input "Enter resource group name: "
    }

    # Get location from resource group
    let rg_info = (az group show --name $resource_group | from json)
    let location = $rg_info.location

    # Default configuration
    let custom_domain = "publiccloudexperiments.net"
    let publisher_email = $user_email

    # Set environment variables
    $env.RESOURCE_GROUP = $resource_group
    $env.LOCATION = $location
    $env.CUSTOM_DOMAIN = $custom_domain
    $env.PUBLISHER_EMAIL = $publisher_email

    # Display configuration
    print ""
    log_info "Environment configured:"
    print ""
    print $"  RESOURCE_GROUP = ($resource_group)"
    print $"  LOCATION = ($location)"
    print $"  CUSTOM_DOMAIN = ($custom_domain)"
    print $"  PUBLISHER_EMAIL = ($publisher_email)"
    print ""

    log_info "Environment variables are now set in your current session"
    print ""
    print "Quick start commands:"
    print "  ./stack-03-swa-typescript-noauth.sh    # Deploy Stack 3 (No Auth)"
    print "  ./stack-04-swa-typescript-jwt.sh       # Deploy Stack 4 (JWT)"
    print "  ./stack-05-swa-typescript-entraid.sh   # Deploy Stack 5 (Entra ID)"
    print "  ./stack-06-flask-appservice.sh         # Deploy Stack 6 (Flask)"
    print ""
    print "Or use Makefile:"
    print "  make deploy-stack3"
    print "  make deploy-stack4"
    print ""
}

# Export the main function so it runs when sourced
export def --env setup [] {
    main
}

# Auto-run when executed directly
if ($nu.is-interactive | is-empty) {
    main
}
