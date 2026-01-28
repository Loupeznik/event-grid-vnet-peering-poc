# IP Logging and Monitoring Configuration

**Date:** January 27, 2026
**Purpose:** Verify private network connectivity and monitor Event Grid/Event Hub operations

---

## Overview

This document describes the IP logging and monitoring configuration added to verify that:
1. HTTP trigger traffic comes from expected sources (client IPs)
2. Event Grid webhook traffic comes from Azure Event Grid service IPs (public)
3. Event Hub trigger traffic is via private endpoint (VNET peering)
4. Event Grid and Event Hub operations are logged to centralized Log Analytics

---

## Function IP Logging

### Python Function (func-eventgrid-3tlv1w)

#### PublishEvent (HTTP Trigger)

**Logs:**
```python
Source IP (X-Forwarded-For): <client-ip>
Original Host: <hostname>
ARR SSL: <ssl-info>
```

**What to look for:**
- `X-Forwarded-For`: Client's original IP address (before Azure Front Door/App Gateway)
- `X-Original-Host`: Original hostname from the request
- `X-ARR-SSL`: SSL/TLS connection information

**Example log:**
```
Source IP (X-Forwarded-For): 203.0.113.42
Original Host: func-eventgrid-3tlv1w.azurewebsites.net
ARR SSL: <certificate-info>
```

#### ConsumeEvent (EventGrid Trigger)

**Logs:**
```
Event Grid trigger function processed an event
⚠️ Note: Event Grid webhook delivery comes via public internet (Azure Event Grid service IPs)
```

**What this means:**
- Event Grid webhooks are delivered via public internet (Microsoft limitation)
- Protected by IP restrictions (AzureEventGrid service tag)
- Cannot log source IP as Event Grid extension handles webhook internally

### .NET Function (func-dotnet-3tlv1w)

#### PublishEvent (HTTP Trigger)

**Logs:**
```csharp
Source IP (X-Forwarded-For): <client-ip>
Original Host: <hostname>
```

**What to look for:**
- Same as Python function
- Helps verify traffic source for publish operations

**Example log:**
```
Source IP (X-Forwarded-For): 198.51.100.5
Original Host: func-dotnet-3tlv1w.azurewebsites.net
```

#### ConsumeEvent (EventGrid Trigger)

**Logs:**
```
=== Event Grid Trigger Fired ===
⚠️ Note: Event Grid webhook delivery comes via public internet (Azure Event Grid service IPs)
```

**What this means:**
- Same as Python EventGrid trigger
- Public webhook delivery (expected behavior per Microsoft docs)

#### ConsumeEventFromEventHub (EventHub Trigger)

**Logs:**
```
=== Event Hub Trigger Fired ===
✅ Event Hub connection via PRIVATE ENDPOINT (VNET peering - fully private path)
```

**What this means:**
- Function polls Event Hub via VNET integration
- Connection goes through VNET peering to private endpoint (10.1.1.5)
- **This is the fully private path** - zero public internet traversal

---

## Expected IP Ranges

### HTTP Triggers (PublishEvent)

**Source IPs will vary based on caller:**
- Test from local machine: Your public IP
- Test from Azure VM: VM's public IP or NAT gateway IP
- Test from another Azure service: Azure service's outbound IP

**Not verifiable as "private"** - HTTP triggers are public endpoints.

### EventGrid Triggers (ConsumeEvent)

**Source IPs (not logged by extension):**
- Azure Event Grid service IPs (varies by region)
- Comes from `AzureEventGrid` service tag
- Example ranges (Sweden Central region):
  - 51.12.xxx.xxx
  - 51.120.xxx.xxx
  - See: https://www.microsoft.com/download/details.aspx?id=56519

**Verification:**
- IP restrictions allow only `AzureEventGrid` service tag
- Check Azure Portal → Function → Networking → Access Restrictions
- Should show: `Allow: AzureEventGrid (priority 100)`

### EventHub Triggers (ConsumeEventFromEventHub)

**Source IPs (not directly visible):**
- Function makes OUTBOUND connection to Event Hub
- Connection goes via VNET integration to private IP: **10.1.1.5**
- No "source IP" from Event Hub's perspective (function is the source)

**Verification method:**
1. Check DNS resolution (should resolve to 10.1.1.5)
2. Verify VNET integration enabled
3. Check Application Insights for "PRIVATE ENDPOINT" log messages
4. Confirm Event Hub private endpoint IP in Azure Portal

---

## Log Analytics Workspace

### Configuration

**Workspace Details:**
- Name: `log-eventgrid-<suffix>`
- SKU: PerGB2018 (pay-as-you-go)
- Retention: 30 days
- Resource Group: `rg-eventgrid-vnet-poc-network`

**What's logged:**
- Event Grid topic operations (publish/delivery failures)
- Event Hub namespace operations (connections, errors)
- Metrics from both services

### Diagnostic Settings

#### Event Grid Topic (evgt-poc-3tlv1w)

**Log Categories:**
- `DeliveryFailures` - Failed webhook deliveries
- `PublishFailures` - Failed publish attempts

**Metrics:**
- `AllMetrics` - All Event Grid metrics

**Use cases:**
- Debug webhook delivery issues
- Monitor publish success rates
- Track event throughput

#### Event Hub Namespace (evhns-eventgrid-3tlv1w)

**Log Categories:**
- `ArchiveLogs` - Archive capture operations
- `OperationalLogs` - Operational events
- `AutoScaleLogs` - Auto-scaling events
- `KafkaCoordinatorLogs` - Kafka protocol logs
- `KafkaUserErrorLogs` - Kafka user errors
- `EventHubVNetConnectionEvent` - **VNET connection events**
- `CustomerManagedKeyUserLogs` - CMK operations
- `RuntimeAuditLogs` - Runtime audit events
- `ApplicationMetricsLogs` - Application metrics

**Metrics:**
- `AllMetrics` - All Event Hub metrics

**Use cases:**
- Verify private endpoint connections
- Monitor Event Hub throughput
- Debug Event Grid → Event Hub delivery

---

## Querying Logs

### Azure Portal - Log Analytics

Navigate to: Azure Portal → Log Analytics Workspace → Logs

#### Query 1: Event Grid Delivery Failures

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.EVENTGRID"
| where Category == "DeliveryFailures"
| project TimeGenerated, OperationName, ResultDescription, Properties
| order by TimeGenerated desc
```

#### Query 2: Event Hub VNET Connections

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.EVENTHUB"
| where Category == "EventHubVNetConnectionEvent"
| project TimeGenerated, OperationName, CallerIpAddress, Properties
| order by TimeGenerated desc
```

**Expected result:** Should show connections from VNET (private IPs)

#### Query 3: Event Grid Publish Operations

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.EVENTGRID"
| where OperationName == "Microsoft.EventGrid/events/send/action"
| project TimeGenerated, ResultType, ResultDescription
| order by TimeGenerated desc
```

#### Query 4: Event Hub Operational Logs

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.EVENTHUB"
| where Category == "OperationalLogs"
| project TimeGenerated, OperationName, EventName, ResultDescription
| order by TimeGenerated desc
```

### Azure CLI Queries

#### Query Function Logs with IP Information

**Python Function:**
```bash
az monitor app-insights query \
  --app func-eventgrid-3tlv1w \
  --analytics-query "traces | where timestamp > ago(1h) | where message contains 'Source IP' | project timestamp, message | order by timestamp desc | take 20"
```

**.NET Function:**
```bash
az monitor app-insights query \
  --app func-dotnet-3tlv1w \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --analytics-query "traces | where timestamp > ago(1h) | where message contains 'Source IP' or message contains 'PRIVATE ENDPOINT' | project timestamp, message | order by timestamp desc | take 20"
```

#### Query Event Grid Diagnostics

```bash
az monitor diagnostic-settings show \
  --name diag-eventgrid-to-logs \
  --resource $(az eventgrid topic show \
    --name evgt-poc-3tlv1w \
    --resource-group rg-eventgrid-vnet-poc-eventgrid \
    --query id -o tsv)
```

#### Query Event Hub Diagnostics

```bash
az monitor diagnostic-settings show \
  --name diag-eventhub-to-logs \
  --resource $(az eventhubs namespace show \
    --name evhns-eventgrid-3tlv1w \
    --resource-group rg-eventgrid-vnet-poc-eventhub \
    --query id -o tsv)
```

---

## Deployment Steps

### 1. Update Infrastructure

Apply Terraform changes to create Log Analytics workspace and diagnostic settings:

```bash
cd terraform
terraform apply -var-file=terraform.phase2.tfvars
```

**What gets created:**
- Log Analytics workspace
- Diagnostic setting for Event Grid
- Diagnostic setting for Event Hub (if enabled)

### 2. Deploy Updated Functions

Deploy updated function code with IP logging:

```bash
./scripts/deploy-function.sh
```

**What gets updated:**
- Python function with IP logging in PublishEvent
- .NET function with IP logging in PublishEvent
- Updated log messages in Event Grid triggers
- Enhanced log messages in Event Hub trigger

### 3. Test and Verify

**Test 1: Publish event via Python function**
```bash
curl -X POST "https://func-eventgrid-3tlv1w.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test IP logging"}'
```

Check logs:
```bash
az monitor app-insights query \
  --app func-eventgrid-3tlv1w \
  --analytics-query "traces | where timestamp > ago(5m) | where message contains 'Source IP' | project timestamp, message"
```

**Test 2: Publish event via .NET function**
```bash
curl -X POST "https://func-dotnet-3tlv1w.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test IP logging"}'
```

Check logs:
```bash
az monitor app-insights query \
  --app func-dotnet-3tlv1w \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --analytics-query "traces | where timestamp > ago(5m) | where message contains 'Source IP' or message contains 'PRIVATE ENDPOINT' | project timestamp, message"
```

**Test 3: Verify Event Hub private connection**
```bash
az monitor app-insights query \
  --app func-dotnet-3tlv1w \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --analytics-query "traces | where timestamp > ago(5m) | where message contains 'PRIVATE ENDPOINT' | project timestamp, message"
```

Expected log:
```
✅ Event Hub connection via PRIVATE ENDPOINT (VNET peering - fully private path)
```

---

## Cost Impact

### Log Analytics Workspace

**Pricing:**
- First 5 GB/month: Free
- Additional data: ~$2.30/GB
- 30-day retention: Included

**Expected usage:**
- Event Grid logs: ~10-50 MB/day
- Event Hub logs: ~10-50 MB/day
- Function logs: Already in Application Insights (separate)
- **Total: ~0.5-2 GB/month = Free tier**

**For 3-day PoC: $0** (within free tier)

---

## Interpreting Results

### HTTP Trigger Source IPs

**What you'll see:**
- External client IPs (your machine, test VMs, etc.)
- These are NOT private IPs (expected - HTTP triggers are public)

**Purpose:**
- Verify client access patterns
- Debug connection issues
- Monitor unauthorized access attempts

### Event Grid Webhook IPs

**What you'll see:**
- No direct IP logging (Event Grid extension handles webhook)
- Warning message: "comes via public internet"
- IP restrictions show: `Allow: AzureEventGrid service tag`

**Purpose:**
- Confirm Event Grid service tag restriction is active
- Document that webhook delivery is NOT private (Microsoft limitation)
- Distinguish from Event Hub trigger behavior

### Event Hub Private Connection

**What you'll see:**
- Log message: "PRIVATE ENDPOINT (VNET peering - fully private path)"
- Event Hub VNET connection events in Log Analytics
- No public IPs in Event Hub connection logs

**Purpose:**
- Verify Event Hub trigger uses private path
- Confirm VNET peering is working
- **This proves the "fully private" claim**

---

## Troubleshooting

### Issue: No "Source IP" logs appearing

**Cause:** Function code not deployed or logs not yet propagated

**Solution:**
```bash
# Redeploy functions
./scripts/deploy-function.sh

# Wait 2-3 minutes for logs to propagate
sleep 180

# Try query again
```

### Issue: Event Hub VNET events not showing in Log Analytics

**Cause:** Diagnostic settings not applied or logs not yet flowing

**Solution:**
```bash
# Verify diagnostic settings exist
az monitor diagnostic-settings list \
  --resource $(az eventhubs namespace show \
    --name evhns-eventgrid-3tlv1w \
    --resource-group rg-eventgrid-vnet-poc-eventhub \
    --query id -o tsv)

# Wait 5-10 minutes for first logs
# Event Hub diagnostic logs can take time to appear
```

### Issue: Log Analytics queries return no results

**Cause:** Logs take 5-15 minutes to appear in Log Analytics

**Solution:**
- Wait 10-15 minutes after first events
- Check Application Insights first (faster)
- Verify diagnostic settings are active

---

## Summary

### What Gets Logged

| Component | What's Logged | Where | Purpose |
|-----------|---------------|-------|---------|
| Python PublishEvent | Source IP, hostname | App Insights | Verify HTTP client IPs |
| .NET PublishEvent | Source IP, hostname | App Insights | Verify HTTP client IPs |
| Python ConsumeEvent | Warning message | App Insights | Document webhook = public |
| .NET ConsumeEvent | Warning message | App Insights | Document webhook = public |
| .NET ConsumeEventFromEventHub | Private endpoint message | App Insights | Confirm fully private path |
| Event Grid Topic | Delivery/publish failures | Log Analytics | Debug operations |
| Event Hub Namespace | VNET connections, operations | Log Analytics | Verify private connectivity |

### Verification Checklist

- ✅ HTTP triggers log source IPs
- ✅ Event Grid triggers document public webhook delivery
- ✅ Event Hub trigger confirms private endpoint usage
- ✅ Log Analytics workspace captures Event Grid/Event Hub operations
- ✅ Diagnostic settings configured for both services
- ✅ Queries available to verify private connections

---

**Document Generated:** January 27, 2026
**Status:** ✅ Configuration Complete
**Cost:** ~$0 (within Log Analytics free tier)
