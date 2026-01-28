#!/bin/bash
set -e

echo "==================================================="
echo "Azure Function Deployment Script"
echo "==================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNCTION_DIR="$PROJECT_ROOT/function"

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
EVENTGRID_TOPIC_NAME=$(terraform output -raw eventgrid_topic_name)
EVENTGRID_RG=$(terraform output -raw resource_group_eventgrid)
ENABLE_DOTNET=$(terraform output -raw enable_dotnet_function)
ENABLE_EVENT_HUB=$(terraform output -raw enable_event_hub 2>/dev/null || echo "false")

echo "Python Function App: $FUNCTION_APP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo "Event Grid Topic: $EVENTGRID_TOPIC_NAME"
echo ".NET Function Enabled: $ENABLE_DOTNET"
echo ""

if [ "$ENABLE_DOTNET" = "true" ]; then
    DOTNET_SUBSCRIPTION=$(terraform output -raw dotnet_subscription_id)
    DOTNET_FUNCTION_APP_NAME=$(terraform output -raw dotnet_function_app_name)
    DOTNET_RESOURCE_GROUP=$(terraform output -raw dotnet_resource_group_function)

    echo ".NET Function App: $DOTNET_FUNCTION_APP_NAME"
    echo ".NET Resource Group: $DOTNET_RESOURCE_GROUP"
    echo ".NET Subscription: $DOTNET_SUBSCRIPTION"
    echo ""

    echo "Verifying access to both subscriptions..."
    verify_subscription_access "$SUBSCRIPTION_1" || exit 1
    verify_subscription_access "$DOTNET_SUBSCRIPTION" || exit 1
    echo "✅ Access verified"
    echo ""
fi

echo "==================================================="
echo "Deploying Python Function"
echo "==================================================="

echo "Step 1: Creating Python deployment package..."
cd "$FUNCTION_DIR"
if [ -f "deployment.zip" ]; then
    rm deployment.zip
fi
zip -r deployment.zip . -x "*.pyc" -x "__pycache__/*" -x "*.zip" -q
echo "✅ Python deployment package created"
echo ""

echo "Step 2: Deploying Python function code to Azure..."
az functionapp deployment source config-zip \
    --resource-group "$RESOURCE_GROUP" \
    --name "$FUNCTION_APP_NAME" \
    --src deployment.zip \
    --build-remote true

echo "✅ Python function code deployed"
echo ""

echo "Step 3: Waiting for Python function app to process deployment..."
sleep 30
echo ""

echo "Step 4: Verifying Python function exists..."
MAX_RETRIES=15
RETRY_COUNT=0
FUNCTION_FOUND=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Checking for consume_event function (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."

    FUNCTIONS=$(az functionapp function list \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" -o tsv 2>/dev/null || echo "")

    if echo "$FUNCTIONS" | grep -q "consume_event"; then
        echo "✅ Python function consume_event found!"
        FUNCTION_FOUND=true
        break
    fi

    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "Function not found yet, waiting 10 seconds..."
        sleep 10
    fi
done

if [ "$FUNCTION_FOUND" = false ]; then
    echo "❌ Error: Function consume_event not found after $MAX_RETRIES attempts"
    exit 1
fi
echo ""

if [ "$ENABLE_DOTNET" = "true" ]; then
    echo "==================================================="
    echo "Deploying .NET Function"
    echo "==================================================="

    echo "Step 5: Building .NET function..."
    "$SCRIPT_DIR/deploy-dotnet-function.sh"
    echo ""

    echo "Step 6: Deploying .NET function code to Azure..."
    push_subscription "$DOTNET_SUBSCRIPTION"

    az functionapp deployment source config-zip \
        --resource-group "$DOTNET_RESOURCE_GROUP" \
        --name "$DOTNET_FUNCTION_APP_NAME" \
        --src "$PROJECT_ROOT/EventGridPubSubFunction/deployment.zip"

    echo "✅ .NET function code deployed"
    echo ""

    echo "Step 7: Waiting for .NET function app to process deployment..."
    sleep 20
    echo ""

    echo "Step 8: Verifying .NET functions exist..."
    RETRY_COUNT=0
    CONSUME_FOUND=false
    PUBLISH_FOUND=false

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        echo "Checking for .NET functions (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."

        FUNCTIONS=$(az functionapp function list \
            --name "$DOTNET_FUNCTION_APP_NAME" \
            --resource-group "$DOTNET_RESOURCE_GROUP" \
            --query "[].name" -o tsv 2>/dev/null || echo "")

        if echo "$FUNCTIONS" | grep -q "ConsumeEvent"; then
            CONSUME_FOUND=true
        fi
        if echo "$FUNCTIONS" | grep -q "PublishEvent"; then
            PUBLISH_FOUND=true
        fi

        if [ "$CONSUME_FOUND" = true ] && [ "$PUBLISH_FOUND" = true ]; then
            echo "✅ .NET functions ConsumeEvent and PublishEvent found!"
            break
        fi

        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "Functions not found yet, waiting 10 seconds..."
            sleep 10
        fi
    done

    if [ "$CONSUME_FOUND" = false ] || [ "$PUBLISH_FOUND" = false ]; then
        echo "❌ Error: .NET functions not found after $MAX_RETRIES attempts"
        echo "ConsumeEvent found: $CONSUME_FOUND"
        echo "PublishEvent found: $PUBLISH_FOUND"
        pop_subscription
        exit 1
    fi

    pop_subscription
    echo ""
fi

echo "==================================================="
echo "Creating Event Grid Subscriptions"
echo "==================================================="

STEP_NUM=9
if [ "$ENABLE_DOTNET" != "true" ]; then
    STEP_NUM=5
fi

echo "Step $STEP_NUM: Creating Python function Event Grid subscription..."
FUNCTION_RESOURCE_ID=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
PYTHON_SUB_NAME="func-python-sub-$(date +%s)"

az eventgrid event-subscription create \
    --name "$PYTHON_SUB_NAME" \
    --source-resource-id "/subscriptions/$SUBSCRIPTION_1/resourceGroups/$EVENTGRID_RG/providers/Microsoft.EventGrid/topics/$EVENTGRID_TOPIC_NAME" \
    --endpoint-type azurefunction \
    --endpoint "$FUNCTION_RESOURCE_ID/functions/consume_event" \
    --max-delivery-attempts 3 \
    --event-delivery-schema eventgridschema

echo "✅ Python function Event Grid subscription created"
echo ""

if [ "$ENABLE_DOTNET" = "true" ]; then
    STEP_NUM=$((STEP_NUM + 1))

    if [ "$ENABLE_EVENT_HUB" = "true" ]; then
        echo "Step $STEP_NUM: Creating Event Grid subscription to Event Hub..."

        EVENTHUB_ID=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw eventhub_id)
        EVENTHUB_SUB_NAME="eventgrid-to-eventhub-$(date +%s)"

        az eventgrid event-subscription create \
            --name "$EVENTHUB_SUB_NAME" \
            --source-resource-id "/subscriptions/$SUBSCRIPTION_1/resourceGroups/$EVENTGRID_RG/providers/Microsoft.EventGrid/topics/$EVENTGRID_TOPIC_NAME" \
            --endpoint-type eventhub \
            --endpoint "$EVENTHUB_ID" \
            --max-delivery-attempts 3 \
            --event-delivery-schema eventgridschema

        echo "✅ Event Grid subscription to Event Hub created"
        echo "   .NET function will receive events via Event Hub trigger"
    else
        echo "Step $STEP_NUM: Creating .NET function Event Grid subscription (webhook)..."

        push_subscription "$DOTNET_SUBSCRIPTION"
        DOTNET_FUNCTION_RESOURCE_ID=$(az functionapp show --name "$DOTNET_FUNCTION_APP_NAME" --resource-group "$DOTNET_RESOURCE_GROUP" --query id -o tsv)
        pop_subscription

        DOTNET_SUB_NAME="func-dotnet-sub-$(date +%s)"

        az eventgrid event-subscription create \
            --name "$DOTNET_SUB_NAME" \
            --source-resource-id "/subscriptions/$SUBSCRIPTION_1/resourceGroups/$EVENTGRID_RG/providers/Microsoft.EventGrid/topics/$EVENTGRID_TOPIC_NAME" \
            --endpoint-type azurefunction \
            --endpoint "$DOTNET_FUNCTION_RESOURCE_ID/functions/ConsumeEvent" \
            --max-delivery-attempts 3 \
            --event-delivery-schema eventgridschema

        echo "✅ .NET function Event Grid subscription (webhook) created"
    fi
    echo ""
fi

echo "==================================================="
echo "Deployment completed successfully!"
echo "==================================================="
echo ""
echo "Python Function App URL: https://$FUNCTION_APP_NAME.azurewebsites.net"
echo "Python Publish endpoint: https://$FUNCTION_APP_NAME.azurewebsites.net/api/publish"

if [ "$ENABLE_DOTNET" = "true" ]; then
    echo ""
    echo ".NET Function App URL: https://$DOTNET_FUNCTION_APP_NAME.azurewebsites.net"
    echo ".NET Publish endpoint: https://$DOTNET_FUNCTION_APP_NAME.azurewebsites.net/api/publish"

    if [ "$ENABLE_EVENT_HUB" = "true" ]; then
        echo ".NET Delivery Mode: Event Hub (fully private)"
    else
        echo ".NET Delivery Mode: Webhook (public endpoint with IP restrictions)"
    fi
fi

echo ""
echo "Next steps:"
echo "1. Run the test script: ./scripts/test-connectivity.sh"
echo "2. Check logs in Azure Portal > Function App > Log stream"
echo "3. View metrics in Application Insights"
echo ""
