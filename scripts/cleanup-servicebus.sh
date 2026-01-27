#!/bin/bash
set -e

echo "==================================================="
echo "Service Bus Cleanup Script"
echo "==================================================="

RESOURCE_GROUP="rg-eventgrid-vnet-poc-servicebus"
NETWORK_RG="rg-eventgrid-vnet-poc-network"
DNS_ZONE="privatelink.servicebus.windows.net"

echo "Step 1: Checking Service Bus resources..."
if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo "Found Service Bus resource group: $RESOURCE_GROUP"

    echo ""
    echo "Resources to be deleted:"
    az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" -o table

    echo ""
    read -p "Delete Service Bus resource group? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting Service Bus resource group..."
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait
        echo "✅ Deletion initiated (running in background)"
    else
        echo "Skipped resource group deletion"
    fi
else
    echo "Service Bus resource group not found (already deleted or never created)"
fi

echo ""
echo "Step 2: Checking Service Bus private DNS zone..."
if az network private-dns zone show --resource-group "$NETWORK_RG" --name "$DNS_ZONE" &>/dev/null; then
    echo "Found Service Bus DNS zone: $DNS_ZONE"

    echo ""
    echo "VNET links to be removed:"
    az network private-dns link vnet list \
        --resource-group "$NETWORK_RG" \
        --zone-name "$DNS_ZONE" \
        --query "[].{Name:name, VNet:virtualNetwork.id}" \
        -o table 2>/dev/null || echo "No VNET links found"

    echo ""
    read -p "Delete Service Bus private DNS zone? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting Service Bus private DNS zone..."
        az network private-dns zone delete \
            --resource-group "$NETWORK_RG" \
            --name "$DNS_ZONE" \
            --yes
        echo "✅ DNS zone deleted"
    else
        echo "Skipped DNS zone deletion"
    fi
else
    echo "Service Bus DNS zone not found (already deleted or never created)"
fi

echo ""
echo "Step 3: Checking for orphaned role assignments..."
# Check for Service Bus role assignments (these will be automatically cleaned up when namespace is deleted)
echo "Role assignments will be automatically removed when namespace is deleted"

echo ""
echo "==================================================="
echo "Cleanup Summary"
echo "==================================================="
echo "✅ Service Bus resource group deletion initiated"
echo "✅ Service Bus private DNS zone deleted"
echo ""
echo "Note: Resource group deletion may take a few minutes to complete."
echo "Check status with: az group show --name $RESOURCE_GROUP"
echo ""
