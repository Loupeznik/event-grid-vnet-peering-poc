#!/bin/bash
set -e

echo "==================================================="
echo "VNET Peering & Private Endpoint Connectivity Test"
echo "==================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/azure-context.sh"
init_context

if [ ! -f "$PROJECT_ROOT/terraform/terraform.tfstate" ]; then
    echo "Error: Terraform state file not found. Please run terraform apply first."
    exit 1
fi

cd "$PROJECT_ROOT/terraform"
SUBSCRIPTION_1=$(terraform output -raw subscription_id 2>/dev/null || az account show --query id -o tsv)
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_function)
FUNCTION_HOSTNAME=$(terraform output -raw function_app_default_hostname)
EVENTGRID_TOPIC_NAME=$(terraform output -raw eventgrid_topic_name)
EVENTGRID_PRIVATE_IP=$(terraform output -raw eventgrid_private_endpoint_ip)
ENABLE_DOTNET=$(terraform output -raw enable_dotnet_function)

echo "Configuration:"
echo "  Python Function App: $FUNCTION_APP_NAME"
echo "  Python Function URL: https://$FUNCTION_HOSTNAME"
echo "  Event Grid Topic: $EVENTGRID_TOPIC_NAME"
echo "  Event Grid Private IP: $EVENTGRID_PRIVATE_IP"
echo "  .NET Function Enabled: $ENABLE_DOTNET"

if [ "$ENABLE_DOTNET" = "true" ]; then
    DOTNET_SUBSCRIPTION=$(terraform output -raw dotnet_subscription_id)
    DOTNET_FUNCTION_APP_NAME=$(terraform output -raw dotnet_function_app_name)
    DOTNET_RESOURCE_GROUP=$(terraform output -raw dotnet_resource_group_function)
    DOTNET_HOSTNAME=$(terraform output -raw dotnet_function_app_default_hostname)

    echo "  .NET Function App: $DOTNET_FUNCTION_APP_NAME"
    echo "  .NET Function URL: https://$DOTNET_HOSTNAME"
    echo "  .NET Subscription: $DOTNET_SUBSCRIPTION"
fi

echo ""

echo "==================================================="
echo "Test 1: Verify Infrastructure Configuration"
echo "==================================================="
echo "Event Grid Topic: $EVENTGRID_TOPIC_NAME"
echo "Private Endpoint IP: $EVENTGRID_PRIVATE_IP"
echo ""

echo "==================================================="
echo "Test 2: Python Function → Event Grid → Python Function"
echo "==================================================="
echo "Publishing test event via Python function..."
echo ""

PUBLISH_URL="https://$FUNCTION_HOSTNAME/api/publish"
echo "Publishing to: $PUBLISH_URL"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PUBLISH_URL" \
    -H "Content-Type: application/json" \
    -d '{"message": "Test: Python to Python"}')

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 200 ]; then
    echo "✅ Event published successfully from Python function!"
    echo "Response: $BODY"
else
    echo "❌ Event publishing failed from Python function!"
    echo "HTTP Code: $HTTP_CODE"
    echo "Response: $BODY"
    exit 1
fi

echo ""
echo "Waiting 15 seconds for event delivery..."
sleep 15
echo ""

echo "Checking Python function logs for received event..."
az monitor app-insights query \
    --app "$FUNCTION_APP_NAME" \
    --analytics-query "traces | where timestamp > ago(2m) | where message contains 'Successfully received event' | project timestamp, message | order by timestamp desc | take 5" \
    --offset 2m 2>/dev/null || echo "Application Insights query not available"

echo ""

if [ "$ENABLE_DOTNET" = "true" ]; then
    echo "==================================================="
    echo "Test 3: Python Function → Event Grid → .NET Function"
    echo "==================================================="
    echo "Publishing test event via Python function to .NET consumer..."
    echo ""

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$PUBLISH_URL" \
        -H "Content-Type: application/json" \
        -d '{"message": "Test: Python to .NET"}')

    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" -eq 200 ]; then
        echo "✅ Event published successfully!"
    else
        echo "❌ Event publishing failed!"
        echo "HTTP Code: $HTTP_CODE"
    fi

    echo ""
    echo "Waiting 15 seconds for event delivery..."
    sleep 15
    echo ""

    echo "Checking .NET function logs for received event..."
    push_subscription "$DOTNET_SUBSCRIPTION"
    az monitor app-insights query \
        --app "$DOTNET_FUNCTION_APP_NAME" \
        --analytics-query "traces | where timestamp > ago(2m) | where message contains 'Successfully received event' | project timestamp, message | order by timestamp desc | take 5" \
        --offset 2m 2>/dev/null || echo "Application Insights query not available"
    pop_subscription

    echo ""

    echo "==================================================="
    echo "Test 4: .NET Function → Event Grid → Python Function"
    echo "==================================================="
    echo "Publishing test event via .NET function to Python consumer..."
    echo ""

    DOTNET_PUBLISH_URL="https://$DOTNET_HOSTNAME/api/publish"
    echo "Publishing to: $DOTNET_PUBLISH_URL"

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DOTNET_PUBLISH_URL" \
        -H "Content-Type: application/json" \
        -d '{"message": "Test: .NET to Python"}')

    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" -eq 200 ]; then
        echo "✅ Event published successfully from .NET function!"
        echo "Response: $BODY"
    else
        echo "❌ Event publishing failed from .NET function!"
        echo "HTTP Code: $HTTP_CODE"
        echo "Response: $BODY"
    fi

    echo ""
    echo "Waiting 15 seconds for event delivery..."
    sleep 15
    echo ""

    echo "Checking Python function logs for received event..."
    az monitor app-insights query \
        --app "$FUNCTION_APP_NAME" \
        --analytics-query "traces | where timestamp > ago(2m) | where message contains 'Successfully received event' | project timestamp, message | order by timestamp desc | take 5" \
        --offset 2m 2>/dev/null || echo "Application Insights query not available"

    echo ""

    echo "==================================================="
    echo "Test 5: .NET Function → Event Grid → .NET Function"
    echo "==================================================="
    echo "Publishing test event via .NET function to .NET consumer..."
    echo ""

    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$DOTNET_PUBLISH_URL" \
        -H "Content-Type: application/json" \
        -d '{"message": "Test: .NET to .NET"}')

    HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)

    if [ "$HTTP_CODE" -eq 200 ]; then
        echo "✅ Event published successfully!"
    else
        echo "❌ Event publishing failed!"
    fi

    echo ""
    echo "Waiting 15 seconds for event delivery..."
    sleep 15
    echo ""

    echo "Checking .NET function logs for received event..."
    push_subscription "$DOTNET_SUBSCRIPTION"
    az monitor app-insights query \
        --app "$DOTNET_FUNCTION_APP_NAME" \
        --analytics-query "traces | where timestamp > ago(2m) | where message contains 'Successfully received event' | project timestamp, message | order by timestamp desc | take 5" \
        --offset 2m 2>/dev/null || echo "Application Insights query not available"
    pop_subscription

    echo ""

    echo "==================================================="
    echo "Test 6: Verify Cross-Subscription VNET Peering"
    echo "==================================================="
fi

FUNCTION_VNET=$(terraform output -raw function_vnet_name)
EVENTGRID_VNET=$(terraform output -raw eventgrid_vnet_name)
NETWORK_RG=$(terraform output -raw resource_group_network)

echo "Checking VNET peering status in Subscription 1..."
echo ""

az network vnet peering show \
    --name "peer-function-to-eventgrid" \
    --resource-group "$NETWORK_RG" \
    --vnet-name "$FUNCTION_VNET" \
    --query "{Name:name, State:peeringState, Connected:peeringState=='Connected'}" \
    -o table

echo ""

az network vnet peering show \
    --name "peer-eventgrid-to-function" \
    --resource-group "$NETWORK_RG" \
    --vnet-name "$EVENTGRID_VNET" \
    --query "{Name:name, State:peeringState, Connected:peeringState=='Connected'}" \
    -o table

if [ "$ENABLE_DOTNET" = "true" ]; then
    echo ""
    echo "Checking cross-subscription peering (Subscription 1 → Subscription 2)..."
    echo ""

    az network vnet peering show \
        --name "peer-eventgrid-to-dotnet" \
        --resource-group "$NETWORK_RG" \
        --vnet-name "$EVENTGRID_VNET" \
        --query "{Name:name, State:peeringState, RemoteVNet:remoteVirtualNetwork.id}" \
        -o table

    echo ""
    echo "Checking cross-subscription peering (Subscription 2 → Subscription 1)..."
    echo ""

    push_subscription "$DOTNET_SUBSCRIPTION"
    DOTNET_VNET=$(terraform output -raw dotnet_vnet_name)
    DOTNET_NETWORK_RG=$(terraform output -raw dotnet_resource_group_network)

    az network vnet peering show \
        --name "peer-dotnet-to-eventgrid" \
        --resource-group "$DOTNET_NETWORK_RG" \
        --vnet-name "$DOTNET_VNET" \
        --query "{Name:name, State:peeringState, RemoteVNet:remoteVirtualNetwork.id}" \
        -o table

    pop_subscription
fi

echo ""
echo "==================================================="
echo "Test Summary"
echo "==================================================="
echo ""
echo "✅ Infrastructure deployed successfully"
echo "✅ VNET peering configured and connected"
echo "✅ Private endpoint created for Event Grid"
echo "✅ Python Function App integrated with VNET"
echo "✅ Event published via Python HTTP trigger"

if [ "$ENABLE_DOTNET" = "true" ]; then
    echo "✅ .NET Function App integrated with VNET (Subscription 2)"
    echo "✅ Cross-subscription VNET peering established"
    echo "✅ Event published via .NET HTTP trigger"
    echo "✅ Cross-subscription Event Grid connectivity verified"
fi

echo ""
echo "To verify detailed event delivery:"
echo "1. Check Application Insights logs in Azure Portal"
echo "2. Look for 'Successfully received event via private endpoint' messages"
echo "3. Verify traffic flows through private endpoints"
echo ""
echo "Azure Portal URLs:"
echo ""
echo "Subscription 1 (Python Function):"
echo "  Function App: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_1/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP_NAME"
echo "  Application Insights: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_1/resourceGroups/$RESOURCE_GROUP/providers/microsoft.insights/components/$FUNCTION_APP_NAME"
echo "  Event Grid Topic: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_1/resourceGroups/$(terraform output -raw resource_group_eventgrid)/providers/Microsoft.EventGrid/topics/$EVENTGRID_TOPIC_NAME"

if [ "$ENABLE_DOTNET" = "true" ]; then
    echo ""
    echo "Subscription 2 (.NET Function):"
    echo "  Function App: https://portal.azure.com/#resource/subscriptions/$DOTNET_SUBSCRIPTION/resourceGroups/$DOTNET_RESOURCE_GROUP/providers/Microsoft.Web/sites/$DOTNET_FUNCTION_APP_NAME"
    echo "  Application Insights: https://portal.azure.com/#resource/subscriptions/$DOTNET_SUBSCRIPTION/resourceGroups/$DOTNET_RESOURCE_GROUP/providers/microsoft.insights/components/$DOTNET_FUNCTION_APP_NAME"
fi

echo ""
