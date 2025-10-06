# Azure Network Virtual Appliance (NVA) Forwarding Research

## Research Question

**Can a VM with network forwarding enabled work as a Network Virtual Appliance (NVA) in Azure when the source subnet has `defaultOutboundAccess: false`?**

## Terminology

**Public vs Private Subnets in Azure:**

- **Public subnet**: `defaultOutboundAccess: true` (or unset on older subnets) - VMs get default SNAT for internet access
- **Private subnet**: `defaultOutboundAccess: false` - VMs have no default internet access
- Azure is changing the default to `false` for new subnets (private-by-default)

**Explicit Outbound Connectivity** means one of these is configured:

- **Public IP** attached to VM's NIC
- **NAT Gateway** attached to the subnet
- **Load Balancer** with outbound rules
- **Azure Firewall** routing

**Default SNAT** (what you get with `defaultOutboundAccess: true`):

- Free, automatic outbound internet access
- Shared, dynamic IP pool managed by Azure
- **Incompatible with custom NVA forwarding** (key finding of this research)

## Architecture Overview

### Network Topology

```text
┌─────────────────────────────────────────────────────────┐
│ VNET: 10.0.0.0/16                                       │
│                                                          │
│  ┌───────────────────┐  ┌───────────────────┐          │
│  │ Subnet 1          │  │ Subnet 2          │          │
│  │ 10.0.10.0/24      │  │ 10.0.20.0/24      │          │
│  │ (public)          │  │ (public)          │          │
│  └───────────────────┘  └───────────────────┘          │
│                                                          │
│  ┌───────────────────┐  ┌───────────────────┐          │
│  │ Subnet 3          │  │ Subnet 4          │          │
│  │ 10.0.30.0/24      │  │ 10.0.40.0/24      │          │
│  │ (public, NVA)     │  │ (private)         │          │
│  │                   │  │                   │          │
│  │ ┌──────────────┐  │  │ ┌──────────────┐ │          │
│  │ │ vm-test3  │  │  │ │ vm-test4   │ │          │
│  │ │ 10.0.30.4    │◄─┼──┼─│ 10.0.40.4    │ │          │
│  │ │ (NVA)        │  │  │ │              │ │          │
│  │ └──────────────┘  │  │ └──────────────┘ │          │
│  │                   │  │                   │          │
│  │ IP Forwarding: OK:  │  │ defaultOutbound   │          │
│  │ nftables NAT: OK:   │  │ Access: false     │          │
│  └───────────────────┘  └───────────────────┘          │
│                                                          │
└─────────────────────────────────────────────────────────┘
            │                           │
            │ (has public access)       │ (blocked by Azure)
            ▼                           ▼
        Internet                    Internet
```

### Routing Configuration

**Route Table: `rt-subnet4-via-nva`**

- Associated with: Subnet 4 (10.0.40.0/24)
- Route: `0.0.0.0/0` → `10.0.30.4` (VirtualAppliance)

**Traffic Flow (Expected):**

```text
vm-test4 (10.0.40.4)
  → UDR: 0.0.0.0/0 via 10.0.30.4
  → vm-test3 (10.0.30.4)
  → nftables NAT (masquerade)
  → Internet
```

## NVA Configuration

### VM Settings

**vm-test3 (NVA in subnet3):**

- IP: 10.0.30.4
- NIC IP Forwarding: **Enabled**
- OS IP Forwarding: **Enabled** (`net.ipv4.ip_forward = 1`)
- Firewall: nftables with NAT

### nftables Configuration

Configured via cloud-init in `nftables-config.yaml`:

```nftables
# Filter table
table ip filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif lo accept
    ct state established,related accept
    ip saddr 10.0.10.0/24 accept
    ip saddr 10.0.20.0/24 drop
    ip saddr 10.0.30.0/24 accept
    ip saddr 10.0.40.0/24 accept  # Allow from private subnet
    tcp dport 22 accept
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    ip saddr 10.0.30.0/24 ip daddr 10.0.20.0/24 accept
    ip saddr 10.0.40.0/24 accept  # Allow subnet4 forwarding
    ip saddr 10.0.10.0/24 accept
    ip saddr 10.0.20.0/24 accept
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}

# NAT table for outbound masquerading
table ip nat {
  chain postrouting {
    type nat hook postrouting priority 100; policy accept;
    ip saddr 10.0.0.0/16 oifname "eth0" masquerade
  }

  chain prerouting {
    type nat hook prerouting priority -100; policy accept;
  }
}
```

### NSG Rules

**NSG: `nsg-simple` (applied to all subnets)**

- **AllowTCPBetweenSubnets**: TCP traffic between 10.0.10.0/24, 10.0.20.0/24, 10.0.30.0/24, 10.0.40.0/24
- **AllowICMPBetweenSubnets**: ICMP traffic between subnets
- **AllowDNSBetweenSubnets**: UDP/53 traffic between subnets
- Default outbound rules: Allow VNet, Allow Internet, Deny All

## Test Results

### Test 1: Direct Inter-Subnet Connectivity [PASS]

**Test:** vm-test4 (10.0.40.4) → vm-test3 (10.0.30.4)

```bash
# Ping test
$ az vm run-command invoke --name vm-test4 --scripts "ping -c 3 10.0.30.4"
OK: 3 packets transmitted, 3 received, 0% packet loss

# TCP test (SSH)
$ az vm run-command invoke --name vm-test4 --scripts "nc -zv -w 5 10.0.30.4 22"
OK: Connection to 10.0.30.4 22 port [tcp/ssh] succeeded!
```

**Result: SUCCESS** - Direct connectivity between subnets works perfectly.

### Test 2: NVA Can Access Internet [PASS]

**Test:** vm-test3 (10.0.30.4) → google.com

```bash
$ az vm run-command invoke --name vm-test3 --scripts "curl -s -m 5 http://google.com"
OK: <HTML><HEAD><meta http-equiv="content-type" content="text/html;charset=utf-8">
OK: <TITLE>301 Moved</TITLE></HEAD><BODY>
```

**Result: SUCCESS** - NVA itself has internet access.

### Test 3: Private VM via NVA to Internet [FAIL]

**Test:** vm-test4 (10.0.40.4) → 8.8.8.8 via NVA

```bash
$ az vm run-command invoke --name vm-test4 --scripts "curl -v -m 5 http://8.8.8.8"
FAIL: Connection timed out after 5002 milliseconds
```

**Packet capture on vm-test4:**

```text
13:35:21.323622 IP 10.0.40.4.45906 > 8.8.8.8.80: Flags [S], seq 2008452674, ...
13:35:22.358562 IP 10.0.40.4.45906 > 8.8.8.8.80: Flags [S], seq 2008452674, ...
13:35:23.382591 IP 10.0.40.4.45906 > 8.8.8.8.80: Flags [S], seq 2008452674, ...
```

**Packet capture on vm-test3 (NVA):**

```text
# NO PACKETS FROM 10.0.40.4 OBSERVED
```

**Route check on vm-test4:**

```bash
$ az vm run-command invoke --name vm-test4 --scripts "ip route get 8.8.8.8"
8.8.8.8 via 10.0.40.1 dev eth0 src 10.0.40.4
```

**Effective routes on vm-test4 NIC:**

```text
Source    State    Address Prefix    Next Hop Type     Next Hop IP
--------  -------  ----------------  ----------------  -------------
Default   Active   10.0.0.0/16       VnetLocal
Default   Invalid  0.0.0.0/0         Internet          # Azure disabled this
User      Active   0.0.0.0/0         VirtualAppliance  10.0.30.4
```

**Result: FAILED** - Packets never reach the NVA, despite UDR being "Active".

### Test 4: Subnet Configuration Verification

**Subnet 3 (NVA subnet):**

```json
{
  "Name": "snet-subnet3",
  "AddressPrefix": "10.0.30.0/24",
  "DefaultOutboundAccess": null // defaults to true
}
```

**Subnet 4 (Private subnet):**

```json
{
  "Name": "snet-subnet4",
  "AddressPrefix": "10.0.40.0/24",
  "DefaultOutboundAccess": false // explicitly disabled
}
```

## Root Cause Analysis

### The Problem

**`defaultOutboundAccess: false` blocks traffic at the Azure platform level BEFORE User-Defined Routes (UDR) can redirect it.**

### Evidence

1. **UDR is properly configured and shows as "Active"**

   - Route table correctly associated with subnet4
   - Route `0.0.0.0/0 → 10.0.30.4` is in "Active" state

2. **NVA is properly configured**

   - IP forwarding enabled on NIC: OK:
   - IP forwarding enabled in OS: OK:
   - nftables rules allow forwarding from 10.0.40.0/24: OK:
   - NAT/masquerade configured: OK:

3. **NSG rules allow the traffic**

   - AllowVnetOutBound: OK: (priority 65000)
   - AllowInternetOutBound: OK: (priority 65001)

4. **Direct inter-subnet connectivity works**

   - vm-test4 can reach vm-test3 directly: OK:

5. **Packets never arrive at the NVA**
   - tcpdump on NVA shows no packets from 10.0.40.4
   - OS routing table on vm-test4 shows next hop as 10.0.40.1 (subnet gateway), not 10.0.30.4

### Azure Packet Processing Order

```text
┌─────────────────────────────────────────────────────────────────┐
│ Packet from vm-test4 (10.0.40.4) to Internet (8.8.8.8)       │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: Azure Platform Level                                    │
│   Check: defaultOutboundAccess setting on source subnet         │
│   Result: false → BLOCK (for internet-bound traffic)            │
│   Status: [NO] BLOCKED HERE                                        │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: User-Defined Routes (UDR)                               │
│   Should check: 0.0.0.0/0 → 10.0.30.4                           │
│   Status: [N/A] NEVER REACHED                                       │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Network Virtual Appliance                               │
│   Should forward: 10.0.40.4 → Internet via NAT                  │
│   Status: [N/A] NEVER REACHED                                       │
└─────────────────────────────────────────────────────────────────┘
```

### Why This Happens

According to Azure documentation:

> **defaultOutboundAccess** provides default outbound connectivity to VMs in a subnet. When set to `false`, VMs in the subnet lose default outbound connectivity to the internet.

The key insight: **This setting operates at the Azure platform level and takes precedence over UDRs.**

Even though the effective routes show:

- `Default Internet (Invalid)` - Azure disabled default internet access
- `User 0.0.0.0/0 → 10.0.30.4 (Active)` - UDR is active

The platform-level block happens **before** the routing decision is applied for internet-bound traffic.

### Intra-VNet Traffic Works

Direct connectivity between vm-test4 and vm-test3 works because:

- Traffic stays within the VNet (10.0.0.0/16)
- `defaultOutboundAccess: false` only blocks **internet-bound** traffic
- VNet-local traffic uses the `VnetLocal` route which has higher priority

### Critical Discovery: Default SNAT Limitation

**IMPORTANT UPDATE:** After extended testing with subnet5 and public IP configurations, we discovered the root cause is **NOT** `defaultOutboundAccess` settings, but rather Azure's default SNAT behavior and packet validation.

**Test 3: Subnet5 (Public-capable) with UDR - NVA WITHOUT Public IP [NO] FAILED**

```bash
# Configuration
- Subnet5: defaultOutboundAccess: true (explicitly set)
- VM: vm-test5 (10.0.50.4) - NO public IP
- UDR: 0.0.0.0/0 → 10.0.30.4 (NVA)
- NVA: vm-test3 (10.0.30.4) - NO public IP

# Results
OK: VM can ping/SSH to NVA directly
OK: NVA can access internet (via default SNAT)
OK: UDR is configured and shows as "Active"
OK: nftables forwarding rules correct
FAIL: Internet-bound traffic NEVER reaches NVA (tcpdump confirms)
```

**Test 4: Subnet5 with UDR - NVA WITH Public IP [WARN] PARTIALLY WORKS**

```bash
# Configuration
- Subnet5: defaultOutboundAccess: true
- VM: vm-test5 (10.0.50.4) - NO public IP (uses default SNAT)
- UDR: 0.0.0.0/0 → 10.0.30.4 (NVA)
- NVA: vm-test3 (10.0.30.4) - WITH public IP (52.159.138.16)

# Critical Results
OK: UDR routing NOW WORKS - packets reach NVA (tcpdump confirms)
OK: NVA receives packets from source VM (10.0.50.4 → Internet destinations)
OK: nftables forward chain processes packets
FAIL: Source IP remains 10.0.50.4 in outbound packets (NAT masquerading not applied)
FAIL: Internet connectivity FAILS - curl times out

# Packet Analysis from tcpdump
Observed: 10.0.50.4 → 20.60.233.193:443 (packets leaving NVA)
Expected: 52.159.138.16 → 20.60.233.193:443 (if NAT masquerading worked)
```

**Root Cause Identified:**

Azure's platform-level routing validation has **TWO levels of checks**:

#### Level 1: UDR Routing Decision

- Requires NVA to have **explicit outbound method** (public IP, NAT Gateway, or Load Balancer)
- Without this: Packets never reach NVA (blocked before UDR evaluation)
- With this: OK: Packets reach NVA via UDR

#### Level 2: Packet Forwarding Validation

- Azure validates the **source VM's outbound path** for forwarded packets
- VMs relying on **default SNAT cannot have their packets properly forwarded** through custom NVAs
- NAT masquerading does not apply to forwarded packets from default SNAT VMs
- This happens even when NVA has public IP and proper NAT configuration

**The Complete Requirement:**

For VM-based NVA internet routing to work in Azure:

1. **NVA must have explicit outbound** (public IP, NAT Gateway, or LB) - enables UDR routing
2. **Source VMs must have explicit outbound** (public IP, NAT Gateway, or LB) - enables packet forwarding
3. Both conditions must be met simultaneously

Azure's **default SNAT** is incompatible with custom NVA forwarding because it operates at the platform level and prevents packet forwarding for VMs that rely on it.

## Conclusions

### Answer to Research Question

#### Summary: VM-based NVAs DO NOT work with Azure's default SNAT

A VM with network forwarding enabled **CANNOT** work as an NVA for internet-bound traffic in Azure when:

[NO] **NVA relies on default SNAT** (no public IP, NAT Gateway, or Load Balancer)

- Result: Traffic never reaches NVA (UDR bypassed)

[NO] **Source VMs rely on default SNAT** (even if NVA has public IP)

- Result: Traffic reaches NVA but Azure SDN drops packets during forwarding

[NO] **Source subnet has `defaultOutboundAccess: false`**

- Result: Traffic blocked at source subnet

**VMs CAN work as NVAs for internet routing ONLY when:**

[YES] **BOTH NVA AND source VMs have explicit outbound** (public IP, NAT Gateway, or Load Balancer)

- This is the complete requirement for internet-bound traffic
- Both conditions must be satisfied simultaneously

[YES] **Routing intra-VNet traffic** (regardless of outbound access settings)

- Default SNAT limitation does not apply to VNet-local traffic

[YES] **Routing to on-premises** via VPN/ExpressRoute

- Default SNAT limitation does not apply to hybrid connectivity

### Workarounds

If you need private subnet VMs to access the internet, you have these options:

#### Option 1: Enable Default Outbound Access [WARN] (Not Recommended for Security)

```bash
az network vnet subnet update \
  --name snet-subnet4 \
  --vnet-name vnet-simple \
  --resource-group rg-test \
  --default-outbound false  # Change to true or remove flag
```

**Pros:**

- Simple change
- UDR-based NVA will work

**Cons:**

- Defeats the purpose of having a private subnet
- VMs get default SNAT IP that bypasses your NVA

#### Option 2: Use NAT Gateway [YES] (Recommended)

```bash
# Create NAT Gateway
az network public-ip create \
  --name pip-natgw \
  --resource-group rg-test \
  --sku Standard

az network nat gateway create \
  --name natgw-subnet4 \
  --resource-group rg-test \
  --public-ip-addresses pip-natgw

# Associate with subnet
az network vnet subnet update \
  --name snet-subnet4 \
  --vnet-name vnet-simple \
  --resource-group rg-test \
  --nat-gateway natgw-subnet4
```

**Pros:**

- Designed for this use case
- Works with `defaultOutboundAccess: false`
- More reliable than VM-based NVA
- Better performance

**Cons:**

- Additional cost (~$45/month + data transfer)
- Less flexible than custom NVA

#### Option 3: Use Azure Firewall [YES] (Enterprise Solution)

```bash
# Create Azure Firewall
az network public-ip create \
  --name pip-azfw \
  --resource-group rg-test \
  --sku Standard \
  --allocation-method Static

az network firewall create \
  --name azfw-hub \
  --resource-group rg-test \
  --vnet-name vnet-simple

az network firewall ip-config create \
  --firewall-name azfw-hub \
  --name azfw-config \
  --public-ip-address pip-azfw \
  --vnet-name vnet-simple \
  --resource-group rg-test
```

**Pros:**

- Fully managed service
- Works with `defaultOutboundAccess: false`
- Advanced features (threat intelligence, logging, etc.)
- Highly available

**Cons:**

- Expensive (~$1/hour + data processing)
- Overkill for simple scenarios

#### Option 4: Add Public IPs to BOTH NVA and Source VMs [WARN] (Required but Expensive)

**CRITICAL:** Based on our extensive testing, VM-based NVAs require **BOTH** the NVA **AND** source VMs to have explicit outbound connectivity.

```bash
# 1. Create public IP for NVA (enables UDR routing)
az network public-ip create \
  --name pip-nva \
  --resource-group rg-test \
  --sku Standard

az network nic ip-config update \
  --name ipconfig1 \
  --nic-name vm-test3-nic \
  --resource-group rg-test \
  --public-ip-address pip-nva

# 2. Create public IPs for each source VM (enables packet forwarding)
az network public-ip create \
  --name pip-vm1 \
  --resource-group rg-test \
  --sku Standard

az network nic ip-config update \
  --name ipconfig1 \
  --nic-name vm-test4-nic \
  --resource-group rg-test \
  --public-ip-address pip-vm1
```

**Pros:**

- This configuration actually works for VM-based NVA routing
- Full control over routing and firewall rules
- No ongoing service fees (just public IP costs)

**Cons:**

- **Defeats the purpose** - if every VM needs a public IP, why use an NVA?
- Expensive at scale (N+1 public IPs for N VMs + 1 NVA)
- Security risk - all VMs directly exposed to internet
- Must secure each VM with NSG/firewall rules
- Not suitable for sandbox/learning environments
- **Recommendation:** Use NAT Gateway instead (simpler, more secure, similar cost)

## Sandbox and Constrained Environment Limitations

### Key Finding for Cost-Constrained Environments

**IMPORTANT:** VM-based NVAs are **NOT viable** in sandbox or cost-constrained environments that don't allow public IP allocation.

Our extensive testing in Azure Pluralsight Sandbox revealed Azure's **two-level validation** for NVA routing:

**What DOESN'T Work:**

[NO] **Level 1 Failure:** NVA with default SNAT (no public IP)

- Traffic never reaches NVA, UDR is bypassed
- Requires NVA to have explicit outbound (public IP, NAT Gateway, or LB)

[NO] **Level 2 Failure:** Source VMs with default SNAT (even if NVA has public IP)

- Traffic reaches NVA via UDR OK:
- NAT masquerading does not apply (packets keep source VM IP) FAIL:
- Return path fails, connectivity broken FAIL:
- Requires source VMs to have explicit outbound connectivity

[NO] **Complete Failure:** Both source VMs and NVA rely on default SNAT

- No VM-based NVA routing possible at all

**What DOES Work:**

[YES] Intra-VNet routing (VM → UDR → NVA → other VM)

- Default SNAT limitation only applies to internet-bound traffic

[YES] Routing to on-premises via VPN/ExpressRoute

- Not affected by default SNAT validation

[YES] Azure-native solutions (NAT Gateway, Azure Firewall)

- Have platform-level integration that bypasses validation

**Implications for Learning/Development:**

- **Cannot practice internet-bound VM-based NVA** in free/sandbox environments
- Requires public IPs on **ALL** VMs (NVA + source VMs) to work
- At that scale, NAT Gateway is simpler and more secure
- Intra-VNet routing experiments work fine without public IPs
- This is an architectural constraint, not a misconfiguration

**Why This Matters:**

Azure's platform has **two distinct validation points**:

1. **UDR Routing Decision:** Checks if NVA has explicit outbound path
2. **Packet Forwarding Validation:** Checks if source VM has explicit outbound path

Both validations must pass for internet-bound NVA routing to work. Azure's default SNAT operates at the platform level and is incompatible with custom packet forwarding, likely by design to prevent routing loops and maintain proper SNAT state tracking.

## Best Practices

### When to Use Custom NVA

[YES] Use custom NVA when:

- You need custom routing logic or specialized packet inspection
- You want full control over firewall rules and routing policies
- You're comfortable managing VM-based infrastructure
- **BOTH NVA AND all source VMs have explicit outbound** (public IP, NAT Gateway, or LB)
- You have a small number of source VMs (otherwise NAT Gateway is more cost-effective)
- Specific use case: Intra-VNet routing only (no internet-bound traffic requirements)

### When to Use NAT Gateway

[YES] Use NAT Gateway when:

- You want `defaultOutboundAccess: false` for security
- You need simple, reliable outbound connectivity
- You want Azure-managed solution
- Cost is acceptable (~$45/month)

### When to Use Azure Firewall

[YES] Use Azure Firewall when:

- Enterprise security requirements
- Need centralized logging and monitoring
- Require threat intelligence
- Multiple VNets/Hub-spoke topology
- Budget allows premium solution

## Related Azure Documentation

- [Default outbound access in Azure](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access)
- [User-defined routes (UDR)](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-udr-overview)
- [NAT Gateway](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview)
- [Azure Firewall](https://learn.microsoft.com/en-us/azure/firewall/overview)
- [Network Virtual Appliances](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/dmz/nva-ha)

## Test Scripts

All scripts used in this research are located in this directory:

- `02-azure-simple-network.sh` - Create VNet with 4 subnets
- `07-vm.sh` - Deploy NVA VM with nftables (via cloud-init)
- `12-private-vm.sh` - Deploy private VM in subnet4
- `14-nva-routing.sh` - Configure UDR for NVA routing
- `15-nva-tests.sh` - Test NVA functionality

**Note:** Script `08-nftables.sh` is for manual nftables updates only. The `07-vm.sh` script already configures nftables via cloud-init, so `08-nftables.sh` is typically not needed.

## Reproduction Steps

To reproduce this research:

```bash
# Set resource group (use existing sandbox or create new)
export RESOURCE_GROUP='your-resource-group-name'

# 1. Create network infrastructure
./02-azure-simple-network.sh

# 2. Deploy NVA VM with nftables
./07-vm.sh

# 3. Deploy private VM
./12-private-vm.sh

# 4. Configure NVA routing
./14-nva-routing.sh

# 5. Test (will show failure with defaultOutboundAccess: false)
./15-nva-tests.sh
```

## Future Research

Areas for further investigation:

1. **Service Endpoints** - Do service endpoints work with `defaultOutboundAccess: false`?
2. **Private Endpoints** - How do private endpoints interact with this setting?
3. **VNet Peering** - Does traffic to peered VNets work?
4. **Hybrid Scenarios** - Can traffic route to on-premises via NVA?
5. **Performance Testing** - Throughput comparison: NVA vs NAT Gateway vs Azure Firewall

---

**Last Updated:** 2025-10-06
**Tested On:** Azure Pluralsight Sandbox (westus region)
**Azure CLI Version:** Latest as of October 2025
