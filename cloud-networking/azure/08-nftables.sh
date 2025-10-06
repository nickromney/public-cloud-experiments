#!/usr/bin/env bash
#
# Configure nftables on an EXISTING VM
#
# PURPOSE:
#   This script is for UPDATING or REPAIRING nftables configuration on a VM
#   that has already been deployed. Use this to:
#   - Update firewall rules on an existing VM
#   - Fix nftables configuration that didn't apply correctly
#   - Change NAT/forwarding rules without redeploying
#
# WHEN TO USE:
#   - VM already exists and needs rule updates
#   - Troubleshooting/debugging firewall rules
#   - Manual configuration changes
#
# WHEN NOT TO USE:
#   - Creating a NEW VM → Use 07-vm.sh instead
#     (07-vm.sh configures nftables via cloud-init during VM creation)
#
# CONFIGURATION:
#   - Receive traffic from subnets 1-4
#   - Drop traffic from subnet 2
#   - Enable IP forwarding
#   - Configure NAT (masquerade) for NVA functionality

set -euo pipefail

# Configuration
readonly RESOURCE_GROUP="${RESOURCE_GROUP:-rg-simple-vnet}"
readonly VM_NAME="${VM_NAME:-vm-test3}"

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

log_info "Configuring nftables on ${VM_NAME}"
log_info ""

# Create nftables configuration script with NAT for NVA functionality
NFT_SCRIPT=$(cat <<'EOF'
#!/bin/bash

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Install nftables if not present
apt-get update && apt-get install -y nftables

# Flush everything
nft flush ruleset

# Create filter table and chains
nft add table ip filter

# Input chain - receive traffic from all subnets
nft add chain ip filter input { type filter hook input priority 0\; policy drop\; }
nft add rule ip filter input iif lo accept
nft add rule ip filter input ct state established,related accept
nft add rule ip filter input ip saddr 10.0.10.0/24 accept
nft add rule ip filter input ip saddr 10.0.20.0/24 drop
nft add rule ip filter input ip saddr 10.0.30.0/24 accept
nft add rule ip filter input ip saddr 10.0.40.0/24 accept
nft add rule ip filter input ip saddr 10.0.50.0/24 accept
nft add rule ip filter input tcp dport 22 accept

# Forward chain - allow forwarding from subnet4, subnet5 (and others)
nft add chain ip filter forward { type filter hook forward priority 0\; policy drop\; }
nft add rule ip filter forward ct state established,related accept
nft add rule ip filter forward ip saddr 10.0.30.0/24 ip daddr 10.0.20.0/24 accept
nft add rule ip filter forward ip saddr 10.0.40.0/24 accept  # Allow subnet4 to forward out
nft add rule ip filter forward ip saddr 10.0.50.0/24 accept  # Allow subnet5 to forward out
nft add rule ip filter forward ip saddr 10.0.10.0/24 accept  # Allow subnet1
nft add rule ip filter forward ip saddr 10.0.20.0/24 accept  # Allow subnet2

# Output chain
nft add chain ip filter output { type filter hook output priority 0\; policy accept\; }

# Create NAT table for outbound traffic (masquerade)
nft add table ip nat

# Postrouting chain for NAT (masquerade outbound traffic)
nft add chain ip nat postrouting { type nat hook postrouting priority 100\; policy accept\; }
nft add rule ip nat postrouting ip saddr 10.0.0.0/16 oifname eth0 masquerade

# Prerouting chain for NAT (needed for completeness)
nft add chain ip nat prerouting { type nat hook prerouting priority -100\; policy accept\; }

# Save rules
nft list ruleset > /etc/nftables.conf

# Enable nftables service
systemctl enable nftables
systemctl restart nftables

echo "nftables configured successfully with NAT"
nft list ruleset
EOF
)

# Run script on VM
log_info "Applying nftables configuration..."
az vm run-command invoke \
  --name "${VM_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --command-id RunShellScript \
  --scripts "${NFT_SCRIPT}" \
  --query "value[0].message" \
  --output tsv

log_info ""
log_info "Done! nftables configured with NAT"
log_info ""
log_info "Rules applied:"
log_info "  - Receives traffic from subnets 1, 3, 4"
log_info "  - Drops traffic from subnet 2"
log_info "  - Allows forwarding from all subnets"
log_info "  - NAT (masquerade) enabled for 10.0.0.0/16 outbound"
log_info ""
log_info "NVA is now ready to route traffic from other subnets to internet"
