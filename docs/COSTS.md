# Azure Event Grid VNET Peering PoC - Cost Analysis

## Cost Estimation for 3-Day PoC in North Europe

**Total Estimated Cost: $3-5 USD**

This document provides a detailed breakdown of costs for running this PoC infrastructure for 3 days in the North Europe region.

## Detailed Cost Breakdown

### 1. Azure Functions (Basic B1 App Service Plan)

**Pricing Model**: Pay-as-you-go hourly rate

| Component | Unit Price | Usage (3 days) | Total Cost |
|-----------|------------|----------------|------------|
| Basic B1 Instance | $0.018/hour | 72 hours | $1.30 |
| Execution Time | Included | N/A | $0.00 |

**Details**:
- 1 instance of Basic B1 (1 core, 1.75 GB RAM)
- Sufficient for low-volume PoC testing
- Includes 1M executions/month
- No additional execution charges expected

**Cost: $1.30**

### 2. Event Grid

**Pricing Model**: Operations-based

| Component | Unit Price | Usage (3 days) | Total Cost |
|-----------|------------|----------------|------------|
| Operations (first 100K) | Free | <100K operations | $0.00 |
| Beyond 100K ops | $0.50/million | 0 operations | $0.00 |

**Details**:
- First 100,000 operations per month are free
- PoC expected to generate <1,000 operations
- No charges expected for Event Grid operations

**Cost: $0.00**

### 3. Storage Account (General Purpose v2, LRS)

**Pricing Model**: Capacity + transactions

| Component | Unit Price | Usage (3 days) | Total Cost |
|-----------|------------|----------------|------------|
| LRS Storage | $0.0184/GB/month | <1 GB | $0.002 |
| Transactions | $0.0036/10K | <100K transactions | $0.036 |
| Bandwidth | Included | Intra-region | $0.00 |

**Details**:
- Used for Function App state and metadata
- Minimal storage (<100 MB expected)
- Low transaction volume
- Intra-region data transfer is free

**Cost: $0.04**

### 4. Private Endpoint

**Pricing Model**: Per endpoint per hour + data processing

| Component | Unit Price | Usage (3 days) | Total Cost |
|-----------|------------|----------------|------------|
| Endpoint (per hour) | $0.01/hour | 72 hours | $0.72 |
| Data Processed (inbound) | $0.01/GB | <1 GB | $0.01 |
| Data Processed (outbound) | $0.01/GB | <1 GB | $0.01 |

**Details**:
- 1 private endpoint for Event Grid topic
- Minimal data transfer (<100 MB expected)
- Charged per hour endpoint is provisioned

**Cost: $0.74**

### 5. Virtual Network Peering

**Pricing Model**: Data transfer based

| Component | Unit Price | Usage (3 days) | Total Cost |
|-----------|------------|----------------|------------|
| Intra-region ingress | $0.01/GB | <1 GB | $0.01 |
| Intra-region egress | $0.01/GB | <1 GB | $0.01 |

**Details**:
- Regional VNET peering within North Europe
- Minimal data transfer for PoC
- Charged per GB transferred across peering

**Cost: $0.02**

### 6. Application Insights

**Pricing Model**: Data ingestion volume

| Component | Unit Price | Usage (3 days) | Total Cost |
|-----------|------------|----------------|------------|
| Data Ingestion (first 5GB) | Free | <1 GB | $0.00 |
| Beyond 5GB | $2.30/GB | 0 GB | $0.00 |

**Details**:
- First 5 GB per month included
- PoC expected to generate <100 MB of telemetry
- 90-day retention included

**Cost: $0.00**

### 7. Virtual Networks and Subnets

**Pricing Model**: No charge

| Component | Unit Price | Usage (3 days) | Total Cost |
|-----------|------------|----------------|------------|
| Virtual Networks | Free | 2 VNETs | $0.00 |
| Subnets | Free | 2 subnets | $0.00 |
| NSGs | Free | As needed | $0.00 |

**Details**:
- No charges for VNET or subnet provisioning
- Only charged for data transfer (covered above)

**Cost: $0.00**

### 8. Private DNS Zone

**Pricing Model**: Per zone + queries

| Component | Unit Price | Usage (3 days) | Total Cost |
|-----------|------------|----------------|------------|
| Hosted DNS Zone | $0.50/zone/month | 3 days | $0.05 |
| DNS Queries (first 1B) | $0.40/million | <1K queries | $0.00 |

**Details**:
- 1 private DNS zone (privatelink.eventgrid.azure.net)
- Prorated for 3 days
- Minimal query volume

**Cost: $0.05**

### 9. Bandwidth and Data Transfer

**Pricing Model**: Outbound data transfer

| Component | Unit Price | Usage (3 days) | Total Cost |
|-----------|------------|----------------|------------|
| Intra-region transfer | Free | All traffic | $0.00 |
| Outbound Internet | $0.087/GB | 0 GB | $0.00 |

**Details**:
- All traffic stays within North Europe region
- No public internet egress
- Intra-region transfers are free

**Cost: $0.00**

## Summary Table

| Service | 3-Day Cost | Notes |
|---------|------------|-------|
| App Service Plan (B1) | $1.30 | Largest cost component |
| Private Endpoint | $0.74 | Per-hour + data processing |
| Storage Account | $0.04 | Minimal usage |
| VNET Peering | $0.02 | Intra-region only |
| Private DNS Zone | $0.05 | Prorated |
| Event Grid | $0.00 | Within free tier |
| Application Insights | $0.00 | Within free tier |
| VNETs and Subnets | $0.00 | No charge |
| Bandwidth | $0.00 | Intra-region free |
| **Total** | **$2.15** | **Conservative estimate** |

**With buffer for variations: $3-5 USD**

## Cost Optimization Recommendations

### For This PoC

1. **Use Consumption Plan**: If VNET integration wasn't required, Consumption plan would be nearly free
2. **Cleanup Immediately**: Delete resources as soon as testing is complete
3. **Automate Teardown**: Use `terraform destroy` to ensure all resources are removed

### For Production

1. **Right-size App Service Plan**: Start with Basic B1, scale up only if needed
2. **Use Consumption Plan**: For event-driven workloads without VNET requirements
3. **Reserved Instances**: For App Service Plans, consider 1-3 year reservations (up to 63% savings)
4. **Monitor Costs**: Set up cost alerts and budgets in Azure Cost Management
5. **Clean Up Unused Resources**: Remove unused Event Grid subscriptions, endpoints

## Cost Comparison: Alternative Architectures

### Consumption Plan (Without VNET Integration)

| Service | 3-Day Cost |
|---------|------------|
| Consumption Plan | $0.00* |
| Event Grid | $0.00 |
| Storage | $0.04 |
| Application Insights | $0.00 |
| **Total** | **$0.04** |

*Within free tier (1M executions/month)

**Note**: Cannot use private endpoints without VNET integration

### Premium Plan EP1 (Original Proposal)

| Service | 3-Day Cost |
|---------|------------|
| Premium EP1 | $13.68 |
| Private Endpoint | $0.74 |
| Storage | $0.04 |
| VNET Peering | $0.02 |
| Other Services | $0.05 |
| **Total** | **$14.53** |

**Savings with Basic B1: 85% cost reduction**

## Extended Duration Estimates

### 1 Week (7 days)

| Component | Weekly Cost |
|-----------|-------------|
| App Service Plan B1 | $3.02 |
| Private Endpoint | $1.68 |
| Other Services | $0.15 |
| **Total** | **$4.85** |

### 1 Month (30 days)

| Component | Monthly Cost |
|-----------|--------------|
| App Service Plan B1 | $12.96 |
| Private Endpoint | $7.20 |
| Other Services | $0.60 |
| **Total** | **$20.76** |

## Cost Monitoring

### Azure Cost Management Setup

1. Navigate to Azure Portal → Cost Management + Billing
2. Create a budget:
   ```
   Name: EventGrid-VNET-PoC
   Amount: $5.00
   Period: Monthly
   Alert at: 80% ($4.00)
   ```

3. Set up cost alerts:
   ```bash
   az consumption budget create \
     --budget-name "EventGrid-VNET-PoC" \
     --amount 5 \
     --time-grain Monthly \
     --start-date $(date +%Y-%m-01) \
     --end-date $(date -d "+1 month" +%Y-%m-01)
   ```

### Query Actual Costs

After deployment, check actual costs:

```bash
az consumption usage list \
  --start-date $(date -d "3 days ago" +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --query "[?contains(instanceName, 'eventgrid') || contains(instanceName, 'func')].{Resource:instanceName, Cost:pretaxCost}" \
  -o table
```

## Billing Tags

All resources are tagged for cost tracking:

```hcl
tags = {
  Environment = "PoC"
  Project     = "EventGrid-VNET-Peering"
  ManagedBy   = "Terraform"
}
```

Filter costs by tags in Azure Cost Management:
- Tag: `Project = EventGrid-VNET-Peering`

## Important Notes

1. **Prorated Charges**: Most services are charged hourly and prorated
2. **Regional Pricing**: Costs are specific to North Europe region
3. **Currency**: All prices in USD
4. **Pricing Date**: Based on January 2025 pricing
5. **Tax Excluded**: Prices exclude applicable taxes
6. **Free Tiers**: Several services have free tier allowances

## Cost Cleanup Verification

After running `terraform destroy`, verify no resources remain:

```bash
az group list --query "[?tags.Project=='EventGrid-VNET-Peering'].name" -o table
```

Expected output: (empty)

Check for any remaining costs:
```bash
az consumption usage list \
  --start-date $(date +%Y-%m-01) \
  --end-date $(date +%Y-%m-%d) \
  --query "[?contains(instanceName, 'eventgrid') || contains(instanceName, 'func')]" \
  -o table
```

## References

- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
- [Event Grid Pricing](https://azure.microsoft.com/pricing/details/event-grid/)
- [Azure Functions Pricing](https://azure.microsoft.com/pricing/details/functions/)
- [Private Link Pricing](https://azure.microsoft.com/pricing/details/private-link/)
- [Azure Cost Management](https://azure.microsoft.com/services/cost-management/)
