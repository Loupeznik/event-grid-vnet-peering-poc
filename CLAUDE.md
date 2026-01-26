# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Azure Event Grid VNET Peering Proof of Concept demonstrating secure private endpoint connectivity between Azure Functions and Event Grid across peered Virtual Networks. All traffic flows through Azure backbone without traversing public internet.

## Architecture

Two-VNET architecture (single subscription) or three-VNET architecture (cross-subscription):

**Single Subscription**:
- **VNET 1 (10.0.0.0/16)**: Python Function App with VNET integration
- **VNET 2 (10.1.0.0/16)**: Event Grid Topic with private endpoint
- **Authentication**: System-assigned managed identities (no credentials)
- **DNS**: Private DNS zone (privatelink.eventgrid.azure.net) linked to both VNETs
- **IaC**: Terraform with azurerm provider v4

**Cross-Subscription** (optional):
- **VNET 1 (10.0.0.0/16)**: Python Function (Subscription 1)
- **VNET 2 (10.1.0.0/16)**: Event Grid Topic with private endpoint (Subscription 1)
- **VNET 3 (10.2.0.0/16)**: .NET Function (Subscription 2)
- **Peering**: Bi-directional peering between all VNETs
- **DNS**: Private DNS zone linked to all three VNETs
- **IAM**: Cross-subscription role assignments for .NET function

## Technology Stack

- **Infrastructure**: Terraform 1.0+, Azure CLI, azurerm provider v4, azuread provider v3
- **Python Function**: Azure Functions v4, Python 3.11 runtime
- **C# Function**: .NET 10.0, Azure Functions v4 (isolated worker process)
- **Compute**: Basic B1 App Service Plan (Linux)
- **Security**: Entra ID authentication, IP restrictions, managed identities
- **Region**: North Europe

## Common Commands

### Infrastructure Management

**Phase 1: Single Subscription (Python only)**:
```bash
cd terraform
terraform init
terraform apply -var-file=terraform.phase1.tfvars
terraform destroy -var-file=terraform.phase1.tfvars
```

**Phase 2: Cross-Subscription (Python + .NET)**:
```bash
cd terraform
# After Phase 1 succeeds
terraform apply -var-file=terraform.phase2.tfvars
terraform destroy -var-file=terraform.phase2.tfvars
```

**Why Two Phases?**
- Cross-subscription VNET peering has known issues with azurerm provider v4.x
- Deploying in phases ensures all Subscription 1 resources exist before Subscription 2 references them
- See [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md) for details

### Function Deployment

Deploy Python function code:
```bash
./scripts/deploy-function.sh
```

This script:
1. Creates deployment package from `function/` directory
2. Deploys to Azure Function App via zip deployment
3. Creates Event Grid subscription for the consume_event function
4. Waits for function registration

### Testing

Test connectivity and VNET peering:
```bash
./scripts/test-connectivity.sh
```

Manually publish test event:
```bash
curl -X POST "https://<function-name>.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test message"}'
```

### .NET Function Development

The `EventGridPubSubFunction/` directory contains .NET implementation for cross-subscription scenarios:

**Build and test locally**:
```bash
cd EventGridPubSubFunction
dotnet restore
dotnet build
dotnet run
```

**Deploy to Azure** (automated):
```bash
./scripts/deploy-function.sh
```

**Deploy manually**:
```bash
cd EventGridPubSubFunction
dotnet publish -c Release -o bin/Release/publish
cd bin/Release/publish
zip -r ../../../deployment.zip .
az functionapp deployment source config-zip \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --name <dotnet-function-name> \
  --src ../../../deployment.zip
```

### Monitoring

View Application Insights logs:
```bash
az monitor app-insights query \
  --app <app-insights-name> \
  --analytics-query "traces | where timestamp > ago(1h) | where message contains 'consume_event'"
```

Check function logs:
```bash
az webapp log tail \
  --name <function-app-name> \
  --resource-group rg-eventgrid-vnet-poc-function
```

## Code Structure

### Terraform Modules (terraform/)

- `main.tf`: Provider configuration (azurerm, azuread, subscription2 alias), resource groups, random suffix
- `networking.tf`: VNETs, subnets, VNET peering (single and cross-subscription)
- `eventgrid.tf`: Event Grid topic, private endpoint
- `function.tf`: Python Function App with IP restrictions and Entra ID auth
- `function-dotnet.tf`: .NET Function infrastructure with security (optional, Subscription 2)
- `auth.tf`: Entra ID app registrations, Event Grid system topic, role assignments
- `iam-dotnet.tf`: Cross-subscription role assignments for .NET function (optional)
- `dns.tf`: Private DNS zone and VNET links (including VNET3 link)
- `iam.tf`: Role assignments for Python function managed identity
- `variables.tf`: Input variables (enable_dotnet_function, subscription_id_2, allowed_ip_addresses, enable_function_authentication)
- `outputs.tf`: All function names, Event Grid info, conditional .NET outputs, auth configuration

### Python Function (function/)

- `function_app.py`: Two functions using v4 programming model
  - `publish_event`: HTTP trigger that publishes to Event Grid via managed identity
  - `consume_event`: Event Grid trigger that logs received events
- `requirements.txt`: Python dependencies (azure-functions, azure-eventgrid, azure-identity)
- `host.json`: Function runtime configuration

### Deployment Scripts (scripts/)

- `deploy-function.sh`: Automated deployment for Python and optionally .NET functions
- `deploy-dotnet-function.sh`: Builds .NET function (called by main script)
- `test-connectivity.sh`: Validates infrastructure, VNET peering, private endpoint connectivity (both single and cross-subscription)
- `helpers/azure-context.sh`: Helper functions for managing multi-subscription context

## Key Implementation Details

### Private Endpoint Connectivity

Event Grid topic has public access disabled. All communication flows through:
1. Function App publishes via `DefaultAzureCredential` (managed identity)
2. DNS resolves Event Grid hostname to private IP (10.1.1.x)
3. Traffic routes through VNET peering to private endpoint in VNET 2
4. Event Grid delivers to Function via webhook (public endpoint with security layers)

### Security Configuration

**IP Restrictions** (Applied to both functions):
- Allow Event Grid service tag (`AzureEventGrid`)
- Allow Azure management services (`AzureCloud`)
- Allow custom IP addresses from `allowed_ip_addresses` variable
- Deny all other traffic

**Entra ID Authentication** (Optional, enabled by default):
- Azure AD app registrations for each function
- Event Grid system topic with managed identity
- Token-based webhook authentication
- Automatic token validation at function layer

**Configuration Variables**:
```hcl
allowed_ip_addresses = ["203.0.113.0/24", "198.51.100.42/32"]
enable_function_authentication = true
entra_tenant_id = ""  # Optional, uses current tenant if empty
```

### VNET Integration Requirements

Function App requires:
- `vnet_route_all_enabled = true` to route all traffic through VNET
- Subnet delegation to `Microsoft.Web/serverFarms`
- Basic or higher App Service Plan (Consumption plan doesn't support VNET integration)

### Managed Identity Setup

Function App uses system-assigned managed identity with:
- `EventGrid Data Sender` role on Event Grid topic for publishing
- No keys or connection strings stored

### Terraform State

Infrastructure creates 3 resource groups:
- `rg-eventgrid-vnet-poc-network`: VNET resources
- `rg-eventgrid-vnet-poc-eventgrid`: Event Grid topic and private endpoint
- `rg-eventgrid-vnet-poc-function`: Function App and dependencies

## Development Workflow

### Making Infrastructure Changes

1. Modify Terraform files
2. Run `terraform plan` to review changes
3. Run `terraform apply` after validation
4. Re-run `./scripts/deploy-function.sh` if Event Grid or Function resources changed

### Modifying Python Function Code

1. Edit `function/function_app.py`
2. Update `function/requirements.txt` if adding dependencies
3. Run `./scripts/deploy-function.sh` to deploy changes
4. Monitor logs in Application Insights

### Modifying .NET Function Code

1. Edit `EventGridPubSubFunction/EventGridFunctions.cs`
2. Update `EventGridPubSubFunction/*.csproj` if adding packages
3. Run `./scripts/deploy-function.sh` to deploy changes (builds and deploys both functions)
4. Monitor logs in Application Insights in Subscription 2

### Cross-Subscription Development

When working with cross-subscription setup:
1. Ensure `az login` has access to both subscriptions
2. Use `az account list` to verify subscription access
3. Deployment script automatically switches subscriptions
4. Monitor logs in both subscriptions' Application Insights
5. Check VNET peering status: `az network vnet peering list`

### Troubleshooting Private Endpoint Issues

Check DNS resolution from Function App context:
```bash
az functionapp config appsettings list \
  --name <function-name> \
  --resource-group rg-eventgrid-vnet-poc-function \
  --query "[?name=='EVENT_GRID_TOPIC_ENDPOINT'].value"
```

Verify VNET integration:
```bash
az functionapp vnet-integration list \
  --name <function-name> \
  --resource-group rg-eventgrid-vnet-poc-function
```

Check VNET peering status (single subscription):
```bash
az network vnet peering list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-function-*
```

Check cross-subscription VNET peering:
```bash
# Peering in Subscription 1
az network vnet peering show \
  --resource-group rg-eventgrid-vnet-poc-network \
  --vnet-name vnet-eventgrid-* \
  --name peer-eventgrid-to-dotnet

# Peering in Subscription 2
az account set --subscription <subscription-2-id>
az network vnet peering show \
  --resource-group rg-eventgrid-vnet-poc-dotnet-network \
  --vnet-name vnet-dotnet-* \
  --name peer-dotnet-to-eventgrid
```

Check role assignments for cross-subscription access:
```bash
az role assignment list \
  --scope /subscriptions/<sub-1>/resourceGroups/rg-eventgrid-vnet-poc-eventgrid/providers/Microsoft.EventGrid/topics/<topic-name> \
  --query "[?principalType=='ServicePrincipal']"
```

## Cost Management

3-day PoC costs approximately $3-5 USD (North Europe):
- App Service Plan B1: $1.30
- Private Endpoint: $0.74
- Other services: <$1.00

Clean up immediately after testing with `terraform destroy` to avoid ongoing charges.

## Important Notes

- Event Grid subscription must target function named exactly `consume_event` (Python) or `ConsumeEvent` (.NET)
- Function deployment can take 1-2 minutes for Azure to recognize new functions
- Role assignments may take 5-10 minutes to propagate, especially cross-subscription
- Private DNS resolution requires VNET integration to be fully configured
- Cross-subscription deployments require Network Contributor role in both subscriptions
- The `EventGridPubSubFunction/` directory contains .NET implementation for cross-subscription PoC
- Event Grid delivers events via webhook (public endpoint) even with private endpoint configured
- Publishing to Event Grid is fully private via VNET peering and private endpoint
- IP restrictions protect webhook endpoints (Event Grid service + custom IPs only)
- Entra ID authentication is enabled by default for additional security
- See [docs/CROSS-SUBSCRIPTION.md](docs/CROSS-SUBSCRIPTION.md) for detailed cross-subscription architecture
- See [docs/SECURITY.md](docs/SECURITY.md) for security configuration and best practices
