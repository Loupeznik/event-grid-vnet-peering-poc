#!/bin/bash
set -e

echo "==================================================="
echo "Azure Function Deployment Script"
echo "==================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FUNCTION_DIR="$PROJECT_ROOT/function"

if [ ! -f "$PROJECT_ROOT/terraform/terraform.tfstate" ]; then
    echo "Error: Terraform state file not found. Please run terraform apply first."
    exit 1
fi

cd "$PROJECT_ROOT/terraform"
FUNCTION_APP_NAME=$(terraform output -raw function_app_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_function)
EVENTGRID_TOPIC_NAME=$(terraform output -raw eventgrid_topic_name)
EVENTGRID_RG=$(terraform output -raw resource_group_eventgrid)

echo "Function App Name: $FUNCTION_APP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo "Event Grid Topic: $EVENTGRID_TOPIC_NAME"
echo ""

echo "Step 1: Creating deployment package..."
cd "$FUNCTION_DIR"
if [ -f "deployment.zip" ]; then
    rm deployment.zip
fi
zip -r deployment.zip . -x "*.pyc" -x "__pycache__/*" -x "*.zip"
echo "✅ Deployment package created"
echo ""

echo "Step 2: Deploying function code to Azure..."
az functionapp deployment source config-zip \
    --resource-group "$RESOURCE_GROUP" \
    --name "$FUNCTION_APP_NAME" \
    --src deployment.zip \
    --build-remote true

echo "✅ Function code deployed"
echo ""

echo "Step 3: Waiting for function app to process deployment..."
sleep 20
echo ""

echo "Step 4: Verifying function exists..."
MAX_RETRIES=10
RETRY_COUNT=0
FUNCTION_FOUND=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Checking for consume_event function (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."

    FUNCTIONS=$(az functionapp function list \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" -o tsv 2>/dev/null || echo "")

    if echo "$FUNCTIONS" | grep -q "consume_event"; then
        echo "✅ Function consume_event found!"
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
    echo ""
    echo "Available functions:"
    az functionapp function list \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name, Language:language}" -o table 2>/dev/null || echo "Could not list functions"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check function app logs: az webapp log tail --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
    echo "2. Verify deployment in Azure Portal"
    echo "3. Re-run this script after fixing any issues"
    exit 1
fi
echo ""

echo "Step 5: Creating Event Grid subscription..."
FUNCTION_RESOURCE_ID=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
SUBSCRIPTION_NAME="func-eventgrid-sub-$(date +%s)"

az eventgrid event-subscription create \
    --name "$SUBSCRIPTION_NAME" \
    --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$EVENTGRID_RG/providers/Microsoft.EventGrid/topics/$EVENTGRID_TOPIC_NAME" \
    --endpoint-type azurefunction \
    --endpoint "$FUNCTION_RESOURCE_ID/functions/consume_event" \
    --max-delivery-attempts 3 \
    --event-delivery-schema eventgridschema

echo "✅ Event Grid subscription created"
echo ""

echo "==================================================="
echo "Deployment completed successfully!"
echo "==================================================="
echo ""
echo "Function App URL: https://$FUNCTION_APP_NAME.azurewebsites.net"
echo "Publish endpoint: https://$FUNCTION_APP_NAME.azurewebsites.net/api/publish"
echo ""
echo "Next steps:"
echo "1. Run the test script: ./scripts/test-connectivity.sh"
echo "2. Check logs in Azure Portal > Function App > Log stream"
echo "3. View metrics in Application Insights"
echo ""
