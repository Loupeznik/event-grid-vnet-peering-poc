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

**Phase 1: Single Subscription (Python only)**:
```bash
cd terraform
terraform init
terraform apply -var-file=terraform.phase1.tfvars
```

**Phase 2: Add Cross-Subscription (.NET)** (after Phase 1 succeeds):
```bash
cd terraform
terraform apply -var-file=terraform.phase2.tfvars
```

**Why Phased?**: Cross-subscription VNET peering has known issues with azurerm provider v4.x when deployed in a single apply. Phased deployment ensures reliable resource creation.

See [docs/CROSS-SUBSCRIPTION.md](docs/CROSS-SUBSCRIPTION.md) for detailed cross-subscription setup and [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md) for troubleshooting.

### Deploy Function

```bash
./scripts/deploy-function.sh
```

### Test Connectivity

```bash
./scripts/test-connectivity.sh
```

### Publish Test Event

```bash
curl -X POST "https://<function-name>.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello from PoC"}'
```

## Cost Estimate

**3-Day PoC in North Europe: $3-5 USD**

- App Service Plan (Basic B1): $1.30
- Private Endpoint: $0.74
- Storage: $0.04
- VNET Peering: $0.02
- Other services: Free tier

See [docs/COSTS.md](docs/COSTS.md) for detailed breakdown.

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

All resources deployed to **North Europe** region.

## License

MIT

## Support

For issues or questions, refer to the detailed documentation in the `docs/` directory.
