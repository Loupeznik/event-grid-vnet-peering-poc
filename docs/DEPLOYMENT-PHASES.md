# Phased Deployment Guide

This guide explains the phased deployment approach required for reliable cross-subscription deployment.

## Why Phased Deployment?

Cross-subscription VNET peering with azurerm provider v4.x has known issues when all resources are deployed simultaneously. The phased approach ensures:

1. ✅ All Subscription 1 resources are fully provisioned
2. ✅ Subscription 2 resources can reliably reference Subscription 1 resources
3. ✅ Cross-subscription VNET peering completes successfully
4. ✅ No race conditions or "inconsistent result" errors

See [KNOWN-ISSUES.md](KNOWN-ISSUES.md) for technical details.

## Prerequisites

### Subscription 1 (Primary)
- Owner or Contributor role
- Resource providers registered
- No quota limitations

### Subscription 2 (Secondary) - Phase 2 Only
- Owner or Contributor role
- Resource providers registered:
  ```bash
  az account set --subscription "subscription-2-id"
  az provider register --namespace Microsoft.Network
  az provider register --namespace Microsoft.Web
  az provider register --namespace Microsoft.Storage
  az provider register --namespace Microsoft.Insights
  ```
- App Service quota available (minimum 1 Basic tier)

## Phase 1: Single Subscription Deployment

### What Gets Deployed

**Subscription 1**:
- Resource groups (network, eventgrid, function)
- VNET1 (10.0.0.0/16) - Python Function VNET
- VNET2 (10.1.0.0/16) - Event Grid VNET
- Bi-directional VNET peering (VNET1 ↔ VNET2)
- Private DNS zone (privatelink.eventgrid.azure.net)
- Event Grid Topic with private endpoint
- Python Function App with VNET integration
- Application Insights
- Storage Account
- Azure AD app registration (if auth enabled)

### Configuration File

Use `terraform.phase1.tfvars`:

```hcl
subscription_id = "your-subscription-1-id"
location = "swedencentral"
enable_dotnet_function = false  # Critical: must be false
enable_function_authentication = true
allowed_ip_addresses = []
```

### Deployment Commands

```bash
# Navigate to terraform directory
cd terraform

# Initialize Terraform
terraform init

# Review plan
terraform plan -var-file=terraform.phase1.tfvars

# Apply (creates Subscription 1 resources)
terraform apply -var-file=terraform.phase1.tfvars
```

### Verification

Verify Phase 1 deployment:

```bash
# Check resource groups
az account set --subscription "subscription-1-id"
az group list --query "[?starts_with(name, 'rg-eventgrid-vnet-poc')].name" -o table

# Check VNETs
az network vnet list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --query "[].{Name:name, AddressSpace:addressSpace.addressPrefixes[0]}" \
  -o table

# Check VNET peering
az network vnet peering list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-function-* \
  --query "[].{Name:name, State:peeringState}" \
  -o table

# Check Function App
az functionapp list \
  --resource-group rg-eventgrid-vnet-poc-function \
  --query "[].{Name:name, State:state}" \
  -o table

# Test Python function
FUNCTION_NAME=$(terraform output -raw function_app_name)
curl -X POST "https://$FUNCTION_NAME.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Phase 1 test"}'
```

### Expected Results

- ✅ 3 resource groups created
- ✅ 2 VNETs with bi-directional peering
- ✅ Event Grid with private endpoint
- ✅ Python function responds to HTTP requests
- ✅ Terraform state contains all Phase 1 resources

### Troubleshooting Phase 1

**Issue: Resource provider not registered**
```bash
az provider register --namespace Microsoft.Web
az provider show --namespace Microsoft.Web --query "registrationState"
```

**Issue: Quota exceeded**
```bash
# Check quotas
az quota list \
  --scope "/subscriptions/subscription-1-id/providers/Microsoft.Web/locations/swedencentral"
```

**Issue: VNET peering not connected**
```bash
# Check peering status
az network vnet peering show \
  --name peer-function-to-eventgrid \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-function-*
```

## Phase 2: Cross-Subscription Deployment

⚠️ **IMPORTANT**: Only proceed if Phase 1 completed successfully!

### Deployment Modes

Phase 2 supports two delivery modes for the .NET function:

| Mode | Delivery Path | Privacy | Cost (3-day PoC) | Use Case |
|------|--------------|---------|------------------|----------|
| **Webhook** (default) | Event Grid → .NET Function webhook | Public endpoint with IP restrictions | ~$3-5 | Standard deployment, cost-effective |
| **Service Bus** (optional) | Event Grid → Service Bus → .NET Function | Fully private via VNET peering | ~$70-72 | Maximum security, requires Premium SKU |

⚠️ **Important**: Service Bus requires **Premium SKU** (~$677/month) for private endpoint support. This is expensive for a PoC. Only enable if fully private delivery is a hard requirement.

Configure via `enable_service_bus` variable (see Configuration File section below).

### What Gets Added

**Subscription 2** (always):
- Resource groups (dotnet-network, dotnet-function)
- VNET3 (10.2.0.0/16) - .NET Function VNET
- Cross-subscription VNET peering (VNET3 ↔ VNET2)
- .NET Function App with VNET integration
- Application Insights (separate instance)
- Storage Account
- Azure AD app registration (if auth enabled)

**Subscription 1 Updates** (always):
- Private DNS zone VNET link to VNET3
- IAM role assignments for .NET function

**Subscription 1 - Webhook Mode** (`enable_service_bus=false`, default):
- Event Grid subscription to .NET function webhook endpoint

**Subscription 1 - Service Bus Mode** (`enable_service_bus=true`, optional):
- Resource group (servicebus)
- Service Bus namespace (Standard SKU, private only)
- Service Bus queue ("events") with dead-lettering
- Private endpoint for Service Bus in VNET2
- Private DNS zone for Service Bus linked to all VNETs
- Event Grid subscription to Service Bus queue
- IAM role assignments (Event Grid → Service Bus, .NET Function → Service Bus)

### Configuration File

**Webhook Mode** (default) - `terraform.phase2.tfvars`:

```hcl
subscription_id = "your-subscription-1-id"
subscription_id_2 = "your-subscription-2-id"
location = "swedencentral"  # Must match Phase 1
enable_dotnet_function = true  # Critical: must be true
enable_service_bus = false  # Default: webhook delivery
enable_function_authentication = true
allowed_ip_addresses = []
```

**Service Bus Mode** (optional) - `terraform.phase2-servicebus.tfvars`:

```hcl
subscription_id = "your-subscription-1-id"
subscription_id_2 = "your-subscription-2-id"
location = "swedencentral"  # Must match Phase 1
enable_dotnet_function = true  # Critical: must be true
enable_service_bus = true  # Enable fully private delivery
enable_function_authentication = true
allowed_ip_addresses = []
```

**Notes:**
- `enable_service_bus` requires `enable_dotnet_function=true` (enforced by validation)
- Service Bus requires **Premium SKU** for private endpoint support
- Service Bus Premium adds **~$677/month** (~$67 for 3-day PoC) to infrastructure costs
- Both modes can coexist in code; switch by changing variable and redeploying

⚠️ **Cost Warning**: Service Bus Premium is expensive for a PoC. Consider webhook mode unless fully private delivery is required.

### Pre-Deployment Checks

```bash
# Verify Phase 1 resources exist
terraform show | grep "resource_group_network"

# Check Subscription 2 access
az account set --subscription "subscription-2-id"
az account show

# Verify resource providers in Subscription 2
az provider list \
  --query "[?namespace=='Microsoft.Web' || namespace=='Microsoft.Network'].{Provider:namespace, State:registrationState}" \
  -o table
```

### Deployment Commands

**Webhook Mode** (default):
```bash
# Ensure you're in terraform directory
cd terraform

# Review Phase 2 changes
terraform plan -var-file=terraform.phase2.tfvars

# Apply Phase 2 (adds Subscription 2 resources)
terraform apply -var-file=terraform.phase2.tfvars
```

**Service Bus Mode** (optional):
```bash
# Ensure you're in terraform directory
cd terraform

# Review Phase 2 changes with Service Bus
terraform plan -var-file=terraform.phase2-servicebus.tfvars

# Apply Phase 2 with Service Bus (adds Subscription 2 resources + Service Bus)
terraform apply -var-file=terraform.phase2-servicebus.tfvars
```

**Or use inline variable**:
```bash
terraform apply -var="enable_service_bus=true" -var-file=terraform.phase2.tfvars
```

### Verification

Verify Phase 2 deployment:

```bash
# Check Subscription 2 resource groups
az account set --subscription "subscription-2-id"
az group list --query "[?starts_with(name, 'rg-eventgrid-vnet-poc')].name" -o table

# Check VNET3
az network vnet list \
  --resource-group rg-eventgrid-vnet-poc-dotnet-network \
  --query "[].{Name:name, AddressSpace:addressSpace.addressPrefixes[0]}" \
  -o table

# Check cross-subscription peering (Subscription 2 side)
az network vnet peering list \
  --resource-group rg-eventgrid-vnet-poc-dotnet-network \
  --vnet-name vnet-dotnet-* \
  --query "[].{Name:name, State:peeringState, RemoteVNet:remoteVirtualNetwork.id}" \
  -o table

# Check cross-subscription peering (Subscription 1 side)
az account set --subscription "subscription-1-id"
az network vnet peering show \
  --name peer-eventgrid-to-dotnet \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-eventgrid-* \
  --query "{Name:name, State:peeringState}"

# Check .NET Function App
az account set --subscription "subscription-2-id"
az functionapp list \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --query "[].{Name:name, State:state}" \
  -o table

# Test .NET function
cd ../terraform
DOTNET_FUNCTION_NAME=$(terraform output -raw dotnet_function_app_name)
curl -X POST "https://$DOTNET_FUNCTION_NAME.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Phase 2 test"}'
```

**Additional checks for Service Bus Mode** (`enable_service_bus=true`):

```bash
# Check Service Bus resource group
az account set --subscription "subscription-1-id"
az group show --name rg-eventgrid-vnet-poc-servicebus

# Check Service Bus namespace
SERVICEBUS_NAMESPACE=$(cd terraform && terraform output -raw servicebus_namespace_name)
az servicebus namespace show \
  --name "$SERVICEBUS_NAMESPACE" \
  --resource-group rg-eventgrid-vnet-poc-servicebus \
  --query "{Name:name, Sku:sku.name, PublicAccess:publicNetworkAccess}"

# Check Service Bus queue
az servicebus queue show \
  --namespace-name "$SERVICEBUS_NAMESPACE" \
  --resource-group rg-eventgrid-vnet-poc-servicebus \
  --name events \
  --query "{Name:name, MaxDelivery:maxDeliveryCount, DeadLetter:deadLetteringOnMessageExpiration}"

# Check Event Grid subscription type
az eventgrid event-subscription list \
  --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-eventgrid-vnet-poc-eventgrid/providers/Microsoft.EventGrid/topics/$EVENTGRID_TOPIC_NAME" \
  --query "[].{Name:name, Type:destination.endpointType, Status:provisioningState}" \
  -o table

# Verify Service Bus connection in .NET function
az account set --subscription "subscription-2-id"
az functionapp config appsettings list \
  --name "$DOTNET_FUNCTION_NAME" \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --query "[?contains(name, 'ServiceBus')].{Name:name, Value:value}" \
  -o table
```

### Expected Results

**Webhook Mode** (default):
- ✅ 5 total resource groups (3 in Sub1, 2 in Sub2)
- ✅ 3 VNETs with full mesh peering
- ✅ Private DNS zone (eventgrid) linked to all 3 VNETs
- ✅ Both functions respond to HTTP requests
- ✅ All VNET peerings show "Connected" state
- ✅ Event Grid subscription type: `azurefunction`

**Service Bus Mode** (optional):
- ✅ 6 total resource groups (4 in Sub1, 2 in Sub2)
- ✅ 3 VNETs with full mesh peering
- ✅ Private DNS zones (eventgrid + servicebus) linked to all 3 VNETs
- ✅ Both functions respond to HTTP requests
- ✅ All VNET peerings show "Connected" state
- ✅ Event Grid subscription type: `servicebusqueue`
- ✅ Service Bus namespace with **Premium SKU** (required for private endpoints), public access disabled
- ✅ Service Bus queue configured with dead-lettering
- ✅ .NET function has `ServiceBusConnection__fullyQualifiedNamespace` setting

### Troubleshooting Phase 2

**Issue: VNET peering inconsistent result**
- **Cause**: Known azurerm provider bug
- **Solution**: Already using phased deployment
- **Verify**: Check that Phase 1 completed fully before running Phase 2

**Issue: Cross-subscription peering shows "Disconnected"**
```bash
# Check peering in both subscriptions
az account set --subscription "subscription-1-id"
az network vnet peering show \
  --name peer-eventgrid-to-dotnet \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-eventgrid-*

az account set --subscription "subscription-2-id"
az network vnet peering show \
  --name peer-dotnet-to-eventgrid \
  --resource-group rg-eventgrid-vnet-poc-dotnet-network \
  --vnet-name vnet-dotnet-*
```

**Issue: .NET function quota error**
- See [KNOWN-ISSUES.md](KNOWN-ISSUES.md#quota-limitations-in-new-subscriptions)
- Request quota increase or use different region

**Issue: Private DNS zone link fails**
```bash
# Verify DNS zone exists
az network private-dns zone show \
  --name privatelink.eventgrid.azure.net \
  --resource-group rg-eventgrid-vnet-poc-network

# Verify VNET3 exists
az account set --subscription "subscription-2-id"
az network vnet show \
  --name vnet-dotnet-* \
  --resource-group rg-eventgrid-vnet-poc-dotnet-network
```

**Issue: Service Bus validation error** (`enable_service_bus=true` without `.NET function`)
- **Cause**: `enable_service_bus` requires `enable_dotnet_function=true`
- **Error**: "enable_service_bus requires enable_dotnet_function to be true"
- **Solution**: Ensure both variables are set to `true` in tfvars file

**Issue: Service Bus queue messages not processing**
```bash
# Check queue status
SERVICEBUS_NAMESPACE=$(cd terraform && terraform output -raw servicebus_namespace_name)
az servicebus queue show \
  --namespace-name "$SERVICEBUS_NAMESPACE" \
  --resource-group rg-eventgrid-vnet-poc-servicebus \
  --name events \
  --query "countDetails.{Active:activeMessageCount, DeadLetter:deadLetterMessageCount}"

# Check IAM roles
az role assignment list \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-eventgrid-vnet-poc-servicebus/providers/Microsoft.ServiceBus/namespaces/$SERVICEBUS_NAMESPACE" \
  --query "[?roleDefinitionName=='Azure Service Bus Data Receiver' || roleDefinitionName=='Azure Service Bus Data Sender'].{Role:roleDefinitionName, Principal:principalName}"

# Check function logs
az account set --subscription "subscription-2-id"
DOTNET_FUNCTION_NAME=$(cd terraform && terraform output -raw dotnet_function_app_name)
az monitor app-insights query \
  --app "$DOTNET_FUNCTION_NAME" \
  --analytics-query "traces | where timestamp > ago(10m) | where message contains 'Service Bus' | order by timestamp desc | take 20"
```

## Function Code Deployment

After both phases complete successfully, deploy function code:

```bash
# From project root
./scripts/deploy-function.sh
```

This script automatically:
1. Deploys Python function code
2. Deploys .NET function code (if enabled)
3. Creates Event Grid subscriptions:
   - Python function: Always webhook endpoint
   - .NET function: Webhook endpoint (default) OR Service Bus queue (if `enable_service_bus=true`)
4. Verifies function registration

**Webhook Mode**: Script creates Event Grid subscription to .NET function's `ConsumeEvent` webhook endpoint

**Service Bus Mode**: Script creates Event Grid subscription to Service Bus queue; .NET function's `ConsumeEventFromQueue` trigger processes messages

## Testing

Run comprehensive connectivity tests:

```bash
./scripts/test-connectivity.sh
```

Tests include:
- Python → Event Grid → Python (webhook)
- Python → Event Grid → .NET (webhook or Service Bus, if Phase 2 deployed)
- .NET → Event Grid → Python (webhook, if Phase 2 deployed)
- .NET → Event Grid → .NET (webhook or Service Bus, if Phase 2 deployed)
- VNET peering verification

**Service Bus Mode Validation**:
When `enable_service_bus=true`, verify logs show "FULLY PRIVATE path" message:
```bash
# Check .NET function logs for Service Bus processing
az account set --subscription "subscription-2-id"
DOTNET_FUNCTION_NAME=$(cd terraform && terraform output -raw dotnet_function_app_name)
az monitor app-insights query \
  --app "$DOTNET_FUNCTION_NAME" \
  --analytics-query "traces | where timestamp > ago(5m) | where message contains 'FULLY PRIVATE' or message contains 'Service Bus Queue Trigger' | order by timestamp desc"
```

## Cleanup

### Destroy Phase 2 Resources

```bash
cd terraform
terraform destroy -var-file=terraform.phase2.tfvars
```

### Destroy Phase 1 Resources

```bash
cd terraform
terraform destroy -var-file=terraform.phase1.tfvars
```

### Complete Cleanup

**Webhook Mode**:
```bash
# Delete all resource groups manually if Terraform destroy fails
az account set --subscription "subscription-1-id"
az group delete --name rg-eventgrid-vnet-poc-network --yes --no-wait
az group delete --name rg-eventgrid-vnet-poc-eventgrid --yes --no-wait
az group delete --name rg-eventgrid-vnet-poc-function --yes --no-wait

az account set --subscription "subscription-2-id"
az group delete --name rg-eventgrid-vnet-poc-dotnet-network --yes --no-wait
az group delete --name rg-eventgrid-vnet-poc-dotnet-function --yes --no-wait

# Clean Azure AD apps
az ad app list --display-name "func-python-*" --query "[].appId" -o tsv | xargs -I {} az ad app delete --id {}
az ad app list --display-name "func-dotnet-*" --query "[].appId" -o tsv | xargs -I {} az ad app delete --id {}
```

**Service Bus Mode** (additional cleanup):
```bash
# Delete Service Bus resource group
az account set --subscription "subscription-1-id"
az group delete --name rg-eventgrid-vnet-poc-servicebus --yes --no-wait

# Or use Terraform destroy to clean up properly
cd terraform
terraform destroy -var-file=terraform.phase2-servicebus.tfvars
```

## Summary

| Phase | Purpose | Time | Subscriptions | Resource Groups |
|-------|---------|------|---------------|-----------------|
| Phase 1 | Deploy core infrastructure | 10-15 min | Subscription 1 | 3 (Sub1) |
| Phase 2 (Webhook) | Add cross-subscription | 10-15 min | Subscription 1 + 2 | 5 total (3 in Sub1, 2 in Sub2) |
| Phase 2 (Service Bus) | Add cross-subscription + private delivery | 12-18 min | Subscription 1 + 2 | 6 total (4 in Sub1, 2 in Sub2) |
| Deploy Code | Deploy functions | 5-10 min | Both | - |
| Testing | Verify connectivity | 5 min | Both | - |

**Total deployment time**:
- Webhook mode: ~30-45 minutes
- Service Bus mode: ~35-50 minutes

**Cost Impact**:
- Webhook mode: ~$3-5 USD for 3-day PoC
- Service Bus mode: ~$70-72 USD for 3-day PoC (additional ~$67 for Service Bus Premium)
  - ⚠️ **Service Bus Premium is expensive** (~$677/month) - only enable if fully private delivery is required

**Delivery Modes**:
- **Webhook** (default): Event Grid → .NET Function (public endpoint with IP restrictions)
- **Service Bus** (optional): Event Grid → Service Bus → .NET Function (fully private via VNET peering)

**Key Takeaways**:
1. Always complete Phase 1 fully before starting Phase 2 to avoid cross-subscription peering issues
2. Both webhook and Service Bus functions coexist in code; switch modes by changing `enable_service_bus` variable
3. Service Bus mode provides fully private delivery with no public endpoints
