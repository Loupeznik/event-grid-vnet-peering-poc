# Cross-Subscription Azure Function with Event Grid Integration

This document provides comprehensive guidance for extending the Event Grid VNET peering PoC to support cross-subscription scenarios with a .NET Azure Function.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Traffic Flow Patterns](#traffic-flow-patterns)
- [Webhook Approach](#webhook-approach)
- [Event Hub Alternative](#event-hub-alternative)
- [Cross-Subscription VNET Peering](#cross-subscription-vnet-peering)
- [Managed Identity Cross-Subscription Authentication](#managed-identity-cross-subscription-authentication)
- [Deployment Guide](#deployment-guide)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Cost Analysis](#cost-analysis)

## Architecture Overview

The cross-subscription architecture extends the existing single-subscription setup to demonstrate Event Grid connectivity across Azure subscriptions using VNET peering.

### Architecture Diagram

```
Subscription 1                        Subscription 2
┌─────────────────────────────┐      ┌─────────────────────────────┐
│                             │      │                             │
│  VNET1 (10.0.0.0/16)        │      │  VNET3 (10.2.0.0/16)        │
│  ┌───────────────────────┐  │      │  ┌───────────────────────┐  │
│  │ Python Function       │  │      │  │ .NET Function         │  │
│  │ - PublishEvent        │  │      │  │ - PublishEvent        │  │
│  │ - ConsumeEvent        │  │      │  │ - ConsumeEvent        │  │
│  └───────────────────────┘  │      │  └───────────────────────┘  │
│           │                 │      │           │                 │
│           │ VNET Integration│      │           │ VNET Integration│
│           ▼                 │      │           ▼                 │
│  ┌───────────────────────┐  │      │  ┌───────────────────────┐  │
│  │ Subnet (10.0.1.0/27)  │  │      │  │ Subnet (10.2.1.0/27)  │  │
│  └───────────────────────┘  │      │  └───────────────────────┘  │
│           │                 │      │           │                 │
└───────────┼─────────────────┘      └───────────┼─────────────────┘
            │                                    │
            │ Peering                   Peering  │
            └────────────┬───────────────────────┘
                         │
                         ▼
            ┌─────────────────────────┐
            │  VNET2 (10.1.0.0/16)    │
            │  ┌───────────────────┐  │
            │  │ Event Grid Topic  │  │
            │  │ Private Endpoint  │  │
            │  │ (10.1.1.x)        │  │
            │  └───────────────────┘  │
            │                         │
            │  Private DNS Zone:      │
            │  privatelink.eventgrid  │
            │  .azure.net             │
            │  - Linked to VNET1      │
            │  - Linked to VNET2      │
            │  - Linked to VNET3      │
            └─────────────────────────┘
```

### Components

**Subscription 1 (Primary)**:
- Python Function App in VNET1 (10.0.0.0/16)
- Event Grid Topic in VNET2 (10.1.0.0/16) with private endpoint
- Private DNS zone for Event Grid (linked to all three VNETs)
- Bi-directional VNET peering between VNET1 and VNET2

**Subscription 2 (Secondary)**:
- .NET Function App in VNET3 (10.2.0.0/16)
- Cross-subscription VNET peering between VNET3 and VNET2
- Managed identity with roles in Subscription 1

## Traffic Flow Patterns

### Publishing Flow (Private via VNET Peering)

Both Python and .NET functions publish to Event Grid through the private endpoint:

1. Function resolves Event Grid hostname via Private DNS zone
2. DNS returns private IP address (10.1.1.x)
3. Traffic routes through VNET peering to private endpoint
4. Event Grid receives event via private connection
5. No traffic traverses public internet

**Status**: ✅ Fully private, secured via VNET peering

### Delivery Flow (Webhook via Azure Backbone)

Event Grid delivers events to functions via public webhook endpoints:

1. Event Grid triggers webhook delivery
2. Webhook targets function's public HTTPS endpoint
3. Traffic flows over Azure backbone network (not public internet)
4. Function receives event via Event Grid trigger

**Status**: ⚠️ Uses public endpoint (HTTPS), but stays on Azure backbone

## Webhook Approach

This implementation uses Event Grid's webhook delivery mechanism for function triggers.

### How It Works

Event Grid delivers events to Azure Functions by calling the function's public HTTPS endpoint. Even though the Event Grid topic has a private endpoint for publishing, event delivery to subscribers always uses webhook endpoints.

### Security Characteristics

**Positive**:
- Traffic never leaves Azure backbone network
- HTTPS encryption for all webhook calls
- Event Grid validates webhook endpoints
- Function App authentication can be enforced
- Azure backbone provides network isolation from internet

**Limitations**:
- Function App must have publicly accessible endpoint
- Not truly "air-gapped" or fully private
- Cannot restrict Event Grid delivery to private IP
- Delivery path doesn't use VNET peering
- Traffic flow asymmetry (private publish, public delivery)

### When to Use

The webhook approach is suitable when:
- Publishing to Event Grid must be private (via VNET peering)
- Event delivery can use Azure backbone (not fully private)
- Cost optimization is important
- Simplicity is preferred over maximum isolation
- Compliance doesn't require fully private event delivery

### Drawbacks

1. **Not Fully Private**: Functions must expose public endpoints
2. **Asymmetric Traffic**: Publishing is private, delivery is not
3. **Limited Network Control**: Cannot apply NSG rules to incoming Event Grid traffic
4. **Compliance Concerns**: May not meet strict air-gap requirements

### Webhook Security Enhancements

While webhook delivery uses public endpoints, the implementation includes multiple security layers:

**IP Restrictions**:
- Restrict function access to `AzureEventGrid` service tag
- Allow `AzureCloud` for Azure management operations
- Support custom IP allowlist for additional access
- Deny all other traffic

**Entra ID Authentication**:
- Azure AD app registrations for each function
- Event Grid uses managed identity to authenticate
- Token-based webhook calls
- Automatic token validation

**Configuration**:
```hcl
# terraform.tfvars
enable_function_authentication = true
allowed_ip_addresses = [
  "203.0.113.0/24",  # Your corporate network
  "198.51.100.42/32"  # Specific trusted IP
]
```

**Security Model**:
```
Internet (403 Forbidden)
   ↓
Event Grid Service IPs (Allowed via service tag)
   ↓ (HTTPS + Azure AD token)
Function IP Restrictions (Validates source)
   ↓
Function Auth Layer (Validates Azure AD token)
   ↓
Function Code (Validates event content)
```

See [docs/SECURITY.md](../SECURITY.md) for complete security configuration guide.

## Event Hub Alternative

For scenarios requiring fully private bidirectional communication, use Event Hub as an intermediary.

### Architecture

```
Function → Event Grid (private) → Event Hub (private) → Function
```

Instead of Event Grid delivering directly to functions:
1. Event Grid topic has system subscription to Event Hub
2. Event Hub has private endpoint in VNET
3. Functions use Event Hub trigger (private connection)
4. Both publishing and delivery are fully private

### Required Additional Components

**Event Hub Namespace**:
- Standard or Premium tier
- Private endpoint in VNET2
- DNS integration with Private DNS zone

**Event Hub**:
- Event Hub instance within namespace
- Event Grid system subscription

**Updated Function Configuration**:
- Change from Event Grid trigger to Event Hub trigger
- Update connection strings to use VNET-routed endpoint
- Configure managed identity for Event Hub access

### Implementation Changes

**Terraform Resources**:
```hcl
resource "azurerm_eventhub_namespace" "main" {
  name                = "evhns-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.eventgrid.name
  location            = var.location
  sku                 = "Standard"

  network_rulesets {
    default_action = "Deny"
    virtual_network_rule {
      subnet_id = azurerm_subnet.private_endpoint_subnet.id
    }
  }
}

resource "azurerm_eventhub" "main" {
  name                = "evh-eventgrid"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.eventgrid.name
  partition_count     = 2
  message_retention   = 1
}

resource "azurerm_private_endpoint" "eventhub" {
  name                = "pe-eventhub"
  resource_group_name = azurerm_resource_group.eventgrid.name
  location            = var.location
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "eventhub-connection"
    private_connection_resource_id = azurerm_eventhub_namespace.main.id
    subresource_names              = ["namespace"]
    is_manual_connection           = false
  }
}

resource "azurerm_eventgrid_event_subscription" "to_eventhub" {
  name  = "eventgrid-to-eventhub"
  scope = azurerm_eventgrid_topic.main.id

  eventhub_endpoint_id = azurerm_eventhub.main.id
}
```

**Function Changes**:
- Replace `[EventGridTrigger]` with `[EventHubTrigger]`
- Update connection string app setting
- Add Event Hub SDK packages

### Cost Comparison

**Webhook Approach (Current)**:
- Event Grid Topic: $0.60/million operations
- Private Endpoint: $0.01/hour = $7.30/month
- Total: ~$8-10/month

**Event Hub Alternative**:
- Event Grid Topic: $0.60/million operations
- Event Hub Standard: $11/month (1 throughput unit)
- Event Hub Private Endpoint: $7.30/month
- Event Grid Private Endpoint: $7.30/month
- Total: ~$25-30/month

**Cost Increase**: ~$17-20/month for fully private architecture

### When to Use Event Hub Approach

Use Event Hub when:
- Compliance requires fully private event delivery
- Air-gapped architecture is mandatory
- Network security policies prohibit public endpoints
- Budget allows for additional Event Hub costs
- Event Hub features (partitioning, replay) are beneficial

## Cross-Subscription VNET Peering

VNET peering works seamlessly across subscriptions within the same Azure AD tenant.

### How It Works

Cross-subscription peering creates bidirectional network connectivity:
1. VNET3 (Subscription 2) peers to VNET2 (Subscription 1)
2. VNET2 (Subscription 1) peers to VNET3 (Subscription 2)
3. Both peerings must be created with corresponding settings
4. Private DNS zone in Subscription 1 is linked to VNET3

### Permission Requirements

**In Both Subscriptions**:
- Network Contributor role on target VNET
- Ability to create VNET peering resources

**Terraform Provider**:
- Authenticate to both subscriptions via `az login`
- Use provider aliases for multi-subscription deployment

### Same-Region vs Cross-Region Considerations

**Same-Region Deployment (Default)**:
- Lower latency (<5ms typically)
- Lower data transfer costs ($0.01/GB)
- Simpler DNS resolution
- Faster peering setup

**Cross-Region Deployment**:
- Higher latency (50-100ms typical)
- Higher VNET peering costs ($0.035/GB ingress + egress)
- Potential DNS resolution delays
- Geographic redundancy benefits

**When to Use Cross-Region**:
- Geographic distribution requirements
- Disaster recovery architecture
- Compliance mandates data residency
- Load distribution across regions

**Cost Impact (Cross-Region)**:
- 3.5x higher data transfer costs
- Example: 100GB/month = $3.50 (cross-region) vs $1.00 (same-region)

### Non-Overlapping Address Spaces

VNETs must have unique address spaces:
- VNET1: 10.0.0.0/16
- VNET2: 10.1.0.0/16
- VNET3: 10.2.0.0/16

Overlapping addresses will cause peering to fail.

## Managed Identity Cross-Subscription Authentication

Azure managed identities work across subscriptions within the same tenant.

### How It Works

1. .NET Function has system-assigned managed identity (created in Subscription 2)
2. Role assignments grant permissions in Subscription 1:
   - EventGrid Data Sender role on Event Grid topic
   - EventGrid Contributor role for subscription management
3. DefaultAzureCredential automatically authenticates using managed identity
4. Event Grid validates identity and permissions

### Role Assignment Configuration

Terraform automatically creates cross-subscription role assignments:

```hcl
resource "azurerm_role_assignment" "dotnet_function_eventgrid_sender" {
  scope                = azurerm_eventgrid_topic.main.id  # Subscription 1
  role_definition_name = "EventGrid Data Sender"
  principal_id         = azurerm_linux_function_app.dotnet[0].identity[0].principal_id  # Subscription 2
}
```

### Role Propagation Timing

Role assignments can take 5-10 minutes to propagate across Azure AD. If functions fail with 401/403 errors immediately after deployment, wait and retry.

## Deployment Guide

### Prerequisites

1. **Azure Subscriptions**:
   - Access to two Azure subscriptions in same tenant
   - Owner or Contributor + User Access Administrator roles in both

2. **Development Tools**:
   - Azure CLI installed and authenticated
   - Terraform 1.0 or later
   - .NET SDK 10.0 or later
   - Bash shell (Linux, macOS, or WSL on Windows)

3. **Authentication**:
   ```bash
   az login
   az account list --output table
   ```

### Step-by-Step Deployment

#### 1. Configure Terraform Variables

Create `terraform/terraform.tfvars`:

```hcl
subscription_id     = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
subscription_id_2   = "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
enable_dotnet_function = true
location            = "northeurope"
```

#### 2. Initialize and Plan

```bash
cd terraform
terraform init
terraform plan
```

Review the plan to ensure:
- Resources are created in correct subscriptions
- Cross-subscription peerings are configured
- Private DNS zone links all three VNETs

#### 3. Apply Infrastructure

```bash
terraform apply
```

This creates:
- **Subscription 1**: Python function, Event Grid, VNET1, VNET2, peerings, private endpoints, DNS
- **Subscription 2**: .NET function, VNET3, cross-subscription peering
- **Cross-subscription**: Role assignments, DNS links, peerings

Deployment takes 10-15 minutes.

#### 4. Deploy Function Code

```bash
cd ..
./scripts/deploy-function.sh
```

This script:
- Deploys Python function code to Subscription 1
- Builds and deploys .NET function code to Subscription 2
- Creates Event Grid subscriptions for both functions
- Verifies function registration

Deployment takes 3-5 minutes.

#### 5. Verify Deployment

```bash
./scripts/test-connectivity.sh
```

This runs comprehensive tests:
- Python → Event Grid → Python
- Python → Event Grid → .NET
- .NET → Event Grid → Python
- .NET → Event Grid → .NET
- VNET peering status verification

### Manual Deployment Steps

If automated scripts fail, deploy manually:

#### Deploy Python Function

```bash
cd function
zip -r deployment.zip . -x "*.pyc" -x "__pycache__/*"
az functionapp deployment source config-zip \
  --resource-group rg-eventgrid-vnet-poc-function \
  --name <python-function-name> \
  --src deployment.zip
```

#### Deploy .NET Function

```bash
cd EventGridPubSubFunction
dotnet publish -c Release -o bin/Release/publish
cd bin/Release/publish
zip -r ../../../deployment.zip .
az account set --subscription <subscription-2-id>
az functionapp deployment source config-zip \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --name <dotnet-function-name> \
  --src ../../deployment.zip
```

## Testing

### Test Scenarios

**Test 1: Python to Python**
```bash
curl -X POST https://<python-function>.azurewebsites.net/api/publish \
  -H "Content-Type: application/json" \
  -d '{"message": "Test: Python to Python"}'
```

**Test 2: Python to .NET**
```bash
curl -X POST https://<python-function>.azurewebsites.net/api/publish \
  -H "Content-Type: application/json" \
  -d '{"message": "Test: Python to .NET"}'
```

**Test 3: .NET to Python**
```bash
curl -X POST https://<dotnet-function>.azurewebsites.net/api/publish \
  -H "Content-Type: application/json" \
  -d '{"message": "Test: .NET to Python"}'
```

**Test 4: .NET to .NET**
```bash
curl -X POST https://<dotnet-function>.azurewebsites.net/api/publish \
  -H "Content-Type: application/json" \
  -d '{"message": "Test: .NET to .NET"}'
```

### Verify Private Connectivity

Check Application Insights logs for "Successfully received event via private endpoint" messages.

Verify DNS resolution returns private IP:
```bash
az webapp log tail --name <function-name> --resource-group <rg-name>
```

## Troubleshooting

### Common Issues

#### DNS Resolution Failures

**Symptom**: Function cannot resolve Event Grid hostname

**Causes**:
- Private DNS zone not linked to VNET
- VNET integration not configured
- DNS propagation delay

**Solutions**:
```bash
# Verify DNS zone link
az network private-dns link vnet list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --zone-name privatelink.eventgrid.azure.net

# Check VNET integration
az functionapp vnet-integration list \
  --name <function-name> \
  --resource-group <rg-name>

# Wait 5-10 minutes for DNS propagation
```

#### Cross-Subscription Peering Disconnected

**Symptom**: Peering shows "Disconnected" state

**Causes**:
- Only one side of peering created
- Insufficient permissions
- VNET address space overlap

**Solutions**:
```bash
# Check both peering sides
az network vnet peering list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-eventgrid-*

az account set --subscription <subscription-2-id>
az network vnet peering list \
  --resource-group rg-eventgrid-vnet-poc-dotnet-network \
  --vnet-name vnet-dotnet-*

# Verify address spaces don't overlap
az network vnet show --name <vnet-name> --resource-group <rg-name> --query addressSpace
```

#### Role Assignment Permission Denied

**Symptom**: Function receives 401/403 when publishing to Event Grid

**Causes**:
- Role assignments not propagated
- Incorrect role definition
- Managed identity not enabled

**Solutions**:
```bash
# Wait 5-10 minutes for propagation
sleep 300

# Verify role assignments
az role assignment list \
  --scope /subscriptions/<sub-1-id>/resourceGroups/rg-eventgrid-vnet-poc-eventgrid/providers/Microsoft.EventGrid/topics/<topic-name> \
  --query "[?principalId=='<dotnet-function-principal-id>']"

# Check managed identity enabled
az functionapp identity show \
  --name <dotnet-function-name> \
  --resource-group <rg-name>
```

#### Webhook Delivery Failures

**Symptom**: Events published but not received by function

**Causes**:
- Event Grid subscription not created
- Function not registered with Azure
- Webhook validation failed

**Solutions**:
```bash
# List Event Grid subscriptions
az eventgrid event-subscription list \
  --source-resource-id /subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.EventGrid/topics/<topic-name>

# Verify function exists
az functionapp function list \
  --name <function-name> \
  --resource-group <rg-name>

# Check Event Grid delivery logs
az monitor activity-log list \
  --resource-group <rg-name> \
  --offset 30m
```

## Cost Analysis

### Multi-Subscription Setup

**Subscription 1 (Monthly)**:
- Python Function (B1 App Service Plan): $13.14
- Event Grid Topic: $0.60/million operations
- Event Grid Private Endpoint: $7.30
- VNET Peering (to VNET2): $0.01/GB
- VNET Peering (to VNET3): $0.01/GB
- Private DNS Zone: $0.50
- Storage Account: $0.05
- Application Insights: $2.30

**Subscription 1 Subtotal**: ~$23-25/month

**Subscription 2 (Monthly)**:
- .NET Function (B1 App Service Plan): $13.14
- VNET Peering (to VNET2): $0.01/GB
- Storage Account: $0.05
- Application Insights: $2.30

**Subscription 2 Subtotal**: ~$15-17/month

**Total Cross-Subscription Cost**: ~$38-42/month

### Single Subscription Baseline

For comparison, single-subscription setup:
- Python Function: $13.14
- Event Grid: $0.60
- Private Endpoint: $7.30
- VNET Peering: $0.01/GB
- Other: ~$3

**Baseline Cost**: ~$23-25/month

**Cross-Subscription Premium**: ~$15-17/month additional

### Cost Optimization Tips

1. **Use Consumption Plan** (if VNET integration not required)
2. **Reduce App Service Plan tier** (B1 → B1 during development)
3. **Delete resources when not in use** (PoC environments)
4. **Use same region** to minimize data transfer costs
5. **Monitor Event Grid operations** to optimize usage

### Event Hub Alternative Cost Impact

Adding Event Hub for fully private delivery:
- Event Hub Standard: +$11/month
- Event Hub Private Endpoint: +$7.30/month
- Total Additional: +$18.30/month

**Total with Event Hub**: ~$56-60/month

## Conclusion

The cross-subscription webhook approach demonstrates Event Grid connectivity across Azure subscriptions using VNET peering. Publishing is fully private via private endpoints, while delivery uses Azure backbone webhooks.

For scenarios requiring fully private bidirectional communication, the Event Hub alternative provides complete network isolation at additional cost and complexity.
