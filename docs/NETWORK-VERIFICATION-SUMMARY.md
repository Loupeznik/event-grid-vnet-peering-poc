# Network Verification Tools - Quick Summary

## Tools Created for You

### 1. 📊 Network Diagram Generator
**Script:** `./scripts/generate-network-diagram.sh`

**What it creates:**
- Visual network topology diagram (PNG/SVG)
- Shows all VNETs across both subscriptions
- Displays private endpoints with IPs
- Illustrates VNET peering connections
- Color-codes private vs public traffic flows

**Output Files:**
- `docs/diagrams/network-topology.png` - Image file
- `docs/diagrams/network-topology.svg` - Scalable vector
- `docs/diagrams/network-topology.dot` - Source file

**Already generated!** Check `docs/diagrams/network-topology.png`

### 2. 🔍 Network Connectivity Verifier
**Script:** `./scripts/verify-network-connectivity.sh`

**What it checks:**
- ✅ VNET integration status
- ✅ Private DNS resolution (Event Grid → 10.1.1.4, Event Hub → 10.1.1.5)
- ✅ VNET peering state (including cross-subscription)
- ✅ Private endpoint configuration
- ✅ Function outbound IP addresses
- ✅ DNS zone VNET links

**Example Output:**
```
✅ Python function has VNET integration
   Subnet: /subscriptions/.../virtualNetworkConnections/snet-function

✅ Private DNS Zone: privatelink.eventgrid.azure.net

Private DNS A Records:
Name                             IP        TTL
-------------------------------  --------  -----
evgt-poc-3tlv1w.swedencentral-1  10.1.1.4  10

VNET Links for Private DNS:
Name                 VirtualNetwork
-------------------  ----------------------------------------------------------------
vnet-dotnet-link     /subscriptions/.../vnet-dotnet-3tlv1w
vnet-eventgrid-link  /subscriptions/.../vnet-eventgrid-3tlv1w
vnet-function-link   /subscriptions/.../vnet-function-3tlv1w
```

### 3. 📚 Comprehensive Guide
**Document:** `docs/NETWORK-VERIFICATION-GUIDE.md`

**Contains:**
- Azure Portal methods (Network Watcher, Resource Graph)
- Complete Azure CLI command reference
- Application Insights queries
- Log Analytics queries
- Third-party tool recommendations
- Verification checklists

---

## Quick Verification Steps

### Step 1: View the Network Diagram
```bash
# Diagram already generated
open docs/diagrams/network-topology.png
```

**What you'll see:**
- Subscription 1 (blue): Python function, Event Grid, Event Hub
- Subscription 2 (green): .NET function
- Gold boxes: Private endpoints with IPs
- Green arrows: Private traffic flows
- Red dashed arrows: Public webhook traffic

### Step 2: Verify in Azure Portal

**Option A: Network Watcher Topology**
1. Open Azure Portal
2. Navigate to **Network Watcher**
3. Select **Topology** under Monitoring
4. Choose:
   - Subscription: Subscription 1
   - Resource Group: `rg-eventgrid-vnet-poc-network`
   - Virtual Network: `vnet-eventgrid-*`

5. Repeat for:
   - `vnet-function-*` (Subscription 1)
   - `vnet-dotnet-*` (Subscription 2)

**What to look for:**
- ✅ VNETs connected via peering (blue lines)
- ✅ Private endpoints in subnet
- ✅ Functions integrated into subnets

**Option B: Resource Graph Explorer**
1. Open Azure Portal
2. Search for "Resource Graph Explorer"
3. Select both subscriptions
4. Run query:

```kusto
Resources
| where type == "microsoft.network/privateendpoints"
| where resourceGroup contains "eventgrid-vnet-poc"
| project name, resourceGroup,
    customDnsConfigs = properties.customDnsConfigs
| mv-expand customDnsConfigs
| project name, resourceGroup,
    fqdn = customDnsConfigs.fqdn,
    ipAddress = customDnsConfigs.ipAddresses[0]
```

**Expected output:**
```
name              resourceGroup                    fqdn                                              ipAddress
pe-eventgrid-*    rg-eventgrid-vnet-poc-eventgrid  evgt-poc-*.swedencentral-1.eventgrid.azure.net   10.1.1.4
pe-eventhub-*     rg-eventgrid-vnet-poc-eventhub   evhns-eventgrid-*.servicebus.windows.net         10.1.1.5
```

### Step 3: Verify Private Communication

**Check 1: Private DNS Resolution**
```bash
# From your terminal
cd terraform

# Event Grid DNS
az network private-dns record-set a list \
  --resource-group $(terraform output -raw resource_group_network) \
  --zone-name privatelink.eventgrid.azure.net \
  --output table
```

**Expected:** Event Grid hostname resolves to `10.1.1.4`

**Check 2: VNET Peering Status**
```bash
# Check peering state
az network vnet peering list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-eventgrid-* \
  --output table
```

**Expected:** `peeringState: Connected`, `allowForwardedTraffic: True`

**Check 3: Function VNET Integration**
```bash
# Python function
az functionapp vnet-integration list \
  --name func-eventgrid-* \
  --resource-group rg-eventgrid-vnet-poc-function \
  --output table

# .NET function (Subscription 2)
az account set --subscription <sub2-id>
az functionapp vnet-integration list \
  --name func-dotnet-* \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --output table
```

**Expected:** Shows subnet integration and `vnetRouteAllEnabled: true`

### Step 4: Verify Traffic Flows

**Application Insights - Python function:**
```bash
# Get App Insights App ID
PYTHON_APP_ID=$(az monitor app-insights component show \
  --app appi-function-3tlv1w \
  --resource-group rg-eventgrid-vnet-poc-function \
  --query appId -o tsv)

# Query for IP logs
cat > /tmp/query.json << 'EOF'
{
  "query": "traces | where timestamp > ago(1h) | where message contains 'Source IP' | project timestamp, message | order by timestamp desc | take 10"
}
EOF

az rest \
  --method POST \
  --uri "https://api.applicationinsights.io/v1/apps/$PYTHON_APP_ID/query" \
  --headers "Content-Type=application/json" \
  --body @/tmp/query.json
```

**Application Insights - .NET function:**
```bash
# Event Hub consumption logs
az account set --subscription <sub2-id>

DOTNET_APP_ID=$(az monitor app-insights component show \
  --app appi-dotnet-function-3tlv1w \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --query appId -o tsv)

cat > /tmp/query-eh.json << 'EOF'
{
  "query": "traces | where timestamp > ago(1h) | where operation_Name == 'ConsumeEventFromEventHub' | summarize count() by bin(timestamp, 5m)"
}
EOF

az rest \
  --method POST \
  --uri "https://api.applicationinsights.io/v1/apps/$DOTNET_APP_ID/query" \
  --headers "Content-Type=application/json" \
  --body @/tmp/query-eh.json
```

---

## Proof of Private Communication

### Evidence Checklist

**✅ Private Endpoint Configuration:**
- Event Grid private endpoint: `10.1.1.4` (verified)
- Event Hub private endpoint: `10.1.1.5` (verified)
- Private DNS zones linked to all VNETs (verified)

**✅ Network Path Configuration:**
- VNET integration on both functions (verified)
- `vnetRouteAllEnabled = true` (verified)
- VNET peering: Connected state (verified)
- Cross-subscription peering: Working (verified)

**✅ Access Control:**
- Event Grid public access: Disabled
- Event Hub public access: Disabled
- Only private endpoint can access

**✅ Functional Verification:**
- Python publishes to Event Grid ✅
- Event Grid delivers to Event Hub ✅
- .NET consumes from Event Hub ✅
- All events delivered successfully

### Traffic Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ Subscription 1                                                  │
│                                                                 │
│  ┌──────────┐     VNET Peering     ┌───────────────┐          │
│  │ Python   │◄────────────────────►│ Event Grid PE │          │
│  │ Function │  10.0.x.x → 10.1.1.4 │  (10.1.1.4)   │          │
│  └──────────┘                       └───────────────┘          │
│      │                                      │                   │
│      │                                      ▼                   │
│      │                               ┌───────────────┐         │
│      └──────────(webhook)───────────►│  Event Hub PE │         │
│           Public Internet            │  (10.1.1.5)   │         │
│                                      └───────────────┘         │
│                                             │                   │
└─────────────────────────────────────────────┼───────────────────┘
                                              │
                                Cross-subscription
                                  VNET Peering
                                              │
                                              ▼
┌─────────────────────────────────────────────┼───────────────────┐
│ Subscription 2                              │                   │
│                                             │                   │
│                                      ┌──────▼──────┐           │
│                                      │   .NET      │           │
│                                      │  Function   │           │
│                                      │ (Poll/Pull) │           │
│                                      └─────────────┘           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Legend:
────► Private communication (via VNET peering)
····► Public communication (webhook only)
```

### Why This Proves Private Communication

1. **Event Grid Publishing (Python/NET → Event Grid)**
   - Function resolves Event Grid FQDN to `10.1.1.4` (private IP)
   - DNS lookup uses private DNS zone
   - Traffic routes through VNET peering (10.0.x.x → 10.1.x.x)
   - Event Grid public access disabled = must use private endpoint
   - **Result:** PRIVATE ✅

2. **Event Hub Delivery (Event Grid → Event Hub)**
   - Event Grid system identity has access
   - Delivers to Event Hub via private endpoint (10.1.1.5)
   - Event Hub public access disabled
   - **Result:** PRIVATE ✅

3. **Event Hub Consumption (.NET → Event Hub)**
   - .NET function resolves Event Hub FQDN to `10.1.1.5`
   - DNS via private DNS zone linked to VNET 3
   - Traffic routes via cross-subscription peering (10.2.x.x → 10.1.1.5)
   - Successfully consuming events (logs prove it)
   - **Result:** PRIVATE ✅

4. **Event Grid Webhook (Event Grid → Functions)**
   - This path is PUBLIC (by design)
   - Protected by IP restrictions (AzureEventGrid service tag)
   - Optional Entra ID authentication
   - **Result:** PUBLIC (secured) ⚠️

---

## Common Questions

### Q: How do I know the Event Hub connection is really private?

**Answer:** Multiple proofs:
1. Event Hub has `publicNetworkAccess` disabled
2. Private endpoint exists at 10.1.1.5
3. Private DNS resolves to 10.1.1.5 (not public IP)
4. Function has VNET integration with `vnetRouteAllEnabled=true`
5. VNET peering connected
6. Events are being consumed successfully

If any of these were misconfigured, the connection would fail. Since it works and public access is disabled, it MUST be using the private path.

### Q: Why does the network diagram show webhook as public?

**Answer:** Event Grid webhooks are delivered via Azure's Event Grid service infrastructure, which uses public IP addresses from the `AzureEventGrid` service tag. This is by design - Event Grid cannot initiate connections through private endpoints.

The Event Hub path was added to provide a fully private alternative for consumption.

### Q: Can I test actual network packets?

**Answer:** Not easily with Functions. Options:
1. Use test script - functional proof (works = correct path)
2. Check Application Insights logs for IPs
3. Enable NSG flow logs (limited value for private endpoint subnets)
4. Trust Azure's private endpoint mechanism (if configured correctly, it works)

### Q: How do I visualize cross-subscription resources?

**Answer:** Use the tools provided:
1. **Network diagram script:** Shows both subscriptions in one view
2. **Resource Graph Explorer:** Query across subscriptions
3. **Network Watcher:** View per subscription (repeat for each)

---

## Next Steps

1. ✅ **View the diagram:** `open docs/diagrams/network-topology.png`
2. ✅ **Run verification:** `./scripts/verify-network-connectivity.sh`
3. ✅ **Check portal:** Network Watcher → Topology
4. ✅ **Test connectivity:** `./scripts/test-connectivity.sh`
5. ✅ **Review logs:** Application Insights (see guide)

---

## Additional Resources

- **Full Guide:** `docs/NETWORK-VERIFICATION-GUIDE.md`
- **Deployment Report:** `docs/EVENT-HUB-DEPLOYMENT-REPORT.md`
- **IP Logging Guide:** `docs/IP-LOGGING-AND-MONITORING.md`
- **Network Architecture:** `docs/NETWORK-ARCHITECTURE-CLARIFICATION.md`

---

**Last Updated:** January 27, 2026
**Status:** ✅ All verification tools ready to use
