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

### What Gets Added

**Subscription 2**:
- Resource groups (dotnet-network, dotnet-function)
- VNET3 (10.2.0.0/16) - .NET Function VNET
- Cross-subscription VNET peering (VNET3 ↔ VNET2)
- .NET Function App with VNET integration
- Application Insights (separate instance)
- Storage Account
- Azure AD app registration (if auth enabled)

**Subscription 1 Updates**:
- Private DNS zone VNET link to VNET3
- Event Grid subscription for .NET function
- IAM role assignments for .NET function

### Configuration File

Use `terraform.phase2.tfvars`:

```hcl
subscription_id = "your-subscription-1-id"
subscription_id_2 = "your-subscription-2-id"
location = "swedencentral"  # Must match Phase 1
enable_dotnet_function = true  # Critical: must be true
enable_function_authentication = true
allowed_ip_addresses = []
```

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

```bash
# Ensure you're in terraform directory
cd terraform

# Review Phase 2 changes
terraform plan -var-file=terraform.phase2.tfvars

# Apply Phase 2 (adds Subscription 2 resources)
terraform apply -var-file=terraform.phase2.tfvars
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

### Expected Results

- ✅ 5 total resource groups (3 in Sub1, 2 in Sub2)
- ✅ 3 VNETs with full mesh peering
- ✅ Private DNS zone linked to all 3 VNETs
- ✅ Both functions respond to HTTP requests
- ✅ All VNET peerings show "Connected" state

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

## Function Code Deployment

After both phases complete successfully, deploy function code:

```bash
# From project root
./scripts/deploy-function.sh
```

This script automatically:
1. Deploys Python function code
2. Deploys .NET function code (if enabled)
3. Creates Event Grid subscriptions for both functions
4. Verifies function registration

## Testing

Run comprehensive connectivity tests:

```bash
./scripts/test-connectivity.sh
```

Tests include:
- Python → Event Grid → Python
- Python → Event Grid → .NET (if Phase 2 deployed)
- .NET → Event Grid → Python (if Phase 2 deployed)
- .NET → Event Grid → .NET (if Phase 2 deployed)
- VNET peering verification

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

## Summary

| Phase | Purpose | Time | Subscriptions |
|-------|---------|------|---------------|
| Phase 1 | Deploy core infrastructure | 10-15 min | Subscription 1 |
| Phase 2 | Add cross-subscription | 10-15 min | Subscription 1 + 2 |
| Deploy Code | Deploy functions | 5-10 min | Both |
| Testing | Verify connectivity | 5 min | Both |

**Total deployment time**: ~30-45 minutes

**Key Takeaway**: Always complete Phase 1 fully before starting Phase 2 to avoid cross-subscription peering issues.
