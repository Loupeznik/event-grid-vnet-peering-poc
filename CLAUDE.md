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

**Phase 3: Enable Event Hub (Fully Private)**:
```bash
cd terraform
# After Phase 2 succeeds
terraform apply -var="enable_event_hub=true" -var-file=terraform.phase2.tfvars
```

**Why Two Phases?**
- Cross-subscription VNET peering has known issues with azurerm provider v4.x
- Deploying in phases ensures all Subscription 1 resources exist before Subscription 2 references them
- See [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md) for details

**Cross-Subscription Prerequisites**:
- Access to both subscriptions (`az account list`)
- Network Contributor role in both subscriptions
- Update `terraform/terraform.phase2.tfvars`:
  ```hcl
  enable_dotnet_function = true
  subscription_id_2 = "your-subscription-2-id"
  enable_event_hub = false  # Set true for fully private
  ```

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

Test connectivity and VNET peering (auto-detects single/cross-subscription):
```bash
./scripts/test-connectivity.sh
```

**Single Subscription - Python Function**:
```bash
# Get function name from Terraform
PYTHON_FUNCTION=$(cd terraform && terraform output -raw function_app_name)

# Publish test event
curl -X POST "https://${PYTHON_FUNCTION}.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test from Python (Sub 1)"}'
```

**Cross-Subscription - .NET Function** (Phase 2):
```bash
# Get .NET function name from Terraform
DOTNET_FUNCTION=$(cd terraform && terraform output -raw dotnet_function_app_name)

# Publish event from Subscription 2 → Event Grid (Sub 1) → .NET Function (Sub 2)
curl -X POST "https://${DOTNET_FUNCTION}.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Cross-subscription test from .NET"}'

# Check logs in Subscription 2
az account set --subscription $(cd terraform && terraform output -raw subscription_id_2)
az webapp log tail \
  --name ${DOTNET_FUNCTION} \
  --resource-group $(cd terraform && terraform output -raw dotnet_resource_group)
```

**Fully Private Event Hub Path** (Phase 3):
```bash
# Publish via Python → Event Grid → Event Hub → .NET (all private)
curl -X POST "https://${PYTHON_FUNCTION}.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"eventType": "test.eventhub", "message": "Fully private via Event Hub"}'

# Verify in Application Insights (Subscription 2)
az monitor app-insights query \
  --app $(cd terraform && terraform output -raw dotnet_app_insights_name) \
  --analytics-query "traces | where timestamp > ago(10m) | where message contains 'FULLY PRIVATE'" \
  --subscription $(cd terraform && terraform output -raw subscription_id_2)
```

**Cross-Subscription Validation**:
```bash
# 1. Verify VNET peering status (both subscriptions)
az network vnet peering list \
  --resource-group $(cd terraform && terraform output -raw network_resource_group) \
  --vnet-name $(cd terraform && terraform output -raw eventgrid_vnet_name) \
  --query "[?name=='peer-eventgrid-to-dotnet'].{Name:name, Status:peeringState}"

az account set --subscription $(cd terraform && terraform output -raw subscription_id_2)
az network vnet peering list \
  --resource-group $(cd terraform && terraform output -raw dotnet_network_resource_group) \
  --vnet-name $(cd terraform && terraform output -raw dotnet_vnet_name) \
  --query "[?name=='peer-dotnet-to-eventgrid'].{Name:name, Status:peeringState}"

# 2. Verify cross-subscription IAM roles
az role assignment list \
  --scope $(cd terraform && terraform output -raw eventgrid_topic_id) \
  --query "[?principalType=='ServicePrincipal'].{Role:roleDefinitionName, Principal:principalId}"

# 3. Verify private DNS resolution (should resolve to 10.1.1.x)
az functionapp config appsettings list \
  --name $(cd terraform && terraform output -raw dotnet_function_app_name) \
  --resource-group $(cd terraform && terraform output -raw dotnet_resource_group) \
  --query "[?name=='EVENT_GRID_TOPIC_ENDPOINT'].value"
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
- `eventhub.tf`: Event Hub namespace, hub, private endpoint (optional, for fully private delivery)
- `function.tf`: Python Function App with IP restrictions and Entra ID auth
- `function-dotnet.tf`: .NET Function infrastructure with security (optional, Subscription 2)
- `auth.tf`: Entra ID app registrations, Event Grid system topic, role assignments
- `iam-dotnet.tf`: Cross-subscription role assignments for .NET function (optional)
- `dns.tf`: Private DNS zone and VNET links (including VNET3 link)
- `iam.tf`: Role assignments for Python function managed identity
- `monitoring.tf`: Application Insights, Log Analytics, diagnostic settings for all resources
- `variables.tf`: Input variables (enable_dotnet_function, subscription_id_2, enable_event_hub, allowed_ip_addresses, enable_function_authentication)
- `outputs.tf`: All function names, Event Grid info, Event Hub info, conditional .NET outputs, auth configuration

### Python Function (function/)

- `function_app.py`: Two functions using v4 programming model
  - `publish_event`: HTTP trigger that publishes to Event Grid via managed identity
  - `consume_event`: Event Grid trigger that logs received events
- `requirements.txt`: Python dependencies (azure-functions, azure-eventgrid, azure-identity)
- `host.json`: Function runtime configuration

### .NET Function (EventGridPubSubFunction/)

- `EventGridFunctions.cs`: Three functions for cross-subscription scenarios
  - `PublishEvent`: HTTP trigger that publishes to Event Grid (Subscription 1) via managed identity
  - `ConsumeEvent`: Event Grid webhook trigger for push-based delivery (hybrid security)
  - `ConsumeEventFromEventHub`: Event Hub trigger for fully private pull-based delivery
- `Program.cs`: Function host configuration
- `*.csproj`: Project file with Azure Functions and Event Hub dependencies
- `local.settings.json`: Local development configuration

### Deployment Scripts (scripts/)

- `deploy-function.sh`: Automated deployment for Python and optionally .NET functions
- `deploy-dotnet-function.sh`: Builds .NET function (called by main script)
- `test-connectivity.sh`: Validates infrastructure, VNET peering, private endpoint connectivity (both single and cross-subscription)
- `helpers/azure-context.sh`: Helper functions for managing multi-subscription context

## Key Implementation Details

### Private Endpoint Connectivity

**Publishing Path** (Always Private):
1. Function App publishes via `DefaultAzureCredential` (managed identity)
2. DNS resolves Event Grid hostname to private IP (10.1.1.4)
3. Traffic routes through VNET peering to private endpoint in VNET 2
4. Event Grid receives event via private endpoint

**Delivery Path** (Two Options):

**Option 1: Webhook Delivery** (Hybrid - Public with Security):
- Event Grid delivers to Function via webhook
- Uses Azure backbone but public endpoint
- Security: IP restrictions (AzureEventGrid service tag) + Entra ID authentication

**Option 2: Event Hub Delivery** (Fully Private):
1. Event Grid delivers to Event Hub via private endpoint (10.1.1.5)
2. Traffic stays within Azure backbone (Subscription 1)
3. .NET Function pulls events from Event Hub via VNET peering (10.1.1.5)
4. 100% private connectivity end-to-end

Enable Event Hub: `terraform apply -var="enable_event_hub=true"`

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

**Cross-Subscription Workflow**:

1. **Deploy Infrastructure** (2 phases):
   ```bash
   # Phase 1: Base infrastructure in Subscription 1
   cd terraform
   terraform apply -var-file=terraform.phase1.tfvars

   # Phase 2: Add .NET function in Subscription 2
   terraform apply -var-file=terraform.phase2.tfvars

   # Optional Phase 3: Enable Event Hub for fully private
   terraform apply -var="enable_event_hub=true" -var-file=terraform.phase2.tfvars
   ```

2. **Deploy Functions** (automatic cross-subscription handling):
   ```bash
   ./scripts/deploy-function.sh
   ```
   This script:
   - Detects cross-subscription deployment
   - Deploys Python function to Subscription 1
   - Deploys .NET function to Subscription 2
   - Creates appropriate Event Grid subscriptions (webhook or Event Hub)

3. **Test Cross-Subscription Communication**:
   - Publish from .NET function (Sub 2)
   - Event routes through Event Grid (Sub 1)
   - Delivered back to .NET function via webhook or Event Hub

4. **Monitor Both Subscriptions**:
   ```bash
   # Subscription 1 - Event Grid metrics
   az monitor metrics list \
     --resource $(cd terraform && terraform output -raw eventgrid_topic_id) \
     --metric PublishSuccessCount

   # Subscription 2 - Function execution logs
   az account set --subscription $(cd terraform && terraform output -raw subscription_id_2)
   az monitor app-insights query \
     --app $(cd terraform && terraform output -raw dotnet_app_insights_name) \
     --analytics-query "requests | where timestamp > ago(1h) | summarize count() by name"
   ```

5. **Troubleshooting Cross-Subscription Issues**:
   - **Peering not connected**: Check NSG rules, verify peering in both directions
   - **DNS not resolving**: Verify private DNS zone links to VNET 3
   - **IAM errors**: Verify .NET function managed identity has roles in Subscription 1
   - **Event delivery failing**: Check Event Grid subscription status, verify endpoint accessible

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

**Single Subscription (Phase 1)**: ~$3-5 USD (3 days)
- App Service Plan B1: $1.30
- Private Endpoint: $0.74
- Other services: <$1.00

**Cross-Subscription Webhook (Phase 2)**: ~$6-8 USD (3 days)
- Additional App Service Plan (Sub 2): $1.30
- Additional Private Endpoint: $0.74
- Cross-subscription VNET peering: $0.02
- Base Phase 1 costs: $3-5

**Cross-Subscription + Event Hub (Phase 3)**: ~$12-15 USD (3 days)
- Event Hub Standard (3 days prorated): ~$5.50
- Event Hub Private Endpoint: $0.74
- Base Phase 2 costs: $6-8

**Monthly Costs** (if running continuously):
- Single Subscription: ~$44/month
- Cross-Subscription Webhook: ~$88/month
- Cross-Subscription + Event Hub: ~$99/month

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

**Deployment Phases**:
- **Phase 1 (Single Subscription)**: Python function only, single subscription, webhook delivery
- **Phase 2 (Cross-Subscription)**: Adds .NET function in Subscription 2, cross-subscription VNET peering, webhook delivery
- **Phase 3 (Fully Private)**: Adds Event Hub for 100% private delivery via pull-based consumption
- **When to use Event Hub**: Strict security requirements, compliance mandates, air-gapped architectures
- **When to use Webhook**: Cost-sensitive scenarios, public delivery acceptable with IP restrictions + Entra ID
