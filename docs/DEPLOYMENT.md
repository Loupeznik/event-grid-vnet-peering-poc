# Azure Event Grid VNET Peering PoC - Deployment Guide

## Overview

This PoC demonstrates Azure Event Grid connectivity through private endpoints across peered Virtual Networks (VNETs). The setup includes:

- Two VNETs connected via VNET peering
- Event Grid Topic with private endpoint in VNET 2
- Azure Function App with VNET integration in VNET 1
- End-to-end event flow through private networking

## Architecture

```
VNET 1 (10.0.0.0/16) - Function VNET
├── Function Subnet (10.0.1.0/27)
│   └── Azure Function App (Basic B1 Plan)
│       └── System-assigned Managed Identity

VNET 2 (10.1.0.0/16) - Event Grid VNET
├── Private Endpoint Subnet (10.1.1.0/27)
│   └── Event Grid Private Endpoint
└── Event Grid Topic (Public access disabled)

VNET Peering: Bi-directional (VNET 1 ↔ VNET 2)

Private DNS Zone: privatelink.eventgrid.azure.net
├── Linked to VNET 1
└── Linked to VNET 2
```

## Prerequisites

### Required Software

- Azure CLI (version 2.50+)
- Terraform (version 1.0+)
- bash shell
- curl
- zip

### Azure Requirements

- Active Azure subscription
- Sufficient permissions to create resources
- Azure CLI authenticated: `az login`

### Verify Prerequisites

```bash
az --version
terraform --version
az account show
```

## Step-by-Step Deployment

### Step 1: Configure Terraform Variables

1. Navigate to the terraform directory:
   ```bash
   cd terraform
   ```

2. Get your Azure subscription ID:
   ```bash
   az account show --query id -o tsv
   ```

3. Edit `terraform.tfvars` and update the subscription ID:
   ```hcl
   subscription_id = "your-subscription-id-here"
   location        = "northeurope"
   ```

### Step 2: Initialize Terraform

```bash
terraform init
```

This will:
- Download the Azure provider (v4.x)
- Initialize the backend
- Prepare the working directory

### Step 3: Review Infrastructure Plan

```bash
terraform plan
```

Review the resources that will be created:
- 3 Resource Groups
- 2 VNETs with subnets
- VNET peering (bi-directional)
- Event Grid topic
- Private endpoint for Event Grid
- Private DNS zone with VNET links
- Storage account
- App Service Plan (Basic B1)
- Linux Function App
- Application Insights
- Role assignments

### Step 4: Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted. Deployment takes approximately 5-10 minutes.

Save the outputs displayed at the end:
```
function_app_name = "func-eventgrid-xxxxxx"
eventgrid_topic_name = "evgt-poc-xxxxxx"
eventgrid_private_endpoint_ip = "10.1.1.x"
```

### Step 5: Deploy Function Code

From the project root directory:

```bash
./scripts/deploy-function.sh
```

This script will:
1. Create a deployment package from the function code
2. Deploy the package to Azure Function App
3. Create an Event Grid subscription
4. Configure the event trigger

Expected output:
```
✅ Deployment package created
✅ Function code deployed
✅ Function app ready
✅ Event Grid subscription created
```

### Step 6: Validate Connectivity

Run the connectivity test script:

```bash
./scripts/test-connectivity.sh
```

This will:
1. Verify DNS resolution from Function App
2. Publish a test event via HTTP trigger
3. Check Event Grid trigger logs
4. Verify VNET peering status

Expected output:
```
✅ Infrastructure deployed successfully
✅ VNET peering configured and connected
✅ Private endpoint created for Event Grid
✅ Function App integrated with VNET
✅ Event published via HTTP trigger
```

## Testing the PoC

### Manual Event Publishing

Publish an event manually using curl:

```bash
FUNCTION_URL="https://func-eventgrid-xxxxxx.azurewebsites.net/api/publish"

curl -X POST "$FUNCTION_URL" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello from manual test"}'
```

Expected response:
```json
{
  "status": "success",
  "message": "Event published successfully",
  "endpoint": "https://evgt-poc-xxxxxx.northeurope-1.eventgrid.azure.net/api/events"
}
```

### Verify Event Reception

Check Application Insights logs in Azure Portal:

1. Navigate to Function App → Application Insights
2. Go to Logs
3. Run query:
   ```kusto
   traces
   | where timestamp > ago(10m)
   | where message contains "consume_event" or message contains "Successfully received event"
   | project timestamp, message
   | order by timestamp desc
   ```

Look for the message:
```
✅ Successfully received event via private endpoint - VNET peering connectivity confirmed!
```

### Verify Private Connectivity

Confirm traffic flows through private endpoint:

1. Check Event Grid endpoint resolution:
   ```bash
   az functionapp config appsettings list \
     --name func-eventgrid-xxxxxx \
     --resource-group rg-eventgrid-vnet-poc-function \
     --query "[?name=='EVENT_GRID_TOPIC_ENDPOINT'].value" -o tsv
   ```

2. Verify private IP is used (should match private endpoint IP from terraform outputs)

3. Check VNET integration:
   ```bash
   az functionapp vnet-integration list \
     --name func-eventgrid-xxxxxx \
     --resource-group rg-eventgrid-vnet-poc-function
   ```

## Troubleshooting

### Issue: Function deployment fails

**Symptoms**: Deployment script returns error during zip deployment

**Solution**:
1. Verify Function App is running: `az functionapp show --name <name> --resource-group <rg>`
2. Check deployment logs in Azure Portal
3. Ensure remote build is enabled in function app settings

### Issue: Events not being received

**Symptoms**: HTTP trigger returns success but Event Grid trigger doesn't fire

**Solution**:
1. Verify Event Grid subscription exists:
   ```bash
   az eventgrid event-subscription list \
     --source-resource-id <topic-resource-id>
   ```
2. Check subscription status is "Succeeded"
3. Verify endpoint validation succeeded
4. Check Function App logs for errors

### Issue: DNS resolution fails

**Symptoms**: Cannot resolve Event Grid hostname to private IP

**Solution**:
1. Verify private DNS zone is linked to Function VNET
2. Check VNET integration is enabled on Function App
3. Ensure `vnet_route_all_enabled = true` is set
4. Restart Function App

### Issue: Authentication failures

**Symptoms**: "Unauthorized" or "Forbidden" errors when publishing events

**Solution**:
1. Verify managed identity is enabled on Function App
2. Check role assignments:
   ```bash
   az role assignment list \
     --assignee <function-principal-id> \
     --scope <eventgrid-topic-id>
   ```
3. Ensure "EventGrid Data Sender" role is assigned
4. Wait 5-10 minutes for role propagation

## Monitoring and Observability

### Application Insights Queries

**Recent function invocations**:
```kusto
requests
| where timestamp > ago(1h)
| project timestamp, name, success, resultCode, duration
| order by timestamp desc
```

**Event Grid trigger executions**:
```kusto
traces
| where timestamp > ago(1h)
| where operation_Name == "consume_event"
| project timestamp, message, severityLevel
| order by timestamp desc
```

**Errors and exceptions**:
```kusto
exceptions
| where timestamp > ago(1h)
| project timestamp, type, outerMessage, innermostMessage
| order by timestamp desc
```

### Metrics to Monitor

- Function execution count
- Function execution duration
- Event Grid publish operations
- Event Grid delivery success rate
- Private endpoint data transfer

## Cleanup

To remove all resources and avoid ongoing costs:

```bash
cd terraform
terraform destroy
```

Type `yes` when prompted. This will delete:
- All created resources
- Resource groups
- VNET peering
- Private endpoints
- Function App and associated resources

Alternatively, delete resource groups manually:
```bash
az group delete --name rg-eventgrid-vnet-poc-network --yes --no-wait
az group delete --name rg-eventgrid-vnet-poc-eventgrid --yes --no-wait
az group delete --name rg-eventgrid-vnet-poc-function --yes --no-wait
```

## Security Considerations

1. **Network Isolation**: Event Grid topic has public access disabled
2. **Private Connectivity**: All traffic flows through Azure backbone
3. **Managed Identity**: No stored credentials, Azure AD authentication
4. **DNS Security**: Private DNS zones prevent DNS hijacking
5. **VNET Integration**: Function App routes all traffic through VNET

## Best Practices Implemented

- Separate resource groups for logical separation
- Tagging for resource management and cost tracking
- System-assigned managed identities
- Application Insights for monitoring
- Infrastructure as Code with Terraform
- Automated deployment scripts
- Comprehensive logging

## Next Steps

After validating the PoC:

1. Review Application Insights metrics
2. Test with higher event volumes
3. Measure latency and throughput
4. Document findings
5. Clean up resources to avoid costs

## Support and Resources

- [Azure Event Grid Documentation](https://learn.microsoft.com/azure/event-grid/)
- [Azure Functions VNET Integration](https://learn.microsoft.com/azure/azure-functions/functions-networking-options)
- [Azure Private Endpoints](https://learn.microsoft.com/azure/private-link/private-endpoint-overview)
- [Terraform Azure Provider v4](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
