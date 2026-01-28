# Azure Network Verification Guide

**Purpose:** Verify private communication paths and visualize network topology across two Azure subscriptions

---

## Quick Start

### 1. Verify Network Connectivity
```bash
./scripts/verify-network-connectivity.sh
```

This script checks:
- ✅ Effective routes and VNET integration
- ✅ Private DNS resolution
- ✅ VNET peering status (including cross-subscription)
- ✅ Private endpoint configuration
- ✅ Network security groups
- ✅ Function app outbound IPs

### 2. Generate Network Topology Diagram
```bash
./scripts/generate-network-diagram.sh
```

This creates a visual diagram showing:
- VNETs and subnets across both subscriptions
- Private endpoints and their IPs
- VNET peering connections
- Traffic flows (private vs public paths)
- DNS resolution paths

**Output:** `docs/diagrams/network-topology.png`

---

## Azure Portal Methods

### Method 1: Network Watcher Topology

**Steps:**
1. Navigate to **Network Watcher** in Azure Portal
2. Select **Topology** under Monitoring
3. Choose:
   - **Subscription:** Select subscription (repeat for both)
   - **Resource Group:** Select `rg-eventgrid-vnet-poc-network`
   - **Virtual Network:** Select VNET

**What it shows:**
- Visual representation of VNETs, subnets, and peerings
- Connected resources (functions, private endpoints)
- NSGs and their associations
- Route tables

**Limitations:**
- Can only view one subscription at a time
- Doesn't show traffic flows
- No cross-subscription view

### Method 2: Network Watcher - Connection Monitor

**Purpose:** Monitor actual connectivity between resources over time

**Setup:**
```bash
# Enable Network Watcher (if not already enabled)
az network watcher configure \
  --resource-group rg-eventgrid-vnet-poc-network \
  --locations swedencentral \
  --enabled true
```

**Note:** Connection Monitor requires VMs or VM scale sets with Network Watcher agent. Azure Functions don't support this directly.

**Alternative:** Use the verification tests in the test script to confirm actual connectivity.

### Method 3: Resource Graph Explorer

**Purpose:** Query infrastructure across multiple subscriptions

**Portal Steps:**
1. Open **Resource Graph Explorer** in Azure Portal
2. Select both subscriptions
3. Run query (see queries below)

**Query 1: List all VNETs and their peerings**
```kusto
Resources
| where type == "microsoft.network/virtualnetworks"
| where resourceGroup contains "eventgrid-vnet-poc"
| project name, location, resourceGroup,
    addressSpace = properties.addressSpace.addressPrefixes,
    peerings = properties.virtualNetworkPeerings
| extend peeringCount = array_length(peerings)
```

**Query 2: List private endpoints and their IPs**
```kusto
Resources
| where type == "microsoft.network/privateendpoints"
| where resourceGroup contains "eventgrid-vnet-poc"
| project name, resourceGroup,
    subnet = properties.subnet.id,
    privateLinkServiceConnections = properties.privateLinkServiceConnections,
    customDnsConfigs = properties.customDnsConfigs
| mv-expand customDnsConfigs
| project name, resourceGroup,
    fqdn = customDnsConfigs.fqdn,
    ipAddress = customDnsConfigs.ipAddresses[0]
```

**Query 3: Function apps with VNET integration**
```kusto
Resources
| where type == "microsoft.web/sites"
| where resourceGroup contains "eventgrid-vnet-poc"
| where properties.virtualNetworkSubnetId != ""
| project name, resourceGroup,
    kind,
    vnetSubnetId = properties.virtualNetworkSubnetId,
    vnetRouteAllEnabled = properties.vnetRouteAllEnabled,
    outboundIpAddresses = properties.outboundIpAddresses
```

---

## Azure CLI Verification Commands

### Verify Private DNS Resolution

**Check Event Grid private DNS:**
```bash
# List private DNS zones
az network private-dns zone list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --query "[].{Name:name, NumRecordSets:numberOfRecordSets}" \
  --output table

# List A records for Event Grid
az network private-dns record-set a list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --zone-name privatelink.eventgrid.azure.net \
  --output table

# Check VNET links
az network private-dns link vnet list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --zone-name privatelink.eventgrid.azure.net \
  --output table
```

**Check Event Hub private DNS:**
```bash
# List A records for Event Hub
az network private-dns record-set a list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --zone-name privatelink.servicebus.windows.net \
  --output table
```

### Verify VNET Peering

**Subscription 1 peerings:**
```bash
# Function VNET peering
az network vnet peering list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-function-* \
  --output table

# Event Grid VNET peering
az network vnet peering list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-eventgrid-* \
  --output table
```

**Subscription 2 peerings:**
```bash
# Switch to subscription 2
az account set --subscription <subscription-2-id>

# .NET Function VNET peering
az network vnet peering list \
  --resource-group rg-eventgrid-vnet-poc-dotnet-network \
  --vnet-name vnet-dotnet-* \
  --output table

# Switch back
az account set --subscription <subscription-1-id>
```

**Expected output:**
- `peeringState`: Should be `Connected`
- `allowForwardedTraffic`: Should be `True`
- `remoteVirtualNetwork`: Shows the peer VNET ID

### Check Private Endpoint Details

**Event Grid private endpoint:**
```bash
az network private-endpoint show \
  --name pe-eventgrid-* \
  --resource-group rg-eventgrid-vnet-poc-eventgrid \
  --query "{Name:name, State:provisioningState, IP:customDnsConfigs[0].ipAddresses[0], FQDN:customDnsConfigs[0].fqdn}" \
  --output table
```

**Event Hub private endpoint:**
```bash
az network private-endpoint show \
  --name pe-eventhub-* \
  --resource-group rg-eventgrid-vnet-poc-eventhub \
  --query "{Name:name, State:provisioningState, IP:customDnsConfigs[0].ipAddresses[0], FQDN:customDnsConfigs[0].fqdn}" \
  --output table
```

### Verify Function VNET Integration

**Python function:**
```bash
az functionapp vnet-integration list \
  --name func-eventgrid-* \
  --resource-group rg-eventgrid-vnet-poc-function \
  --output table

az functionapp config show \
  --name func-eventgrid-* \
  --resource-group rg-eventgrid-vnet-poc-function \
  --query "{VnetRouteAll:vnetRouteAllEnabled, VnetName:vnetName}" \
  --output table
```

**.NET function (Subscription 2):**
```bash
az account set --subscription <subscription-2-id>

az functionapp vnet-integration list \
  --name func-dotnet-* \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --output table
```

### Test DNS Resolution from Function Context

You can't directly run `nslookup` from a function, but you can verify DNS configuration:

**Check Event Grid endpoint resolution:**
```bash
# Get Event Grid endpoint
EVENTGRID_ENDPOINT=$(az eventgrid topic show \
  --name evgt-poc-* \
  --resource-group rg-eventgrid-vnet-poc-eventgrid \
  --query endpoint -o tsv)

# Extract hostname
EVENTGRID_HOST=$(echo $EVENTGRID_ENDPOINT | sed 's|https://||' | sed 's|/.*||')

echo "Event Grid hostname: $EVENTGRID_HOST"
echo "Should resolve to private IP via privatelink.eventgrid.azure.net"

# Check private DNS has record
az network private-dns record-set a list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --zone-name privatelink.eventgrid.azure.net \
  --query "[?name=='$EVENTGRID_HOST'].{Name:name, IP:aRecords[0].ipv4Address}"
```

---

## Network Security Group Flow Logs

To capture actual traffic flows, enable NSG Flow Logs:

### Enable Flow Logs

**Prerequisites:**
- Storage account for logs
- Network Watcher enabled

**Enable for subnet NSG:**
```bash
# Create storage account for flow logs (if needed)
az storage account create \
  --name stflowlogs$RANDOM \
  --resource-group rg-eventgrid-vnet-poc-network \
  --location swedencentral \
  --sku Standard_LRS

# Get storage account ID
STORAGE_ID=$(az storage account show \
  --name stflowlogs* \
  --resource-group rg-eventgrid-vnet-poc-network \
  --query id -o tsv)

# Enable flow logs for NSG (if you have NSGs)
az network watcher flow-log create \
  --name flowlog-eventgrid \
  --nsg <nsg-name> \
  --resource-group rg-eventgrid-vnet-poc-network \
  --storage-account $STORAGE_ID \
  --enabled true \
  --retention 7
```

**Note:** This infrastructure doesn't use NSGs on the private endpoint subnet, so flow logs won't capture much. The verification comes from:
1. Successful event delivery
2. Private endpoint provisioning state
3. DNS resolution to private IPs
4. VNET peering status

---

## Effective Routes

To see the actual routing table used by a function:

**Note:** Functions don't expose effective routes directly. Instead, verify:

**1. Check VNET integration is using correct subnet:**
```bash
az functionapp vnet-integration list \
  --name func-eventgrid-* \
  --resource-group rg-eventgrid-vnet-poc-function \
  --query "[].{VnetName:vnetName, SubnetName:name, RouteAll:routeAllEnabled}"
```

**2. Check subnet route table:**
```bash
# Get subnet details
az network vnet subnet show \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-function-* \
  --name snet-function \
  --query "{RouteTable:routeTable, ServiceEndpoints:serviceEndpoints}"
```

**3. Verify vnetRouteAllEnabled:**
```bash
az functionapp config show \
  --name func-eventgrid-* \
  --resource-group rg-eventgrid-vnet-poc-function \
  --query vnetRouteAllEnabled
```

Should return `true` - this routes ALL outbound traffic through the VNET, ensuring it uses VNET peering to reach private endpoints.

---

## Traffic Flow Verification

### Private Path Verification Checklist

**✅ Event Grid Publish (Python/NET → Event Grid):**
- [ ] Private endpoint exists for Event Grid (10.1.1.4)
- [ ] Private DNS resolves to 10.1.1.4
- [ ] Function has VNET integration
- [ ] vnetRouteAllEnabled = true
- [ ] VNET peering connected
- [ ] Event successfully published (test script)

**✅ Event Hub Delivery (Event Grid → Event Hub):**
- [ ] Private endpoint exists for Event Hub (10.1.1.5)
- [ ] Event Grid system identity has Event Hub Data Sender role
- [ ] Event Hub public access disabled
- [ ] Events delivered successfully (test script)

**✅ Event Hub Consumption (.NET → Event Hub):**
- [ ] Private endpoint exists for Event Hub (10.1.1.5)
- [ ] Private DNS zone linked to VNET 3
- [ ] .NET function has VNET integration
- [ ] VNET peering from VNET 3 to VNET 2
- [ ] Function has Event Hub Data Receiver role
- [ ] Events consumed successfully (test script)

**⚠️ Webhook Delivery (Event Grid → Functions):**
- [ ] This path is PUBLIC (by design)
- [ ] Protected by IP restrictions (AzureEventGrid service tag)
- [ ] Optional: Protected by Entra ID authentication

---

## Monitoring Actual Traffic

### Application Insights Queries

**Python function - verify private endpoint used:**
```kusto
traces
| where timestamp > ago(1h)
| where message contains "Publishing event to Event Grid"
| project timestamp, message
```

**.NET function - verify Event Hub private connection:**
```kusto
traces
| where timestamp > ago(1h)
| where operation_Name == "ConsumeEventFromEventHub"
| summarize EventCount = count() by bin(timestamp, 5m)
| render timechart
```

### Log Analytics Queries

**Event Hub VNET connection events:**
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.EVENTHUB"
| where Category == "EventHubVNetConnectionEvent"
| project TimeGenerated, OperationName, CallerIpAddress, properties_s
| order by TimeGenerated desc
```

**Event Grid delivery status:**
```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.EVENTGRID"
| where Category == "DeliveryFailures" or Category == "PublishFailures"
| project TimeGenerated, Category, OperationName, properties_s
| order by TimeGenerated desc
```

---

## Third-Party Visualization Tools

### 1. Terraform Visual

**Install:**
```bash
# Using Homebrew (macOS)
brew install terraform-visual

# Or using pip
pip install terraform-visual
```

**Generate diagram:**
```bash
cd terraform
terraform graph | terraform-visual \
  --format png \
  --output ../docs/diagrams/terraform-graph.png
```

### 2. Blast Radius

**Install:**
```bash
pip install blastradius
```

**Generate interactive diagram:**
```bash
cd terraform
blast-radius --serve .
# Open http://localhost:5000
```

### 3. draw.io / diagrams.net

Use the DOT file generated by `generate-network-diagram.sh`:
1. Open https://www.diagrams.net/
2. Import `docs/diagrams/network-topology.dot`
3. Arrange and customize
4. Export as PNG/SVG

### 4. Azure Network Topology on GitHub

Export infrastructure to JSON and use visualization tools:

```bash
# Export all network resources
az graph query \
  -q "Resources | where type contains 'network' | where resourceGroup contains 'eventgrid-vnet-poc'" \
  --subscriptions <sub1-id> <sub2-id> \
  > docs/diagrams/network-resources.json
```

---

## Summary

### Best Methods for Private Communication Verification:

1. **Network Watcher Topology** (Portal)
   - Visual representation per subscription
   - Good for understanding VNET structure

2. **Custom Scripts** (This repo)
   - `verify-network-connectivity.sh` - comprehensive CLI checks
   - `generate-network-diagram.sh` - visual diagram
   - Best for cross-subscription view

3. **Resource Graph Explorer** (Portal)
   - Query across subscriptions
   - Great for detailed configuration review

4. **Test Script** (Functional verification)
   - `./scripts/test-connectivity.sh`
   - **Most important** - proves actual connectivity works

5. **Application Insights** (Runtime verification)
   - Logs prove traffic flows
   - IP logging shows source
   - Confirms private vs public paths

### Evidence of Private Communication:

1. ✅ Private endpoints provisioned with private IPs
2. ✅ Private DNS zones resolve to private IPs
3. ✅ VNET peering connected between all VNETs
4. ✅ Functions have VNET integration with vnetRouteAllEnabled
5. ✅ Public access disabled on Event Grid and Event Hub
6. ✅ Events successfully delivered (test script proves it)
7. ✅ No public IP addresses in logs (except webhook delivery)

**Conclusion:** If events are delivered successfully and public access is disabled, the communication MUST be using the private path.

---

## Quick Reference Commands

```bash
# Verify everything
./scripts/verify-network-connectivity.sh

# Generate diagram
./scripts/generate-network-diagram.sh

# Test actual connectivity
./scripts/test-connectivity.sh

# View in portal
# 1. Network Watcher → Topology
# 2. Resource Graph Explorer → Run queries above
# 3. Application Insights → Logs → Run queries above
```

---

**Last Updated:** January 27, 2026
