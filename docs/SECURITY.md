# Security Configuration Guide

This document details the security features implemented in the Event Grid VNET Peering PoC, including IP restrictions and Entra ID authentication.

## Table of Contents

- [Overview](#overview)
- [Security Layers](#security-layers)
- [IP Restrictions Configuration](#ip-restrictions-configuration)
- [Entra ID Authentication](#entra-id-authentication)
- [Event Grid Authentication](#event-grid-authentication)
- [Configuration Examples](#configuration-examples)
- [Testing Authentication](#testing-authentication)
- [Troubleshooting](#troubleshooting)

## Overview

The security implementation provides multiple layers of defense:

1. **Network Layer**: IP restrictions limiting access to Event Grid and approved IPs
2. **Application Layer**: Entra ID authentication for webhook endpoints
3. **Event Grid Layer**: Managed identity authentication from Event Grid to functions
4. **Transport Layer**: HTTPS encryption for all traffic

## Security Layers

### Layer 1: Network Isolation

**VNET Integration**:
- Function Apps route all traffic through private VNETs
- Event Grid accessible only via private endpoint
- No direct internet exposure for Event Grid

**IP Restrictions**:
- Allow Event Grid service tag (`AzureEventGrid`)
- Allow Azure management traffic (`AzureCloud`)
- Allow custom IP addresses/CIDR blocks
- Deny all other traffic

### Layer 2: Entra ID Authentication

**Function App Authentication**:
- Entra ID (Azure AD) app registrations for each function
- Token-based authentication for webhook calls
- Azure AD tenant-scoped access control

**Event Grid System Topic**:
- Managed identity for Event Grid
- `Website Contributor` role on Function Apps
- Automatic token acquisition for authenticated calls

### Layer 3: Application Security

**Function-Level Validation**:
- Event type validation
- Event source verification
- Custom business logic authorization

## IP Restrictions Configuration

### Terraform Variables

Configure IP restrictions in `terraform.tfvars`:

```hcl
allowed_ip_addresses = [
  "203.0.113.0/24",
  "198.51.100.42/32"
]
```

### Default Restrictions

The following restrictions are automatically applied:

| Priority | Name | Type | Action |
|----------|------|------|--------|
| 100 | Allow-EventGrid | Service Tag | Allow |
| 110 | Allow-AzureCloud | Service Tag | Allow |
| 200+ | Allow-Custom-{n} | IP/CIDR | Allow |
| 1000 | Deny-All | 0.0.0.0/0 | Deny |

### Service Tags

**AzureEventGrid**:
- All Event Grid service IP addresses in the region
- Required for Event Grid webhook delivery
- Cannot be narrowed to specific Event Grid instance

**AzureCloud**:
- Azure management services
- Required for Azure Portal access and management operations
- Includes deployment, monitoring, and diagnostic services

### Custom IP Addresses

Add your own IP addresses for:
- Development/testing access
- CI/CD pipeline IP ranges
- Corporate network egress IPs
- Bastion host IP addresses

**Format**:
- Single IP: `"203.0.113.42/32"`
- CIDR block: `"203.0.113.0/24"`
- Multiple entries supported

## Entra ID Authentication

### Configuration

Enable authentication in `terraform.tfvars`:

```hcl
enable_function_authentication = true

# Optional: specify custom tenant
entra_tenant_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

If `entra_tenant_id` is not provided, the current tenant is used automatically.

### How It Works

1. **App Registration**: Terraform creates Entra ID app registrations for each function
2. **Service Principal**: Azure AD service principals enable authentication
3. **Function Configuration**: Auth settings applied via `auth_settings_v2`
4. **Token Validation**: Function App validates Azure AD tokens automatically

### Authentication Flow

```
Event Grid System Topic
  ↓ (requests token from Azure AD)
Azure AD
  ↓ (issues JWT token)
Event Grid
  ↓ (webhook call with Bearer token)
Function App Firewall
  ↓ (validates IP from AzureEventGrid)
Function App Auth Layer
  ↓ (validates Azure AD token)
Function Code
  ↓ (processes event)
```

### Unauthenticated Endpoints

The configuration allows anonymous access to HTTP triggers while validating Event Grid webhook calls:

- **HTTP Trigger** (`/api/publish`): Accessible without authentication for testing
- **Event Grid Trigger**: Requires Azure AD token from Event Grid system topic
- **SCM Endpoint**: Accessible via Azure Portal/Azure CLI

This allows manual testing while securing automated Event Grid delivery.

### Strict Authentication Mode

To require authentication for all endpoints, update the configuration:

```hcl
# In auth_settings_v2 block
unauthenticated_action = "RedirectToLoginPage"
require_authentication = true
```

## Event Grid Authentication

### System Topic Managed Identity

Terraform creates an Event Grid system topic with managed identity:

```hcl
resource "azurerm_eventgrid_system_topic" "main" {
  name                = "evgt-system-${random_string.suffix.result}"
  source_arm_resource_id = azurerm_eventgrid_topic.main.id
  topic_type          = "Microsoft.EventGrid.Topics"

  identity {
    type = "SystemAssigned"
  }
}
```

### Role Assignments

Event Grid system topic receives `Website Contributor` role on both functions:

```hcl
resource "azurerm_role_assignment" "eventgrid_to_python_function" {
  scope                = azurerm_linux_function_app.main.id
  role_definition_name = "Website Contributor"
  principal_id         = azurerm_eventgrid_system_topic.main.identity.principal_id
}
```

This allows Event Grid to:
- Invoke function webhook endpoints
- Authenticate using Azure AD tokens
- Access function URLs

### Event Grid Subscription Configuration

The deployment script automatically configures Event Grid subscriptions to use the system topic identity.

## Configuration Examples

### Minimal Security (Development)

```hcl
# terraform.tfvars
enable_function_authentication = false
allowed_ip_addresses = [
  "0.0.0.0/0"  # Allow all (not recommended for production)
]
```

**Use case**: Local development, quick testing

**Security level**: Low - no authentication, open IP access

### Moderate Security (Default)

```hcl
# terraform.tfvars
enable_function_authentication = true
allowed_ip_addresses = []
```

**Use case**: Most production scenarios

**Security level**: Medium - Event Grid + Azure services only, Entra ID auth

### High Security

```hcl
# terraform.tfvars
enable_function_authentication = true
allowed_ip_addresses = [
  "203.0.113.0/24",    # Corporate network
  "198.51.100.10/32"   # Bastion host
]
```

**Use case**: Highly regulated environments, compliance requirements

**Security level**: High - restricted IPs, Entra ID auth, explicit allow-list

### Multi-Region with Custom Tenant

```hcl
# terraform.tfvars
enable_function_authentication = true
entra_tenant_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
allowed_ip_addresses = [
  "10.0.0.0/8",        # Internal networks
  "203.0.113.0/24"     # Partner network
]
```

**Use case**: Multi-tenant deployments, partner integrations

**Security level**: High - custom tenant, network restrictions

## Testing Authentication

### Test IP Restrictions

From allowed IP:
```bash
curl -X POST "https://<function-name>.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test from allowed IP"}'
```

Expected: `200 OK`

From denied IP:
```bash
curl -X POST "https://<function-name>.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test from denied IP"}'
```

Expected: `403 Forbidden`

### Test Event Grid Delivery

Publish event to trigger webhook delivery:
```bash
curl -X POST "https://<function-name>.azurewebsites.net/api/publish" \
  -H "Content-Type: application/json" \
  -d '{"message": "Test Event Grid delivery"}'
```

Check Application Insights logs:
```bash
az monitor app-insights query \
  --app <app-insights-name> \
  --analytics-query "traces | where timestamp > ago(5m) | where message contains 'Successfully received event' | project timestamp, message"
```

### Verify Authentication Configuration

Check function auth settings:
```bash
az functionapp auth show \
  --name <function-name> \
  --resource-group <resource-group>
```

Verify IP restrictions:
```bash
az functionapp config access-restriction show \
  --name <function-name> \
  --resource-group <resource-group>
```

Check Event Grid system topic identity:
```bash
az eventgrid system-topic show \
  --name evgt-system-<suffix> \
  --resource-group rg-eventgrid-vnet-poc-eventgrid \
  --query "identity"
```

## Troubleshooting

### Issue: 403 Forbidden from Event Grid

**Symptom**: Events published successfully but not delivered to function

**Causes**:
- IP restrictions blocking Event Grid IPs
- Missing `AzureEventGrid` service tag
- Event Grid system topic not configured

**Solutions**:

1. Verify IP restrictions include Event Grid:
```bash
az functionapp config access-restriction list \
  --name <function-name> \
  --resource-group <resource-group> \
  --query "[?name=='Allow-EventGrid']"
```

2. Check Event Grid system topic exists:
```bash
az eventgrid system-topic list \
  --resource-group rg-eventgrid-vnet-poc-eventgrid
```

3. Verify role assignment:
```bash
az role assignment list \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<function-name> \
  --query "[?principalType=='ServicePrincipal']"
```

### Issue: 401 Unauthorized

**Symptom**: Webhook calls fail with 401 error

**Causes**:
- Entra ID app registration misconfigured
- Token validation failing
- Audience mismatch

**Solutions**:

1. Verify app registration:
```bash
az ad app list \
  --display-name "func-python-<suffix>" \
  --query "[].{AppId:appId, DisplayName:displayName}"
```

2. Check auth configuration:
```bash
az functionapp auth show \
  --name <function-name> \
  --resource-group <resource-group> \
  --query "properties.identityProviders.azureActiveDirectory"
```

3. Review Function App logs:
```bash
az webapp log tail \
  --name <function-name> \
  --resource-group <resource-group>
```

### Issue: Custom IP Not Working

**Symptom**: Access denied from IP that should be allowed

**Causes**:
- Incorrect CIDR notation
- IP restriction priority conflict
- NAT/proxy changing source IP

**Solutions**:

1. Verify current public IP:
```bash
curl ifconfig.me
```

2. Check IP restriction configuration:
```bash
az functionapp config access-restriction show \
  --name <function-name> \
  --resource-group <resource-group>
```

3. Test with broader CIDR block temporarily:
```hcl
allowed_ip_addresses = [
  "203.0.113.0/24"  # Broader range for testing
]
```

### Issue: Azure Portal Access Blocked

**Symptom**: Cannot access Function App in Azure Portal

**Cause**: IP restrictions too strict, missing `AzureCloud` service tag

**Solution**:

Verify `AzureCloud` service tag is present:
```bash
az functionapp config access-restriction list \
  --name <function-name> \
  --resource-group <resource-group> \
  --query "[?name=='Allow-AzureCloud']"
```

If missing, temporarily disable restrictions:
```bash
az functionapp config access-restriction remove \
  --name <function-name> \
  --resource-group <resource-group> \
  --rule-name "Deny-All"
```

Then redeploy with correct configuration.

## Security Best Practices

1. **Always enable authentication** in production environments
2. **Use specific IP ranges** instead of 0.0.0.0/0
3. **Monitor access logs** in Application Insights
4. **Rotate credentials** regularly (though managed identities don't require rotation)
5. **Apply least privilege** for all role assignments
6. **Enable logging** for all authentication events
7. **Test security controls** after deployment
8. **Document exceptions** when loosening restrictions
9. **Review IP restrictions** quarterly as infrastructure changes
10. **Use Azure Policy** to enforce security standards

## Compliance Considerations

### GDPR
- Personal data in events should be encrypted
- Implement data retention policies in Application Insights
- Document data flows for privacy impact assessments

### SOC 2
- Authentication and authorization controls satisfy access control requirements
- IP restrictions provide network-level controls
- Audit logs in Application Insights support monitoring requirements

### ISO 27001
- Defense-in-depth approach aligns with standard
- Managed identities reduce credential exposure
- Regular review of IP restrictions required

## Additional Resources

- [Azure Function IP Restrictions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-networking-options#inbound-access-restrictions)
- [Entra ID Authentication for Functions](https://learn.microsoft.com/en-us/azure/app-service/configure-authentication-provider-aad)
- [Event Grid Security and Authentication](https://learn.microsoft.com/en-us/azure/event-grid/security-authentication)
- [Azure Service Tags](https://learn.microsoft.com/en-us/azure/virtual-network/service-tags-overview)
