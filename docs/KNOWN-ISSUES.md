# Known Issues and Solutions

This document tracks known issues encountered during development and their solutions.

## Cross-Subscription VNET Peering Deployment Failure

### Issue Description

**Severity**: High
**Status**: Workaround Available
**Affected Versions**: azurerm provider v4.x

When deploying cross-subscription VNET peering in a single `terraform apply`, the deployment fails with multiple errors:

```
Error: Provider produced inconsistent result after apply

When applying changes to azurerm_virtual_network_peering.eventgrid_to_dotnet[0],
provider "provider["registry.terraform.io/hashicorp/azurerm"]" produced an
unexpected new value: Root object was present, but now absent.

This is a bug in the provider, which should be reported in the provider's own issue tracker.
```

Additional errors include:
- 404 errors for VNETs that were just created
- 404 errors for Private DNS zones
- "ParentResourceNotFound" for DNS zone VNET links
- Inconsistent state where resources appear created but are not found

### Root Cause

The issue occurs due to:

1. **Provider Bug**: The azurerm provider has a known bug with cross-subscription VNET peering where resources are created asynchronously across subscriptions, but Terraform doesn't wait properly for all resources to be fully provisioned before attempting dependent resources.

2. **Resource Ordering**: Cross-subscription VNET peering requires resources in Subscription 1 (source) to be fully created before resources in Subscription 2 can reference them. When deployed simultaneously, race conditions occur.

3. **DNS Zone Links**: Private DNS zone VNET links attempting to link to VNETs in Subscription 2 fail because the parent DNS zone or target VNET may not be fully provisioned yet.

### Error Pattern

Typical error sequence:
1. VNETs created successfully in both subscriptions
2. Subnets begin creation
3. Cross-subscription peering starts before subnets complete
4. Peering fails with "inconsistent result"
5. DNS zone links fail with "ParentResourceNotFound"
6. Subsequent resources fail with 404 errors for parents

### Solution: Phased Deployment

Deploy infrastructure in two phases to ensure proper resource ordering:

**Phase 1: Single Subscription (Subscription 1)**
- Deploy all Subscription 1 resources first
- Includes Python function, Event Grid, VNETs 1 & 2, peering between VNET1 and VNET2
- Use `terraform.phase1.tfvars`

**Phase 2: Add Cross-Subscription (Subscription 2)**
- After Phase 1 completes successfully
- Add Subscription 2 resources (.NET function, VNET3, cross-subscription peering)
- Use `terraform.phase2.tfvars`

### Implementation

#### Phase 1 Configuration (`terraform.phase1.tfvars`)

```hcl
# Phase 1: Deploy Subscription 1 resources only
subscription_id = "your-subscription-1-id"
location = "swedencentral"

# Disable cross-subscription
enable_dotnet_function = false

# Security settings
enable_function_authentication = true
allowed_ip_addresses = []
```

Deploy Phase 1:
```bash
cd terraform
terraform init
terraform apply -var-file=terraform.phase1.tfvars
```

#### Phase 2 Configuration (`terraform.phase2.tfvars`)

```hcl
# Phase 2: Add Subscription 2 resources
subscription_id = "your-subscription-1-id"
subscription_id_2 = "your-subscription-2-id"
location = "swedencentral"

# Enable cross-subscription
enable_dotnet_function = true

# Security settings
enable_function_authentication = true
allowed_ip_addresses = []
```

Deploy Phase 2:
```bash
cd terraform
terraform apply -var-file=terraform.phase2.tfvars
```

### Why This Works

1. **Phase 1** ensures all Subscription 1 resources are fully created and in a stable state
2. **Phase 2** can reliably reference Subscription 1 resources because they're already in Terraform state
3. Cross-subscription peering succeeds because both VNETs are fully provisioned
4. DNS zone links work because the parent DNS zone and all VNETs exist

### Code Changes

Added explicit `depends_on` blocks to ensure proper ordering:

```hcl
resource "azurerm_virtual_network_peering" "dotnet_to_eventgrid" {
  # ...
  depends_on = [
    azurerm_subnet.dotnet_function_subnet,
    azurerm_subnet.private_endpoint_subnet
  ]
}

resource "azurerm_virtual_network_peering" "eventgrid_to_dotnet" {
  # ...
  depends_on = [
    azurerm_virtual_network_peering.dotnet_to_eventgrid,
    azurerm_subnet.dotnet_function_subnet,
    azurerm_subnet.private_endpoint_subnet
  ]
}
```

### Alternative Solutions Considered

1. **Single Deployment with Longer Timeouts**: Not effective - the issue is resource ordering, not timing
2. **Targeted Apply**: `terraform apply -target=...` for each resource - Too manual and error-prone
3. **Separate Terraform Modules**: Would work but adds complexity for a PoC
4. **Same Subscription Deployment**: Works perfectly but defeats the purpose of cross-subscription demo

### Verification

After successful Phase 2 deployment, verify:

```bash
# Check VNET peering status in both subscriptions
az account set --subscription "subscription-1-id"
az network vnet peering list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-eventgrid-* \
  --query "[].{Name:name, State:peeringState}" -o table

az account set --subscription "subscription-2-id"
az network vnet peering list \
  --resource-group rg-eventgrid-vnet-poc-dotnet-network \
  --vnet-name vnet-dotnet-* \
  --query "[].{Name:name, State:peeringState}" -o table
```

All peerings should show `peeringState: "Connected"`.

### Related Issues

- Azure Provider Issue: https://github.com/hashicorp/terraform-provider-azurerm/issues (search for "cross-subscription peering")
- Similar reported in community forums with azurerm 3.x and 4.x

### Future Improvements

Once the provider bug is fixed:
- Can be deployed in single phase
- Remove phase separation documentation
- Keep `depends_on` blocks for safety

---

## Event Grid System Topic Authentication Error

### Issue Description

**Severity**: Medium
**Status**: Resolved
**Affected Resource**: `azurerm_eventgrid_system_topic`

Attempting to create Event Grid system topic for custom Event Grid topics fails:

```
Error: creating/updating System Topic: unexpected status 400 (400 Bad Request)
with error: InvalidRequest: System topic creation is not enabled for topic type
microsoft.eventgrid.topics
```

### Root Cause

**Event Grid System Topics** are only supported for **Azure resource events**, not custom Event Grid topics:

- ✅ Supported: Storage Account events, Resource Group events, Subscription events
- ❌ Not Supported: Custom Event Grid topics (which we're using)

System topics are used when you want to subscribe to events FROM Azure resources (e.g., "notify me when a blob is created"). Custom topics are for publishing your own events.

### Solution

**Do not create system topics for custom Event Grid topics.** Instead:

1. **Use standard webhook validation** (automatic with Event Grid subscriptions)
2. **Use IP restrictions** to limit access to Event Grid service IPs
3. **Use Entra ID authentication** for additional security (if needed)

### Implementation

Removed system topic resources from `auth.tf`:

```hcl
# Removed:
# resource "azurerm_eventgrid_system_topic" "main" { ... }
# resource "azurerm_role_assignment" "eventgrid_to_python_function" { ... }
# resource "azurerm_role_assignment" "eventgrid_to_dotnet_function" { ... }

# Keep: IP restrictions + Entra ID auth on Function Apps
```

### Authentication Flow (Corrected)

For custom Event Grid topics with webhook subscriptions:

```
1. Event Grid validates webhook endpoint during subscription creation
2. Function App IP restrictions allow Event Grid service tag
3. Function App Entra ID auth has excluded paths for webhooks:
   - /runtime/webhooks/eventgrid (Event Grid trigger)
   - /api/publish (manual testing)
4. Event Grid delivers events via HTTPS POST
5. Function App validates Event Grid signature (automatic)
```

**No managed identity needed** - Event Grid webhooks use different authentication:
- Webhook validation handshake during subscription creation
- Event signature validation on each event delivery
- IP-based restrictions for additional security

### Related Documentation

- [Event Grid webhook authentication](https://learn.microsoft.com/en-us/azure/event-grid/webhook-event-delivery)
- [Event Grid system topics](https://learn.microsoft.com/en-us/azure/event-grid/system-topics)
- Difference between system topics (Azure resource events) and custom topics (your events)

---

## Quota Limitations in New Subscriptions

### Issue Description

**Severity**: High (Blocks Deployment)
**Status**: Requires Manual Action
**Affected Service**: Azure App Service

New Azure subscriptions may have zero quota for Basic App Service Plans:

```
Error: creating App Service Plan: unexpected status 401 (401 Unauthorized)
with response: {"Code":"Unauthorized","Message":"Operation cannot be completed
without additional quota. Current Limit (Basic VMs): 0"}
```

### Root Cause

Azure subscriptions start with:
- **No quota** for some services in newer regions
- **Zero quota** for App Service in certain tiers/regions
- **Requires manual approval** to increase quota

### Solution

**Option 1: Request Quota Increase (Preferred for Production)**

Via Azure Portal:
1. Navigate to **Quotas** service
2. Filter: Provider = `Compute`, Region = `swedencentral` (or your region)
3. Find: "Basic App Service instances" or "App Service Plans"
4. Request increase to minimum 10
5. Wait 1-2 business days for approval

Via Azure CLI:
```bash
# Check current quota
az quota list \
  --scope "/subscriptions/{subscription-id}/providers/Microsoft.Web/locations/swedencentral"

# Request increase (if supported by CLI)
az quota update \
  --resource-name "BasicAVMs" \
  --scope "/subscriptions/{subscription-id}/providers/Microsoft.Web/locations/swedencentral" \
  --limit-object value=10
```

**Option 2: Use Different Region**

Try regions with existing quota:
- `westeurope`
- `northeurope`
- `eastus`
- `westus2`

Update `location` in `terraform.tfvars`

**Option 3: Use Different Subscription**

Use a subscription with existing App Service quota:
```hcl
subscription_id_2 = "subscription-with-quota"
```

**Option 4: Single Subscription Deployment (PoC)**

Deploy everything in Subscription 1:
```hcl
enable_dotnet_function = false
```

### Required Resource Providers

Before deploying to a new subscription, register these providers:

```bash
SUBSCRIPTION_ID="your-subscription-id"
az account set --subscription "$SUBSCRIPTION_ID"

# Register all required providers
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.EventGrid
az provider register --namespace Microsoft.Quota

# Verify registration (takes 2-15 minutes)
az provider list \
  --query "[?namespace=='Microsoft.Web'].{Provider:namespace, State:registrationState}" \
  -o table
```

### Verification

Check if App Service Plans can be created:

```bash
# List existing plans
az appservice plan list \
  --subscription "{subscription-id}" \
  --query "[?location=='swedencentral'].{Name:name, SKU:sku.name}" \
  -o table

# Test quota availability (will fail if no quota)
terraform plan -var-file=terraform.phase2.tfvars
```

---

## Summary

| Issue | Severity | Status | Solution |
|-------|----------|--------|----------|
| Cross-Subscription VNET Peering | High | Workaround | Phased deployment |
| System Topic for Custom Topics | Medium | Resolved | Use webhook validation |
| Quota Limitations | High | Manual Action | Request quota increase |

All issues have documented workarounds or solutions. The phased deployment approach is the recommended strategy for reliable cross-subscription deployments.
