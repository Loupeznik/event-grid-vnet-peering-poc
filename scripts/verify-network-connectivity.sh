#!/bin/bash
set -e

echo "=================================================="
echo "Azure Network Connectivity Verification"
echo "=================================================="
echo ""

# Subscription IDs (hardcoded for reliability)
SUB1_ID="6391aa55-ec4d-40af-bc22-2e7ad5b7eda5"  # Event Grid, Python function
SUB2_ID="4f120dcf-daee-4def-b87c-4139995ca024"  # .NET function

# Get terraform outputs
cd "$(dirname "$0")/../terraform"

PYTHON_FUNC_NAME=$(terraform output -raw function_app_name 2>/dev/null || echo "func-eventgrid-*")
DOTNET_FUNC_NAME=$(terraform output -raw dotnet_function_app_name 2>/dev/null || echo "func-dotnet-*")
EVENTGRID_PRIVATE_IP=$(terraform output -raw eventgrid_private_endpoint_ip 2>/dev/null || echo "10.1.1.4")
EVENTHUB_FQDN=$(terraform output -raw eventhub_namespace_fqdn 2>/dev/null || echo "evhns-eventgrid-*.servicebus.windows.net")
RG_NETWORK=$(terraform output -raw resource_group_network 2>/dev/null || echo "rg-eventgrid-vnet-poc-network")
RG_DOTNET_NETWORK=$(terraform output -raw dotnet_resource_group_network 2>/dev/null || echo "rg-eventgrid-vnet-poc-dotnet-network")

echo "Python Function: $PYTHON_FUNC_NAME"
echo "DOTNET Function: $DOTNET_FUNC_NAME"
echo "Event Grid Private IP: $EVENTGRID_PRIVATE_IP"
echo "Event Hub FQDN: $EVENTHUB_FQDN"
echo ""

# Ensure we're in subscription 1
echo "Setting context to Subscription 1..."
az account set --subscription "$SUB1_ID"
echo "✅ Current subscription:"
az account show --query "{Name:name, ID:id}" -o table
echo ""

echo "=================================================="
echo "1. Check Effective Routes (Python Function)"
echo "=================================================="
echo "Getting network interface for Python function..."

PYTHON_FUNC_VNET_ROUTE=$(az functionapp vnet-integration list \
  --name "$PYTHON_FUNC_NAME" \
  --resource-group rg-eventgrid-vnet-poc-function \
  --query "[0].id" -o tsv)

if [ -n "$PYTHON_FUNC_VNET_ROUTE" ]; then
  echo "✅ Python function has VNET integration"

  # Get the subnet details
  PYTHON_SUBNET_ID=$(az functionapp vnet-integration list \
    --name "$PYTHON_FUNC_NAME" \
    --resource-group rg-eventgrid-vnet-poc-function \
    --query "[0].id" -o tsv)
  echo "   Subnet: $PYTHON_SUBNET_ID"
else
  echo "⚠️  Could not determine VNET integration"
fi

echo ""
echo "=================================================="
echo "2. Verify DNS Resolution (Event Grid Private Endpoint)"
echo "=================================================="

# Get Event Grid Topic endpoint
EVENTGRID_ENDPOINT=$(terraform output -raw eventgrid_topic_endpoint)
EVENTGRID_HOSTNAME=$(echo "$EVENTGRID_ENDPOINT" | sed 's|https://||' | sed 's|/.*||')

echo "Event Grid Hostname: $EVENTGRID_HOSTNAME"
echo "Expected Private IP: $EVENTGRID_PRIVATE_IP"
echo ""
echo "Verifying private DNS resolution..."

# Check private DNS zone
PRIVATE_DNS_ZONE=$(az network private-dns zone list \
  --resource-group "$RG_NETWORK" \
  --query "[?contains(name, 'eventgrid')].name" -o tsv)

if [ -n "$PRIVATE_DNS_ZONE" ]; then
  echo "✅ Private DNS Zone: $PRIVATE_DNS_ZONE"

  # List A records
  echo ""
  echo "Private DNS A Records:"
  az network private-dns record-set a list \
    --resource-group "$RG_NETWORK" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --query "[].{Name:name, IP:aRecords[0].ipv4Address, TTL:ttl}" \
    --output table

  # Check VNET links
  echo ""
  echo "VNET Links for Private DNS:"
  az network private-dns link vnet list \
    --resource-group "$RG_NETWORK" \
    --zone-name "$PRIVATE_DNS_ZONE" \
    --query "[].{Name:name, VirtualNetwork:virtualNetwork.id, RegistrationEnabled:registrationEnabled}" \
    --output table
else
  echo "⚠️  Private DNS zone not found"
fi

echo ""
echo "=================================================="
echo "3. Verify Event Hub Private DNS"
echo "=================================================="

# Check Event Hub private DNS zone
EVENTHUB_DNS_ZONE=$(az network private-dns zone list \
  --resource-group "$RG_NETWORK" \
  --query "[?contains(name, 'servicebus')].name" -o tsv)

if [ -n "$EVENTHUB_DNS_ZONE" ]; then
  echo "✅ Event Hub Private DNS Zone: $EVENTHUB_DNS_ZONE"

  # List A records
  echo ""
  echo "Event Hub Private DNS A Records:"
  az network private-dns record-set a list \
    --resource-group "$EVENTHUB_DNS_ZONE" \
    --zone-name "$EVENTHUB_DNS_ZONE" \
    --query "[].{Name:name, IP:aRecords[0].ipv4Address}" \
    --output table 2>/dev/null || echo "No A records found yet"

  # Check VNET links
  echo ""
  echo "VNET Links for Event Hub Private DNS:"
  az network private-dns link vnet list \
    --resource-group "$RG_NETWORK" \
    --zone-name "$EVENTHUB_DNS_ZONE" \
    --query "[].{Name:name, VirtualNetwork:virtualNetwork.id}" \
    --output table
else
  echo "⚠️  Event Hub private DNS zone not found"
fi

echo ""
echo "=================================================="
echo "4. Verify VNET Peering Status"
echo "=================================================="

echo "VNET Peerings in Subscription 1:"

# Get actual VNET names
EVENTGRID_VNET=$(az network vnet list --resource-group "$RG_NETWORK" --query "[?contains(name, 'eventgrid')].name" -o tsv)
FUNCTION_VNET=$(az network vnet list --resource-group "$RG_NETWORK" --query "[?contains(name, 'function')].name" -o tsv)

if [ -n "$EVENTGRID_VNET" ]; then
  echo "Event Grid VNET ($EVENTGRID_VNET) peerings:"
  az network vnet peering list \
    --resource-group "$RG_NETWORK" \
    --vnet-name "$EVENTGRID_VNET" \
    --query "[].{Name:name, State:peeringState, RemoteVnet:remoteVirtualNetwork.id, AllowForwarded:allowForwardedTraffic}" \
    --output table
fi

echo ""
if [ -n "$FUNCTION_VNET" ]; then
  echo "Function VNET ($FUNCTION_VNET) peerings:"
  az network vnet peering list \
    --resource-group "$RG_NETWORK" \
    --vnet-name "$FUNCTION_VNET" \
    --query "[].{Name:name, State:peeringState, RemoteVnet:remoteVirtualNetwork.id, AllowForwarded:allowForwardedTraffic}" \
    --output table
fi

echo ""
echo "VNET Peerings in Subscription 2:"
az account set --subscription "$SUB2_ID"

DOTNET_VNET=$(az network vnet list --resource-group "$RG_DOTNET_NETWORK" --query "[?contains(name, 'dotnet')].name" -o tsv)
if [ -n "$DOTNET_VNET" ]; then
  echo ".NET Function VNET ($DOTNET_VNET) peerings:"
  az network vnet peering list \
    --resource-group "$RG_DOTNET_NETWORK" \
    --vnet-name "$DOTNET_VNET" \
    --query "[].{Name:name, State:peeringState, RemoteVnet:remoteVirtualNetwork.id, AllowForwarded:allowForwardedTraffic}" \
    --output table
else
  echo "⚠️  .NET VNET not found"
fi

# Switch back to subscription 1
az account set --subscription "$SUB1_ID"

echo ""
echo "=================================================="
echo "5. Check Private Endpoints"
echo "=================================================="

echo "Event Grid Private Endpoint:"
az network private-endpoint list \
  --resource-group rg-eventgrid-vnet-poc-eventgrid \
  --query "[?contains(name, 'eventgrid')].{Name:name, ProvisioningState:provisioningState, PrivateIP:customDnsConfigs[0].ipAddresses[0], FQDN:customDnsConfigs[0].fqdn}" \
  --output table

echo ""
echo "Event Hub Private Endpoint:"
az network private-endpoint list \
  --resource-group rg-eventgrid-vnet-poc-eventhub \
  --query "[?contains(name, 'eventhub')].{Name:name, ProvisioningState:provisioningState, PrivateIP:customDnsConfigs[0].ipAddresses[0], FQDN:customDnsConfigs[0].fqdn}" \
  --output table

echo ""
echo "=================================================="
echo "6. Verify Network Security Groups"
echo "=================================================="

echo "NSGs in Network Resource Group:"
az network nsg list \
  --resource-group "$RG_NETWORK" \
  --query "[].{Name:name, Location:location, ProvisioningState:provisioningState}" \
  --output table

echo ""
echo "=================================================="
echo "7. Check Function App Outbound IPs"
echo "=================================================="

echo "Python Function Outbound IPs:"
az functionapp show \
  --name "$PYTHON_FUNC_NAME" \
  --resource-group rg-eventgrid-vnet-poc-function \
  --query "{PossibleOutbound:possibleOutboundIpAddresses, OutboundIPs:outboundIpAddresses, VnetRouteAll:siteConfig.vnetRouteAllEnabled}" \
  --output json | jq .

echo ""
echo ".NET Function Outbound IPs:"
az account set --subscription "$SUB2_ID"
az functionapp show \
  --name "$DOTNET_FUNC_NAME" \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --query "{PossibleOutbound:possibleOutboundIpAddresses, OutboundIPs:outboundIpAddresses, VnetRouteAll:siteConfig.vnetRouteAllEnabled}" \
  --output json | jq .

# Switch back to subscription 1
az account set --subscription "$SUB1_ID"

echo ""
echo "=================================================="
echo "8. Network Watcher - Connection Test"
echo "=================================================="
echo ""
echo "Note: To test actual connectivity, you would need to:"
echo "1. Enable Network Watcher in both regions"
echo "2. Install Network Watcher agent on test VMs"
echo "3. Use 'az network watcher test-connectivity' command"
echo ""
echo "Since Functions don't support Network Watcher agent, we verify via:"
echo "  - Private endpoint provisioning state (above)"
echo "  - VNET peering state (above)"
echo "  - DNS resolution (above)"
echo "  - Actual event delivery (test script)"
echo ""

echo "=================================================="
echo "Verification Complete!"
echo "=================================================="
echo ""
echo "To view network topology in Azure Portal:"
echo "1. Go to Network Watcher service"
echo "2. Select 'Topology' under Monitoring"
echo "3. Select subscription and resource group"
echo ""
echo "To generate visual diagram, run:"
echo "  ./scripts/generate-network-diagram.sh"
echo ""
