# Azure Event Grid VNET Peering PoC

Proof of Concept demonstrating Azure Event Grid connectivity through private endpoints across peered Virtual Networks.

## Overview

This PoC validates that Azure Functions can securely communicate with Event Grid through private endpoints across VNET-peered networks, ensuring all traffic remains within the Azure backbone without traversing the public internet.

## Architecture

- **VNET 1**: Azure Function App with VNET integration
- **VNET 2**: Event Grid Topic with private endpoint
- **Connectivity**: Bi-directional VNET peering + Private DNS
- **Security**: Managed identities, no public access

## Key Features

- Private endpoint connectivity for Event Grid
- VNET peering between Function and Event Grid networks
- System-assigned managed identities (no stored credentials)
- Private DNS resolution
- Complete network isolation
- Infrastructure as Code with Terraform (azurerm v4)
- Python 3.11 Azure Functions v4
- **Optional**: Cross-subscription .NET Function deployment

## Project Structure

```
.
├── terraform/                   # Infrastructure as Code
│   ├── main.tf                  # Provider and resource groups
│   ├── networking.tf            # VNETs, subnets, peering
│   ├── eventgrid.tf             # Event Grid and private endpoint
│   ├── function.tf              # Python Function App
│   ├── function-dotnet.tf       # .NET Function App (optional)
│   ├── iam-dotnet.tf            # .NET Function IAM (optional)
│   ├── dns.tf                   # Private DNS configuration
│   ├── iam.tf                   # Role assignments
│   ├── variables.tf             # Input variables
│   ├── outputs.tf               # Output values
│   └── terraform.tfvars         # Configuration values
├── function/                    # Python Azure Function
│   ├── function_app.py          # HTTP and Event Grid triggers
│   ├── requirements.txt         # Python dependencies
│   └── host.json                # Function host configuration
├── EventGridPubSubFunction/     # .NET Azure Function (optional)
│   ├── EventGridFunctions.cs    # HTTP and Event Grid triggers
│   ├── Program.cs               # Function host setup
│   ├── *.csproj                 # Project file
│   └── local.settings.json      # Local configuration
├── scripts/                     # Deployment and testing
│   ├── helpers/
│   │   └── azure-context.sh     # Multi-subscription helpers
│   ├── deploy-function.sh       # Deploy both functions
│   ├── deploy-dotnet-function.sh # Build .NET function
│   └── test-connectivity.sh     # Validate connectivity
└── docs/                        # Documentation
    ├── CROSS-SUBSCRIPTION.md    # Cross-subscription guide
    ├── DEPLOYMENT.md            # Detailed deployment guide
    └── COSTS.md                 # Cost analysis

```

## Quick Start

### Prerequisites

- Azure CLI (authenticated)
- Terraform 1.0+
- bash shell
- **Optional**: .NET SDK 10.0+ (for cross-subscription .NET function)

### Deploy Infrastructure

#### Option 1: Single Subscription (Python Function Only)

**Phase 1: Deploy Python Function Infrastructure**:
```bash
cd terraform
terraform init
terraform apply -var-file=terraform.phase1.tfvars
```

This deploys:
- VNET 1 (10.0.0.0/16): Python Function
- VNET 2 (10.1.0.0/16): Event Grid with private endpoint
- Single subscription architecture

#### Option 2: Cross-Subscription (.NET + Event Hub)

**Prerequisites**:
- Access to both Azure subscriptions
- Network Contributor role in both subscriptions
- Subscription IDs configured in `terraform.phase2.tfvars`

**Phase 1: Deploy Base Infrastructure** (Subscription 1):
```bash
cd terraform
terraform init
terraform apply -var-file=terraform.phase1.tfvars
```

**Phase 2: Add Cross-Subscription Resources** (.NET Function in Subscription 2):
```bash
terraform apply -var-file=terraform.phase2.tfvars
```

This adds:
- VNET 3 (10.2.0.0/16): .NET Function in Subscription 2
- Cross-subscription VNET peering
- Event Hub for fully private communication (optional)
- Cross-subscription IAM roles

**Phase 3: Enable Event Hub** (Optional - Fully Private Communication):
```bash
terraform apply -var="enable_event_hub=true" -var-file=terraform.phase2.tfvars
```

**Why Phased?**: Cross-subscription VNET peering has known issues with azurerm provider v4.x when deployed in a single apply. Phased deployment ensures reliable resource creation.

See [docs/CROSS-SUBSCRIPTION.md](docs/CROSS-SUBSCRIPTION.md) for detailed cross-subscription setup and [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md) for troubleshooting.

### Deploy Function

```bash
./scripts/deploy-function.sh
```

### Test Connectivity

#### Single Subscription Testing

```bash
./scripts/test-connectivity.sh
```

#### Cross-Subscription Testing

The test script automatically detects cross-subscription deployment and validates:
- VNET peering across subscriptions
- Private DNS resolution in both subscriptions
- Cross-subscription IAM roles
- Event Hub connectivity (if enabled)

```bash
./scripts/test-connectivity.sh
```

### Publish Test Events

#### Test Python Function (Subscription 1)

```bash
# Get Python function name from Terraform output
PYTHON_FUNCTION=$(cd terraform && terraform output -raw function_app_name)

# Publish event via Python function
curl -X POST "https://${PYTHON_FUNCTION}.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test from Python (Sub 1)"}'
```

#### Test .NET Function (Subscription 2) - Cross-Subscription

```bash
# Get .NET function name from Terraform output
DOTNET_FUNCTION=$(cd terraform && terraform output -raw dotnet_function_app_name)

# Publish event via .NET function (cross-subscription)
curl -X POST "https://${DOTNET_FUNCTION}.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test from .NET (Sub 2) - Cross-Subscription"}'
```

#### Test Event Hub Path (Fully Private)

```bash
# Publish via Python function → Event Grid → Event Hub → .NET Function
curl -X POST "https://${PYTHON_FUNCTION}.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"eventType": "test.eventhub", "message": "Fully private test via Event Hub"}'
```

### Verify Event Delivery

#### Check Python Function Logs (Subscription 1)

```bash
az webapp log tail \
  --name $(cd terraform && terraform output -raw function_app_name) \
  --resource-group $(cd terraform && terraform output -raw function_resource_group)
```

#### Check .NET Function Logs (Subscription 2)

```bash
# Switch to Subscription 2
az account set --subscription $(cd terraform && terraform output -raw subscription_id_2)

# Tail logs
az webapp log tail \
  --name $(cd terraform && terraform output -raw dotnet_function_app_name) \
  --resource-group $(cd terraform && terraform output -raw dotnet_resource_group)
```

#### Query Application Insights (Cross-Subscription Events)

```bash
# Query .NET function Application Insights for Event Hub events
az monitor app-insights query \
  --app $(cd terraform && terraform output -raw dotnet_app_insights_name) \
  --analytics-query "traces
    | where timestamp > ago(10m)
    | where message contains 'FULLY PRIVATE' or message contains 'Event Hub'
    | project timestamp, message, severityLevel
    | order by timestamp desc" \
  --subscription $(cd terraform && terraform output -raw subscription_id_2)
```

## Cross-Subscription Architecture

This PoC supports three deployment scenarios with increasing security levels:

### Phase 1: Single Subscription Webhook
- **Architecture**: Python Function → Event Grid (private endpoint) → Python Function (webhook)
- **Subscriptions**: Single subscription
- **Publishing**: Fully private via VNET peering
- **Delivery**: Public webhook (Azure backbone, mitigated by IP restrictions + Entra ID)

### Phase 2: Cross-Subscription Webhook
- **Architecture**: .NET Function (Sub 2) → Event Grid (Sub 1) → .NET Function (Sub 2, webhook)
- **Subscriptions**: Two subscriptions
- **Publishing**: Fully private via cross-subscription VNET peering
- **Delivery**: Public webhook (Azure backbone, mitigated by IP restrictions + Entra ID)
- **Additional**: Cross-subscription IAM, VNET peering between Sub 1 and Sub 2

### Phase 3: Cross-Subscription Event Hub (Fully Private)
- **Architecture**: .NET Function (Sub 2) → Event Grid (Sub 1) → Event Hub (Sub 1) → .NET Function (Sub 2)
- **Subscriptions**: Two subscriptions
- **Publishing**: Fully private via VNET peering
- **Delivery**: Fully private via Event Hub and VNET peering
- **Result**: 100% private end-to-end communication (no public internet)

### Cross-Subscription Configuration

**Edit `terraform/terraform.phase2.tfvars`**:

```hcl
# Enable cross-subscription deployment
enable_dotnet_function = true
subscription_id_2 = "your-subscription-2-id"

# Optional: Enable Event Hub for fully private delivery
enable_event_hub = false  # Set to true for Phase 3

# Security configuration
allowed_ip_addresses = ["your-public-ip/32"]
enable_function_authentication = true
```

### Cross-Subscription Validation Checklist

After deployment, verify:

1. **VNET Peering Status**:
   ```bash
   # Check peering in Subscription 1
   az network vnet peering list \
     --resource-group $(cd terraform && terraform output -raw network_resource_group) \
     --vnet-name $(cd terraform && terraform output -raw eventgrid_vnet_name) \
     --query "[?name=='peer-eventgrid-to-dotnet'].{Name:name, Status:peeringState}" -o table

   # Check peering in Subscription 2
   az account set --subscription $(cd terraform && terraform output -raw subscription_id_2)
   az network vnet peering list \
     --resource-group $(cd terraform && terraform output -raw dotnet_network_resource_group) \
     --vnet-name $(cd terraform && terraform output -raw dotnet_vnet_name) \
     --query "[?name=='peer-dotnet-to-eventgrid'].{Name:name, Status:peeringState}" -o table
   ```

2. **Private DNS Resolution** (both subscriptions should resolve to private IP):
   ```bash
   # From .NET function, should resolve Event Grid to 10.1.1.4
   az functionapp config appsettings list \
     --name $(cd terraform && terraform output -raw dotnet_function_app_name) \
     --resource-group $(cd terraform && terraform output -raw dotnet_resource_group) \
     --subscription $(cd terraform && terraform output -raw subscription_id_2) \
     --query "[?name=='EVENT_GRID_TOPIC_ENDPOINT'].value" -o tsv
   ```

3. **IAM Roles** (cross-subscription):
   ```bash
   # .NET function should have Event Grid Data Sender role in Sub 1
   az role assignment list \
     --scope $(cd terraform && terraform output -raw eventgrid_topic_id) \
     --query "[?principalType=='ServicePrincipal'].{Role:roleDefinitionName, Principal:principalId}" -o table
   ```

4. **Event Delivery**:
   - Publish event from .NET function (Sub 2)
   - Event routes through Event Grid private endpoint in Sub 1
   - Event Grid delivers to .NET function webhook (Sub 2) or Event Hub (Sub 1)
   - Check Application Insights logs in Sub 2 for successful delivery

### Cross-Subscription Cleanup

```bash
cd terraform

# Destroy Phase 2 resources first
terraform destroy -var-file=terraform.phase2.tfvars

# Then destroy Phase 1 resources
terraform destroy -var-file=terraform.phase1.tfvars
```

## Cost Estimate

### Single Subscription (Phase 1)
**3-Day PoC: $3-5 USD**
- App Service Plan (Basic B1): $1.30
- Private Endpoint: $0.74
- Storage: $0.04
- VNET Peering: $0.02
- Other services: Free tier

### Cross-Subscription Webhook (Phase 2)
**3-Day PoC: $6-8 USD**
- Additional App Service Plan (Sub 2): $1.30
- Additional Storage: $0.04
- Cross-subscription VNET peering: $0.02
- Additional Private Endpoint: $0.74
- Total: ~$6-8 USD

### Cross-Subscription with Event Hub (Phase 3)
**3-Day PoC: $12-15 USD**
- Event Hub Standard (prorated 3 days): ~$5.50
- Event Hub Private Endpoint: $0.74
- Base infrastructure (Phase 2): $6-8
- Total: ~$12-15 USD

**Monthly Costs** (if running continuously):
- Single Subscription: ~$44/month
- Cross-Subscription Webhook: ~$88/month
- Cross-Subscription + Event Hub: ~$99/month

See [docs/COSTS.md](docs/COSTS.md) and [docs/POC-SUMMARY.md](docs/POC-SUMMARY.md) for detailed breakdown.

## Documentation

- **[Known Issues](docs/KNOWN-ISSUES.md)**: Common problems and solutions (READ THIS FIRST)
- **[Security Guide](docs/SECURITY.md)**: IP restrictions and Entra ID authentication configuration
- **[Cross-Subscription Guide](docs/CROSS-SUBSCRIPTION.md)**: Deploy .NET function in second subscription
- **[Deployment Guide](docs/DEPLOYMENT.md)**: Step-by-step deployment instructions
- **[Cost Analysis](docs/COSTS.md)**: Detailed cost breakdown and optimization

## Validation

The PoC proves VNET peering + private endpoint connectivity by:

1. Function App publishes events via HTTP trigger
2. Events route through private endpoint in peered VNET
3. Event Grid delivers to Function's Event Grid trigger
4. All traffic stays within Azure private network
5. Logs confirm private endpoint usage

## Cleanup

Remove all resources to avoid costs:

```bash
cd terraform
terraform destroy
```

## Key Components

### Infrastructure

- 3 Resource Groups (network, eventgrid, function)
- 2 VNETs with bi-directional peering
- Event Grid Topic with public access disabled
- Private endpoint for Event Grid
- Private DNS zone with VNET links
- Basic B1 App Service Plan (Linux)
- Azure Function App with VNET integration
- Application Insights for monitoring

### Application

- **HTTP Trigger**: Publishes events to Event Grid
- **Event Grid Trigger**: Consumes events from Event Grid
- Managed identity authentication
- Python 3.11 runtime

## Security Features

- No public access to Event Grid
- All traffic through Azure backbone
- System-assigned managed identities
- No stored credentials or keys
- Private DNS prevents DNS hijacking
- VNET isolation
- **IP restrictions** limiting access to Event Grid service + approved IPs
- **Entra ID authentication** for webhook endpoints
- **Event Grid managed identity** authentication to functions

See [docs/SECURITY.md](docs/SECURITY.md) for detailed security configuration.

## Monitoring

View logs in Application Insights:

```kusto
traces
| where timestamp > ago(1h)
| where message contains "Successfully received event"
| order by timestamp desc
```

## Troubleshooting

Common issues and solutions in [docs/DEPLOYMENT.md#troubleshooting](docs/DEPLOYMENT.md#troubleshooting)

## Region

All resources deployed to a single region.

## License

MIT

## Support

For issues or questions, refer to the detailed documentation in the `docs/` directory.
