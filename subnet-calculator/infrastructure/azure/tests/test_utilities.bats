#!/usr/bin/env bats
#
# Tests for utility libraries
# Tests region mapping and selection utilities

setup() {
  load setup
}

teardown() {
  load teardown
}

# Region mapping tests for map-swa-region.sh

@test "map-swa-region.sh maps uksouth to westeurope" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "uksouth")
  [ "$result" = "westeurope" ]
}

@test "map-swa-region.sh maps eastus to eastus2" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "eastus")
  [ "$result" = "eastus2" ]
}

@test "map-swa-region.sh is case insensitive - UKSOUTH" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "UKSOUTH")
  [ "$result" = "westeurope" ]
}

@test "map-swa-region.sh is case insensitive - UkSouth" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "UkSouth")
  [ "$result" = "westeurope" ]
}

@test "map-swa-region.sh maps ukwest to westeurope" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "ukwest")
  [ "$result" = "westeurope" ]
}

@test "map-swa-region.sh maps northeurope to westeurope" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "northeurope")
  [ "$result" = "westeurope" ]
}

@test "map-swa-region.sh maps francecentral to westeurope" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "francecentral")
  [ "$result" = "westeurope" ]
}

@test "map-swa-region.sh maps westus to westus2" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "westus")
  [ "$result" = "westus2" ]
}

@test "map-swa-region.sh maps eastus3 to eastus2" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "eastus3")
  [ "$result" = "eastus2" ]
}

@test "map-swa-region.sh keeps centralus as-is" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "centralus")
  [ "$result" = "centralus" ]
}

@test "map-swa-region.sh keeps westus2 as-is" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "westus2")
  [ "$result" = "westus2" ]
}

@test "map-swa-region.sh keeps eastus2 as-is" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "eastus2")
  [ "$result" = "eastus2" ]
}

@test "map-swa-region.sh keeps westeurope as-is" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "westeurope")
  [ "$result" = "westeurope" ]
}

@test "map-swa-region.sh keeps eastasia as-is" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "eastasia")
  [ "$result" = "eastasia" ]
}

@test "map-swa-region.sh maps southeastasia to eastasia" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "southeastasia")
  [ "$result" = "eastasia" ]
}

@test "map-swa-region.sh maps japaneast to eastasia" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "japaneast")
  [ "$result" = "eastasia" ]
}

@test "map-swa-region.sh defaults unknown regions to westeurope" {
  source lib/map-swa-region.sh
  result=$(map_swa_region "unknownregion")
  [ "$result" = "westeurope" ]
}

@test "map-swa-region.sh fails without region parameter" {
  source lib/map-swa-region.sh
  run map_swa_region
  [ "$status" -ne 0 ]
}

@test "map-swa-region.sh can be run as standalone script" {
  run lib/map-swa-region.sh uksouth
  assert_success
  [[ "$output" == "westeurope" ]]
}

@test "map-swa-region.sh shows usage when run without args" {
  run lib/map-swa-region.sh
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Usage" ]]
}

# Selection utilities tests

@test "selection-utils.sh defines select_from_list function" {
  source lib/selection-utils.sh
  declare -f select_from_list >/dev/null
}

@test "selection-utils.sh defines select_resource_group function" {
  source lib/selection-utils.sh
  declare -f select_resource_group >/dev/null
}

@test "selection-utils.sh defines select_static_web_app function" {
  source lib/selection-utils.sh
  declare -f select_static_web_app >/dev/null
}

@test "selection-utils.sh defines select_function_app function" {
  source lib/selection-utils.sh
  declare -f select_function_app >/dev/null
}

@test "selection-utils.sh defines select_storage_account function" {
  source lib/selection-utils.sh
  declare -f select_storage_account >/dev/null
}

@test "selection-utils.sh defines select_apim_instance function" {
  source lib/selection-utils.sh
  declare -f select_apim_instance >/dev/null
}

@test "selection-utils.sh defines select_app_service_plan function" {
  source lib/selection-utils.sh
  declare -f select_app_service_plan >/dev/null
}
