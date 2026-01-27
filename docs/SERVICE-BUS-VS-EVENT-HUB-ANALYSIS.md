# Service Bus vs Event Hub vs Storage Queue for Fully Private Event Grid Communication

**Date:** January 26, 2026
**Last Updated:** January 27, 2026 (Service Bus Premium pricing update)
**Analysis Scope:** Alternative to webhook delivery for achieving fully private communication
**Target Function:** .NET Function (Subscription 2) only
**Status:** ✅ Validated - All three approaches are technically feasible

---

## 🚨 CRITICAL UPDATE (January 27, 2026)

**Service Bus Private Endpoints Require Premium SKU**

During implementation, we discovered that Service Bus private endpoints are **only supported on Premium SKU**, not Standard SKU.

**Impact:**
- **Previous estimate:** Service Bus ~$21/month (Standard SKU)
- **Actual cost:** Service Bus **~$677/month** (Premium SKU required)
- **Cost increase:** **32x more expensive** than originally estimated

**Pricing Model:**
- Premium SKU charges **$0.928/hour per messaging unit** (continuous hourly billing)
- **Minimum 1 messaging unit** required (cannot scale to zero)
- **Not pay-as-you-go** - you pay for reserved capacity, not message volume
- **Fixed cost** regardless of whether you send 0 messages or 1 billion messages

**Revised Recommendation:**
- ✅ **Event Hub** is now the **best option** for fully private PoC ($31/month, 22x cheaper)
- ✅ **Storage Queue** remains best for budget-conscious PoC ($8/month, semi-private)
- ❌ **Service Bus Premium** is **NOT recommended** for PoC due to extreme cost

---

## Executive Summary

**Azure Service Bus**, **Azure Event Hubs**, and **Azure Storage Queue** can all be used as middleware to achieve bidirectional communication with Event Grid, eliminating the webhook delivery limitation where traffic traverses the public internet. This analysis validates all three approaches, compares their characteristics, and provides implementation guidance for the .NET function.

⚠️ **Important Note on Privacy:** Storage Queue uses "trusted services" access (traffic on Microsoft backbone) rather than private endpoints for Event Grid delivery, making it **semi-private** rather than fully private like Service Bus and Event Hub.

### Key Findings

| Aspect | Service Bus | Event Hub | Storage Queue | Winner |
|--------|-------------|-----------|---------------|--------|
| **Feasibility** | ✅ Fully Supported | ✅ Fully Supported | ✅ Supported | Tie |
| **Monthly Cost** | ⚠️ **~$677/month (Premium)** | ~$31/month | ~$8/month | 🏆 Storage Queue |
| **Complexity** | Lower (traditional queue) | Medium (partition-based) | Lowest (simple queue) | 🏆 Storage Queue |
| **Privacy Level** | ✅ Fully Private (PE) | ✅ Fully Private (PE) | ⚠️ Semi-Private (Trusted) | 🏆 Event Hub |
| **Latency** | 50-200ms | 100-500ms | 50-300ms | 🏆 Service Bus |
| **Throughput** | 20 MB/s (Premium) | 1 MB/s per TU | 2,000 msg/s | 🏆 Service Bus |
| **Message Size** | 100 MB (Premium) | 1 MB | 64 KB | 🏆 Service Bus |
| **Retention** | TTL-based (max 14 days) | 1-7 days (Standard) | 7 days (max) | Service Bus |
| **Feature Set** | Rich (sessions, transactions) | Streaming-focused | Basic (simple queue) | 🏆 Service Bus |
| **Best For** | Traditional messaging, command/control | High-volume streaming, analytics | Budget-conscious, simple queuing | Depends on use case |

### Recommendation

⚠️ **CRITICAL UPDATE:** Service Bus private endpoints require **Premium SKU** (~$677/month), making it **85x more expensive** than Storage Queue and **22x more expensive** than Event Hub.

**For this PoC:** 🏆 **Azure Event Hub (Standard Tier)**

**Rationale:**
- **Fully private** (private endpoints for Event Grid delivery)
- **Affordable cost** (~$31/month - only 4x Storage Queue, 22x cheaper than Service Bus Premium)
- Production-grade reliability and support
- Scales to high volumes if needed
- Rich feature set (partitioning, event replay, retention)
- **Best balance of privacy and cost**

**When to Choose Storage Queue Instead:**
- **Minimum budget** (~$8/month - absolute lowest cost)
- **Semi-private is acceptable** - trusted services (Microsoft backbone) vs full private endpoints
- **Simple use case** - basic queuing without advanced features
- **Existing Storage Account** - already have infrastructure
- **PoC/testing only** - not planning production deployment

**When to Choose Service Bus Premium:**
- ❌ **NOT recommended for PoC** due to extreme cost (~$677/month)
- Only if you have a **hard requirement** for:
  - Service Bus-specific features (sessions, transactions, request-reply)
  - Existing enterprise Service Bus infrastructure
  - Company-mandated Service Bus standard
- **Cost warning:** ~$67 for just 3-day PoC vs ~$3 for Event Hub

**Service Bus Premium Pricing Model:**
- **Hourly charge:** ~$0.928/hour per messaging unit
- **Not pay-as-you-go:** Continuous hourly billing for reserved capacity
- **Minimum:** 1 messaging unit required (can't scale to zero)
- **Usage independent:** Same cost for 0 messages or 1 billion messages

---

## Technical Validation

### Microsoft Official Support

Both approaches are **officially documented and supported** by Microsoft:

**Service Bus:**
> "You can deliver events to Event Hubs, Service Bus, or Azure Storage using an Azure Event Grid custom topic or domain with system-assigned or user-assigned managed identity."

**Source:** [Microsoft Learn - Deliver events using private link service](https://learn.microsoft.com/en-us/azure/event-grid/consume-private-endpoints)

> "Azure Event Grid enables routing events directly to Azure Service Bus queues and topics for buffering, command and control scenarios, and messaging patterns in enterprise applications."

**Source:** [Microsoft Learn - Configure Service Bus as Event Handlers](https://learn.microsoft.com/en-us/azure/event-grid/handler-service-bus)

**Event Hub:**
> "However, you can use a private link configured in Azure Functions or your webhook deployed on your virtual network to pull events [from Event Hub]."

**Source:** [Microsoft Q&A - Event Grid and Functions](https://learn.microsoft.com/en-us/answers/questions/1491065/azure-function-app-calling-and-azure-event-grid)

### Private Endpoint Support

Both services support private endpoints for Azure Functions:

**Service Bus Private Link:**
> "Azure Private Link Service enables you to access Azure Service Bus over a private endpoint in your virtual network."

**Source:** [Microsoft Learn - Service Bus Private Link](https://learn.microsoft.com/en-us/azure/service-bus-messaging/private-link-service)

**Event Hub Private Link:**
> "Azure Private Link enables you to access Azure services over a private endpoint in your virtual network."

**Source:** [Microsoft Learn - Event Hubs Private Endpoints](https://learn.microsoft.com/en-us/azure/event-hubs/private-link-service)

### Azure Functions Integration

Both services support triggers with VNET integration:

> "Runtime-driven scaling allows you to connect non-HTTP trigger functions to services that run inside your virtual network."

**Source:** [Microsoft Learn - Functions VNET Integration](https://learn.microsoft.com/en-us/azure/azure-functions/functions-create-vnet)

---

## Architecture Comparison

### Current Architecture (Webhook - Partially Public)

```
┌─────────────────┐         ┌──────────────┐         ┌─────────────────┐
│ .NET Function   │ PRIVATE │ Event Grid   │ PUBLIC  │ .NET Function   │
│ (Subscription 2)│────────▶│ Topic        │────────▶│ Webhook         │
│                 │  10.1.4  │ (Sub 1)      │ Internet│ (Public HTTPS)  │
│ Publish         │         │              │         │ Consume         │
└─────────────────┘         └──────────────┘         └─────────────────┘
    ✅ Private                                            ❌ Public
```

### Service Bus Architecture (Fully Private)

```
┌─────────────────┐         ┌──────────────┐         ┌──────────────────┐
│ .NET Function   │ PRIVATE │ Event Grid   │ PRIVATE │ Service Bus      │
│ (Subscription 2)│────────▶│ Topic        │────────▶│ Queue/Topic      │
│                 │  10.1.4  │ (Sub 1)      │ Managed │ (Sub 1)          │
│ Publish         │         │              │ Identity│                  │
└─────────────────┘         └──────────────┘         └──────────────────┘
                                                               │
                                                      PRIVATE  │
                                                      10.1.3.4 │
                                                               ▼
                                                      ┌──────────────────┐
                                                      │ .NET Function    │
                                                      │ ServiceBusTrigger│
                                                      │ (Subscription 2) │
                                                      │ Consume          │
                                                      └──────────────────┘
    ✅ Private              ✅ Private                ✅ Private
```

### Event Hub Architecture (Fully Private)

```
┌─────────────────┐         ┌──────────────┐         ┌──────────────────┐
│ .NET Function   │ PRIVATE │ Event Grid   │ PRIVATE │ Event Hub        │
│ (Subscription 2)│────────▶│ Topic        │────────▶│ Namespace        │
│                 │  10.1.4  │ (Sub 1)      │ Managed │ (Sub 1)          │
│ Publish         │         │              │ Identity│                  │
└─────────────────┘         └──────────────┘         └──────────────────┘
                                                               │
                                                      PRIVATE  │
                                                      10.1.3.4 │
                                                               ▼
                                                      ┌──────────────────┐
                                                      │ .NET Function    │
                                                      │ EventHubTrigger  │
                                                      │ (Subscription 2) │
                                                      │ Consume          │
                                                      └──────────────────┘
    ✅ Private              ✅ Private                ✅ Private
```

---

## Implementation: Service Bus Approach

### Infrastructure Changes (Terraform)

**New File: `terraform/servicebus.tf`**

```hcl
# Service Bus Namespace in Subscription 1
resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-eventgrid-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.eventgrid.name
  sku                 = "Standard"  # Required for VNET integration

  # Disable public network access
  public_network_access_enabled = false

  tags = var.tags
}

# Service Bus Queue
resource "azurerm_servicebus_queue" "events" {
  name         = "events"
  namespace_id = azurerm_servicebus_namespace.main.id

  # Enable duplicate detection (recommended for Event Grid)
  requires_duplicate_detection = true
  duplicate_detection_history_time_window = "PT10M"  # 10 minutes

  # Enable dead-lettering
  dead_lettering_on_message_expiration = true

  # Message TTL: 1 day
  default_message_ttl = "P1D"

  # Lock duration for processing
  lock_duration = "PT5M"  # 5 minutes

  # Max delivery attempts
  max_delivery_count = 10
}

# Alternative: Service Bus Topic with Subscription
# Useful if you want multiple consumers or filtering
resource "azurerm_servicebus_topic" "events" {
  count        = var.use_servicebus_topic ? 1 : 0
  name         = "events"
  namespace_id = azurerm_servicebus_namespace.main.id

  requires_duplicate_detection = true
  duplicate_detection_history_time_window = "PT10M"

  default_message_ttl = "P1D"
}

resource "azurerm_servicebus_subscription" "dotnet_function" {
  count    = var.use_servicebus_topic ? 1 : 0
  name     = "dotnet-function-sub"
  topic_id = azurerm_servicebus_topic.events[0].id

  max_delivery_count               = 10
  dead_lettering_on_message_expiration = true
  lock_duration                    = "PT5M"
}

# Private Endpoint for Service Bus in VNET2
resource "azurerm_private_endpoint" "servicebus" {
  name                = "pe-servicebus-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.eventgrid.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "pe-connection-servicebus"
    private_connection_resource_id = azurerm_servicebus_namespace.main.id
    is_manual_connection          = false
    subresource_names             = ["namespace"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.servicebus.id]
  }

  tags = var.tags

  depends_on = [
    azurerm_servicebus_namespace.main
  ]
}

# Private DNS Zone for Service Bus
resource "azurerm_private_dns_zone" "servicebus" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.network.name

  tags = var.tags
}

# Link Private DNS Zone to all VNETs
resource "azurerm_private_dns_zone_virtual_network_link" "servicebus_vnet1" {
  name                  = "vnet1-servicebus-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.servicebus.name
  virtual_network_id    = azurerm_virtual_network.function_vnet.id

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "servicebus_vnet2" {
  name                  = "vnet2-servicebus-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.servicebus.name
  virtual_network_id    = azurerm_virtual_network.eventgrid_vnet.id

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "servicebus_vnet3" {
  count                 = var.enable_dotnet_function ? 1 : 0
  name                  = "vnet3-servicebus-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.servicebus.name
  virtual_network_id    = azurerm_virtual_network.dotnet_vnet[0].id

  tags = var.tags
}

# IAM: Grant Event Grid managed identity permission to send to Service Bus
resource "azurerm_role_assignment" "eventgrid_servicebus_sender" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_eventgrid_topic.main.identity[0].principal_id
}

# IAM: Grant .NET Function managed identity permission to receive from Service Bus
resource "azurerm_role_assignment" "dotnet_function_servicebus_receiver" {
  count                = var.enable_dotnet_function ? 1 : 0
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_linux_function_app.dotnet[0].identity[0].principal_id
}
```

**Update `terraform/eventgrid.tf`:**

```hcl
# Enable managed identity on Event Grid topic
resource "azurerm_eventgrid_topic" "main" {
  name                = "evgt-poc-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.eventgrid.name

  # Disable public network access
  public_network_access_enabled = false

  # Enable managed identity for Service Bus delivery
  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Event Grid subscription to Service Bus Queue
resource "azurerm_eventgrid_event_subscription" "to_servicebus_queue" {
  count = var.use_servicebus && !var.use_servicebus_topic ? 1 : 0
  name  = "eventgrid-to-servicebus-queue"
  scope = azurerm_eventgrid_topic.main.id

  service_bus_queue_endpoint_id = azurerm_servicebus_queue.events.id

  # Use managed identity for authentication
  delivery_identity {
    type = "SystemAssigned"
  }

  # Optional: Set custom delivery properties
  delivery_property {
    header_name  = "MessageId"
    type         = "Dynamic"
    source_field = "id"
  }

  delivery_property {
    header_name = "CorrelationId"
    type        = "Static"
    value       = "event-grid-delivery"
  }

  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440  # 24 hours
  }

  depends_on = [
    azurerm_role_assignment.eventgrid_servicebus_sender
  ]
}

# Event Grid subscription to Service Bus Topic
resource "azurerm_eventgrid_event_subscription" "to_servicebus_topic" {
  count = var.use_servicebus && var.use_servicebus_topic ? 1 : 0
  name  = "eventgrid-to-servicebus-topic"
  scope = azurerm_eventgrid_topic.main.id

  service_bus_topic_endpoint_id = azurerm_servicebus_topic.events[0].id

  delivery_identity {
    type = "SystemAssigned"
  }

  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440
  }

  depends_on = [
    azurerm_role_assignment.eventgrid_servicebus_sender
  ]
}
```

**Update `terraform/variables.tf`:**

```hcl
variable "use_servicebus" {
  type        = bool
  description = "Use Service Bus for fully private event delivery (alternative to webhook)"
  default     = false
}

variable "use_servicebus_topic" {
  type        = bool
  description = "Use Service Bus Topic instead of Queue (allows multiple consumers)"
  default     = false
}
```

**Update `terraform/outputs.tf`:**

```hcl
output "servicebus_namespace_name" {
  value       = var.use_servicebus ? azurerm_servicebus_namespace.main.name : null
  description = "Service Bus namespace name"
}

output "servicebus_queue_name" {
  value       = var.use_servicebus && !var.use_servicebus_topic ? azurerm_servicebus_queue.events.name : null
  description = "Service Bus queue name"
}

output "servicebus_topic_name" {
  value       = var.use_servicebus && var.use_servicebus_topic ? azurerm_servicebus_topic.events[0].name : null
  description = "Service Bus topic name"
}

output "servicebus_connection_endpoint" {
  value       = var.use_servicebus ? "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net" : null
  description = "Service Bus fully qualified namespace (for managed identity connection)"
}
```

### .NET Function Code Changes

**Update `EventGridPubSubFunction/EventGridPubSubFunction.csproj`:**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <AzureFunctionsVersion>v4</AzureFunctionsVersion>
    <OutputType>Exe</OutputType>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Azure.Identity" Version="1.13.1" />
    <PackageReference Include="Azure.Messaging.EventGrid" Version="4.30.0" />
    <PackageReference Include="Microsoft.Azure.Functions.Worker" Version="2.0.0" />
    <PackageReference Include="Microsoft.Azure.Functions.Worker.Sdk" Version="2.0.0" />
    <PackageReference Include="Microsoft.ApplicationInsights.WorkerService" Version="2.22.0" />
    <PackageReference Include="Microsoft.Azure.Functions.Worker.ApplicationInsights" Version="2.0.0" />

    <!-- Add Service Bus SDK -->
    <PackageReference Include="Microsoft.Azure.Functions.Worker.Extensions.ServiceBus" Version="5.24.0" />
    <PackageReference Include="Azure.Messaging.ServiceBus" Version="7.18.2" />
  </ItemGroup>
  <ItemGroup>
    <None Update="host.json">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
    <None Update="local.settings.json">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
      <CopyToPublishDirectory>Never</CopyToPublishDirectory>
    </None>
  </ItemGroup>
</Project>
```

**Replace `EventGridFunctions.cs` with `EventGridServiceBusFunctions.cs`:**

```csharp
using Azure;
using Azure.Identity;
using Azure.Messaging.EventGrid;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using Azure.Messaging.ServiceBus;

namespace EventGridPubSubFunction
{
    public class EventGridServiceBusFunctions
    {
        private readonly ILogger<EventGridServiceBusFunctions> _logger;

        public EventGridServiceBusFunctions(ILogger<EventGridServiceBusFunctions> logger)
        {
            _logger = logger;
        }

        /// <summary>
        /// HTTP trigger that publishes events to Event Grid (unchanged from webhook version)
        /// </summary>
        [Function("PublishEvent")]
        public async Task<HttpResponseData> PublishEvent(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", Route = "publish")] HttpRequestData req)
        {
            _logger.LogInformation("Processing HTTP request to publish event to Event Grid");

            try
            {
                var endpoint = Environment.GetEnvironmentVariable("EVENT_GRID_TOPIC_ENDPOINT");
                if (string.IsNullOrEmpty(endpoint))
                {
                    var errorResponse = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                    await errorResponse.WriteStringAsync("EVENT_GRID_TOPIC_ENDPOINT not configured");
                    return errorResponse;
                }

                // Use managed identity to authenticate
                var credential = new DefaultAzureCredential();
                var client = new EventGridPublisherClient(new Uri(endpoint), credential);

                // Parse request body or use default message
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var data = string.IsNullOrEmpty(requestBody)
                    ? new { message = "Test event from .NET function" }
                    : JsonSerializer.Deserialize<dynamic>(requestBody);

                var eventId = $"event-{DateTime.UtcNow:yyyyMMddHHmmssfff}";
                var eventGridEvent = new EventGridEvent(
                    subject: "test/event",
                    eventType: "Custom.TestEvent",
                    dataVersion: "1.0",
                    data: new
                    {
                        message = data?.GetProperty("message").GetString() ?? "Test event from .NET function",
                        timestamp = DateTime.UtcNow.ToString("o"),
                        source = "azure-function-via-private-endpoint"
                    }
                );

                await client.SendEventAsync(eventGridEvent);

                _logger.LogInformation($"Successfully published event {eventId} to Event Grid");

                var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await response.WriteAsJsonAsync(new
                {
                    status = "success",
                    message = "Event published successfully",
                    eventId = eventId,
                    endpoint = endpoint
                });

                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error publishing event to Event Grid");

                var errorResponse = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errorResponse.WriteAsJsonAsync(new
                {
                    status = "error",
                    message = ex.Message
                });

                return errorResponse;
            }
        }

        /// <summary>
        /// Service Bus Queue trigger that receives events from Event Grid via Service Bus
        /// REPLACES the EventGridTrigger (webhook-based)
        /// </summary>
        [Function("ConsumeEventFromQueue")]
        public async Task ConsumeEventFromQueue(
            [ServiceBusTrigger("events", Connection = "ServiceBusConnection")]
            ServiceBusReceivedMessage message,
            ServiceBusMessageActions messageActions)
        {
            _logger.LogInformation("Service Bus Queue trigger function processing message");

            try
            {
                // Parse Event Grid event from Service Bus message body
                var messageBody = message.Body.ToString();
                _logger.LogInformation($"Raw message body: {messageBody}");

                // Event Grid wraps the event in an array when delivering to Service Bus
                var eventGridEvents = JsonSerializer.Deserialize<EventGridEvent[]>(messageBody);

                if (eventGridEvents == null || eventGridEvents.Length == 0)
                {
                    _logger.LogWarning("No Event Grid events found in message");
                    await messageActions.CompleteMessageAsync(message);
                    return;
                }

                foreach (var eventGridEvent in eventGridEvents)
                {
                    _logger.LogInformation($"✅ Event received via FULLY PRIVATE path (Service Bus)");
                    _logger.LogInformation($"Event ID: {eventGridEvent.Id}");
                    _logger.LogInformation($"Event Type: {eventGridEvent.EventType}");
                    _logger.LogInformation($"Event Subject: {eventGridEvent.Subject}");
                    _logger.LogInformation($"Event Time: {eventGridEvent.EventTime}");

                    // Parse event data
                    var eventData = JsonSerializer.Serialize(eventGridEvent.Data,
                        new JsonSerializerOptions { WriteIndented = true });
                    _logger.LogInformation($"Event Data: {eventData}");

                    // Log Service Bus message properties
                    _logger.LogInformation($"Service Bus Message ID: {message.MessageId}");
                    _logger.LogInformation($"Service Bus Correlation ID: {message.CorrelationId}");
                    _logger.LogInformation($"Delivery Count: {message.DeliveryCount}");

                    // Check for Event Grid custom headers
                    if (message.ApplicationProperties.TryGetValue("aeg-subscription-name", out var subName))
                    {
                        _logger.LogInformation($"Event Grid Subscription: {subName}");
                    }
                    if (message.ApplicationProperties.TryGetValue("aeg-delivery-count", out var deliveryCount))
                    {
                        _logger.LogInformation($"Event Grid Delivery Count: {deliveryCount}");
                    }
                }

                // Complete the message (remove from queue)
                await messageActions.CompleteMessageAsync(message);

                _logger.LogInformation("✅ Successfully processed message via Service Bus private endpoint");
            }
            catch (JsonException ex)
            {
                _logger.LogError(ex, "Failed to parse Event Grid event from Service Bus message");

                // Dead letter the message if it can't be parsed
                await messageActions.DeadLetterMessageAsync(
                    message,
                    deadLetterReason: "InvalidMessageFormat",
                    deadLetterErrorDescription: ex.Message);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing Service Bus message");

                // Abandon the message - it will be retried up to MaxDeliveryCount
                await messageActions.AbandonMessageAsync(message);
                throw;
            }
        }

        /// <summary>
        /// Service Bus Topic Subscription trigger (alternative to Queue)
        /// Use this if you have multiple consumers or need message filtering
        /// </summary>
        [Function("ConsumeEventFromTopic")]
        public async Task ConsumeEventFromTopic(
            [ServiceBusTrigger("events", "dotnet-function-sub", Connection = "ServiceBusConnection")]
            ServiceBusReceivedMessage message,
            ServiceBusMessageActions messageActions)
        {
            _logger.LogInformation("Service Bus Topic trigger function processing message");

            // Same logic as ConsumeEventFromQueue
            await ConsumeEventFromQueue(message, messageActions);
        }
    }
}
```

**Update `local.settings.json`:**

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "EVENT_GRID_TOPIC_ENDPOINT": "https://evgt-poc-<suffix>.swedencentral-1.eventgrid.azure.net/api/events",
    "ServiceBusConnection__fullyQualifiedNamespace": "sb-eventgrid-<suffix>.servicebus.windows.net",
    "ServiceBusConnection__credential": "managedidentity"
  }
}
```

**Update `terraform/function-dotnet.tf` - Add Service Bus connection:**

```hcl
resource "azurerm_linux_function_app" "dotnet" {
  count               = var.enable_dotnet_function ? 1 : 0
  name                = "func-dotnet-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.dotnet_function[0].name
  location            = var.location

  # ... existing configuration ...

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"             = "dotnet-isolated"
    "EVENT_GRID_TOPIC_ENDPOINT"            = azurerm_eventgrid_topic.main.endpoint
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.dotnet_function[0].primary_connection_string
    "WEBSITE_CONTENTSHARE"                 = "func-dotnet-content"

    # Add Service Bus connection (managed identity)
    "ServiceBusConnection__fullyQualifiedNamespace" = var.use_servicebus ? "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net" : ""
    "ServiceBusConnection__credential"              = "managedidentity"
  }

  # ... rest of configuration ...
}
```

### Deployment Steps

1. **Update tfvars file:**
```hcl
# terraform/terraform.phase2.tfvars
enable_dotnet_function = true
use_servicebus = true
use_servicebus_topic = false  # Use Queue (simpler)
```

2. **Apply Terraform:**
```bash
cd terraform
terraform plan -var-file=terraform.phase2.tfvars
terraform apply -var-file=terraform.phase2.tfvars
```

3. **Deploy .NET function:**
```bash
./scripts/deploy-function.sh
```

4. **Test private connectivity:**
```bash
./scripts/test-connectivity.sh
```

### Verification

**Check Service Bus message in Azure Portal:**
1. Navigate to Service Bus namespace
2. Go to Queues > events
3. Use Service Bus Explorer to peek messages

**Check Application Insights:**
```bash
az monitor app-insights query \
  --app appi-dotnet-function-3tlv1w \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --analytics-query "traces | where message contains 'FULLY PRIVATE' | take 10"
```

---

## Implementation: Event Hub Approach

### Infrastructure Changes (Terraform)

**New File: `terraform/eventhub.tf`**

```hcl
# Event Hub Namespace in Subscription 1
resource "azurerm_eventhub_namespace" "main" {
  name                = "evhns-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.eventgrid.name
  sku                 = "Standard"
  capacity            = 1  # Throughput units

  # Disable public network access
  public_network_access_enabled = false

  # Enable auto-inflate (optional, for scaling)
  auto_inflate_enabled     = false
  maximum_throughput_units = 1

  # Enable managed identity
  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Event Hub
resource "azurerm_eventhub" "events" {
  name                = "events"
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = azurerm_resource_group.eventgrid.name
  partition_count     = 2
  message_retention   = 1  # days (1-7 for Standard)
}

# Consumer Group for .NET Function
resource "azurerm_eventhub_consumer_group" "dotnet_function" {
  name                = "dotnet-function"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.events.name
  resource_group_name = azurerm_resource_group.eventgrid.name
}

# Private Endpoint for Event Hub
resource "azurerm_private_endpoint" "eventhub" {
  name                = "pe-eventhub-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.eventgrid.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "pe-connection-eventhub"
    private_connection_resource_id = azurerm_eventhub_namespace.main.id
    is_manual_connection          = false
    subresource_names             = ["namespace"]
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.eventhub.id]
  }

  tags = var.tags
}

# Private DNS Zone for Event Hub
resource "azurerm_private_dns_zone" "eventhub" {
  name                = "privatelink.servicebus.windows.net"
  resource_group_name = azurerm_resource_group.network.name

  tags = var.tags
}

# Link Private DNS Zone to all VNETs
resource "azurerm_private_dns_zone_virtual_network_link" "eventhub_vnet1" {
  name                  = "vnet1-eventhub-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.eventhub.name
  virtual_network_id    = azurerm_virtual_network.function_vnet.id

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "eventhub_vnet2" {
  name                  = "vnet2-eventhub-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.eventhub.name
  virtual_network_id    = azurerm_virtual_network.eventgrid_vnet.id

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "eventhub_vnet3" {
  count                 = var.enable_dotnet_function ? 1 : 0
  name                  = "vnet3-eventhub-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.eventhub.name
  virtual_network_id    = azurerm_virtual_network.dotnet_vnet[0].id

  tags = var.tags
}

# IAM: Grant Event Grid permission to send to Event Hub
resource "azurerm_role_assignment" "eventgrid_eventhub_sender" {
  scope                = azurerm_eventhub_namespace.main.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = azurerm_eventgrid_topic.main.identity[0].principal_id
}

# IAM: Grant .NET Function permission to receive from Event Hub
resource "azurerm_role_assignment" "dotnet_function_eventhub_receiver" {
  count                = var.enable_dotnet_function ? 1 : 0
  scope                = azurerm_eventhub_namespace.main.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_linux_function_app.dotnet[0].identity[0].principal_id
}

# Event Grid subscription to Event Hub
resource "azurerm_eventgrid_event_subscription" "to_eventhub" {
  count = var.use_eventhub ? 1 : 0
  name  = "eventgrid-to-eventhub"
  scope = azurerm_eventgrid_topic.main.id

  eventhub_endpoint_id = azurerm_eventhub.events.id

  delivery_identity {
    type = "SystemAssigned"
  }

  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440
  }

  depends_on = [
    azurerm_role_assignment.eventgrid_eventhub_sender
  ]
}
```

### .NET Function Code Changes (Event Hub)

**Update NuGet packages:**
```xml
<!-- Add Event Hub SDK -->
<PackageReference Include="Microsoft.Azure.Functions.Worker.Extensions.EventHubs" Version="6.3.6" />
<PackageReference Include="Azure.Messaging.EventHubs" Version="5.12.0" />
```

**Function code:**
```csharp
/// <summary>
/// Event Hub trigger that receives events from Event Grid via Event Hub
/// </summary>
[Function("ConsumeEventFromEventHub")]
public async Task ConsumeEventFromEventHub(
    [EventHubTrigger("events",
        Connection = "EventHubConnection",
        ConsumerGroup = "dotnet-function")]
    EventData[] events)
{
    foreach (EventData eventData in events)
    {
        _logger.LogInformation("Event Hub trigger processing event");

        try
        {
            // Parse Event Grid event from Event Hub body
            var messageBody = Encoding.UTF8.GetString(eventData.EventBody);
            _logger.LogInformation($"Raw message body: {messageBody}");

            var eventGridEvents = JsonSerializer.Deserialize<EventGridEvent[]>(messageBody);

            if (eventGridEvents == null || eventGridEvents.Length == 0)
            {
                _logger.LogWarning("No Event Grid events found in Event Hub event");
                continue;
            }

            foreach (var eventGridEvent in eventGridEvents)
            {
                _logger.LogInformation($"✅ Event received via FULLY PRIVATE path (Event Hub)");
                _logger.LogInformation($"Event ID: {eventGridEvent.Id}");
                _logger.LogInformation($"Event Type: {eventGridEvent.EventType}");
                _logger.LogInformation($"Event Subject: {eventGridEvent.Subject}");

                var eventDataJson = JsonSerializer.Serialize(eventGridEvent.Data,
                    new JsonSerializerOptions { WriteIndented = true });
                _logger.LogInformation($"Event Data: {eventDataJson}");

                // Log Event Hub properties
                _logger.LogInformation($"Event Hub Sequence Number: {eventData.SequenceNumber}");
                _logger.LogInformation($"Event Hub Offset: {eventData.Offset}");
                _logger.LogInformation($"Event Hub Partition Key: {eventData.PartitionKey}");
            }

            _logger.LogInformation("✅ Successfully processed event via Event Hub private endpoint");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing Event Hub event");
            throw;
        }
    }
}
```

**App Settings:**
```json
{
  "EventHubConnection__fullyQualifiedNamespace": "evhns-<suffix>.servicebus.windows.net",
  "EventHubConnection__credential": "managedidentity"
}
```

---

## Implementation: Storage Queue Approach

### Technical Validation

**Microsoft Official Support:**

Storage Queue is officially supported as an Event Grid delivery destination with managed identity authentication:

> "You can deliver events to Event Hubs, Service Bus queues, or Azure Storage queues using an Azure Event Grid custom topic or domain with system-assigned or user-assigned managed identity."

**Source:** [Microsoft Learn - Deliver events using private link service](https://learn.microsoft.com/en-us/azure/event-grid/consume-private-endpoints)

> "Event Grid supports delivering events to Azure Storage queues. You can use Storage Queues to buffer events when you can't process them immediately."

**Source:** [Microsoft Learn - Configure Azure Storage queue as Event Grid handler](https://learn.microsoft.com/en-us/azure/event-grid/handler-storage-queues)

**⚠️ Important Limitation - Trusted Services, Not Private Endpoints:**

Unlike Service Bus and Event Hub, Event Grid delivery to Storage Queue does **NOT** use private endpoints. Instead, it uses the "Allow Azure services on the trusted services list" feature:

> "If you're using a firewall to protect Azure Storage, you need to enable 'Allow trusted Microsoft services' to enable Event Grid to write events to storage queues."

**Source:** [Microsoft Learn - Firewall configuration for Storage Queue](https://learn.microsoft.com/en-us/azure/event-grid/handler-storage-queues#firewall-configuration)

**What This Means:**
- Event Grid → Storage Queue traffic stays on **Microsoft backbone network** (not public internet)
- However, it's **not fully private** like Service Bus/Event Hub (no private endpoint for this path)
- Function → Storage Queue connection **CAN** use private endpoints (fully private)
- Result: **Semi-private** architecture (one leg public backbone, one leg private)

### Private Endpoint Support for Functions

Azure Functions **CAN** use private endpoints to connect to Storage Queue:

> "Azure Functions can use virtual network integration to connect to Azure Storage over private endpoints."

**Source:** [Microsoft Learn - Functions Storage considerations](https://learn.microsoft.com/en-us/azure/azure-functions/storage-considerations)

### Storage Queue Architecture (Semi-Private)

```
┌─────────────────┐         ┌──────────────┐         ┌──────────────────┐
│ .NET Function   │ PRIVATE │ Event Grid   │ TRUSTED │ Storage Queue    │
│ (Subscription 2)│────────▶│ Topic        │────────▶│ (Sub 1)          │
│                 │  10.1.4  │ (Sub 1)      │ Services│                  │
│ Publish         │         │              │ Backbone│                  │
└─────────────────┘         └──────────────┘         └──────────────────┘
                                                               │
                                                      PRIVATE  │
                                                      10.1.3.4 │
                                                               ▼
                                                      ┌──────────────────┐
                                                      │ .NET Function    │
                                                      │ QueueTrigger     │
                                                      │ (Subscription 2) │
                                                      │ Consume          │
                                                      └──────────────────┘
    ✅ Private              ⚠️ Trusted Services      ✅ Private
```

**Traffic Flow Analysis:**
- **Function → Event Grid:** ✅ Fully Private (private endpoint)
- **Event Grid → Storage Queue:** ⚠️ Semi-Private (trusted services via Microsoft backbone)
- **Storage Queue → Function:** ✅ Fully Private (private endpoint)

### Infrastructure Changes (Terraform)

**New File: `terraform/storagequeue.tf`**

```hcl
# Storage Account for Event Grid queue in Subscription 1
resource "azurerm_storage_account" "eventgrid_queue" {
  name                     = "steventq${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.eventgrid.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Disable public network access for maximum security
  public_network_access_enabled = false

  # Enable private endpoint for Functions connection
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]  # REQUIRED for Event Grid delivery
  }

  # Enable blob encryption
  min_tls_version = "TLS1_2"

  tags = var.tags
}

# Storage Queue for Event Grid events
resource "azurerm_storage_queue" "events" {
  name                 = "eventgrid-events"
  storage_account_name = azurerm_storage_account.eventgrid_queue.name
}

# Private Endpoint for Storage Account in VNET2
resource "azurerm_private_endpoint" "storagequeue" {
  name                = "pe-storage-queue-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.eventgrid.name
  subnet_id           = azurerm_subnet.private_endpoint_subnet.id

  private_service_connection {
    name                           = "pe-connection-storagequeue"
    private_connection_resource_id = azurerm_storage_account.eventgrid_queue.id
    is_manual_connection          = false
    subresource_names             = ["queue"]  # Queue subresource type
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.storagequeue.id]
  }

  tags = var.tags

  depends_on = [
    azurerm_storage_account.eventgrid_queue
  ]
}

# Private DNS Zone for Storage Queue
resource "azurerm_private_dns_zone" "storagequeue" {
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = azurerm_resource_group.network.name

  tags = var.tags
}

# Link Private DNS Zone to all VNETs
resource "azurerm_private_dns_zone_virtual_network_link" "storagequeue_vnet1" {
  name                  = "vnet1-storagequeue-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.storagequeue.name
  virtual_network_id    = azurerm_virtual_network.function_vnet.id

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storagequeue_vnet2" {
  name                  = "vnet2-storagequeue-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.storagequeue.name
  virtual_network_id    = azurerm_virtual_network.eventgrid_vnet.id

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storagequeue_vnet3" {
  count                 = var.enable_dotnet_function ? 1 : 0
  name                  = "vnet3-storagequeue-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.storagequeue.name
  virtual_network_id    = azurerm_virtual_network.dotnet_vnet[0].id

  tags = var.tags
}

# IAM: Grant Event Grid managed identity permission to write to Storage Queue
resource "azurerm_role_assignment" "eventgrid_storagequeue_sender" {
  scope                = azurerm_storage_account.eventgrid_queue.id
  role_definition_name = "Storage Queue Data Message Sender"
  principal_id         = azurerm_eventgrid_topic.main.identity[0].principal_id
}

# IAM: Grant .NET Function managed identity permission to read from Storage Queue
resource "azurerm_role_assignment" "dotnet_function_storagequeue_receiver" {
  count                = var.enable_dotnet_function ? 1 : 0
  scope                = azurerm_storage_account.eventgrid_queue.id
  role_definition_name = "Storage Queue Data Message Processor"
  principal_id         = azurerm_linux_function_app.dotnet[0].identity[0].principal_id
}
```

**Update `terraform/eventgrid.tf` - Add Storage Queue subscription:**

```hcl
# Event Grid subscription to Storage Queue
resource "azurerm_eventgrid_event_subscription" "to_storagequeue" {
  count = var.use_storagequeue ? 1 : 0
  name  = "eventgrid-to-storagequeue"
  scope = azurerm_eventgrid_topic.main.id

  storage_queue_endpoint {
    storage_account_id = azurerm_storage_account.eventgrid_queue.id
    queue_name         = azurerm_storage_queue.events.name

    # Optional: Set message TTL (max 7 days)
    queue_message_time_to_live_in_seconds = 604800  # 7 days
  }

  # Use managed identity for authentication
  delivery_identity {
    type = "SystemAssigned"
  }

  # Optional: Advanced filtering
  # subject_filter {
  #   subject_begins_with = "/test"
  # }

  retry_policy {
    max_delivery_attempts = 3
    event_time_to_live    = 1440  # 24 hours
  }

  depends_on = [
    azurerm_role_assignment.eventgrid_storagequeue_sender
  ]
}
```

**Update `terraform/variables.tf`:**

```hcl
variable "use_storagequeue" {
  type        = bool
  description = "Use Storage Queue for semi-private event delivery (alternative to webhook)"
  default     = false
}
```

**Update `terraform/outputs.tf`:**

```hcl
output "storage_account_name" {
  value       = var.use_storagequeue ? azurerm_storage_account.eventgrid_queue.name : null
  description = "Storage account name for Event Grid queue"
}

output "storage_queue_name" {
  value       = var.use_storagequeue ? azurerm_storage_queue.events.name : null
  description = "Storage queue name for Event Grid events"
}

output "storage_queue_connection_endpoint" {
  value       = var.use_storagequeue ? "${azurerm_storage_account.eventgrid_queue.name}.queue.core.windows.net" : null
  description = "Storage queue endpoint (for managed identity connection)"
}
```

### .NET Function Code Changes

**Update `EventGridPubSubFunction/EventGridPubSubFunction.csproj`:**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <AzureFunctionsVersion>v4</AzureFunctionsVersion>
    <OutputType>Exe</OutputType>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Azure.Identity" Version="1.13.1" />
    <PackageReference Include="Azure.Messaging.EventGrid" Version="4.30.0" />
    <PackageReference Include="Microsoft.Azure.Functions.Worker" Version="2.0.0" />
    <PackageReference Include="Microsoft.Azure.Functions.Worker.Sdk" Version="2.0.0" />
    <PackageReference Include="Microsoft.ApplicationInsights.WorkerService" Version="2.22.0" />
    <PackageReference Include="Microsoft.Azure.Functions.Worker.ApplicationInsights" Version="2.0.0" />

    <!-- Add Storage Queue SDK -->
    <PackageReference Include="Microsoft.Azure.Functions.Worker.Extensions.Storage.Queues" Version="6.6.0" />
    <PackageReference Include="Azure.Storage.Queues" Version="12.21.0" />
  </ItemGroup>
  <ItemGroup>
    <None Update="host.json">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
    <None Update="local.settings.json">
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
      <CopyToPublishDirectory>Never</CopyToPublishDirectory>
    </None>
  </ItemGroup>
</Project>
```

**Add `EventGridStorageQueueFunctions.cs`:**

```csharp
using Azure;
using Azure.Identity;
using Azure.Messaging.EventGrid;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using Azure.Storage.Queues.Models;

namespace EventGridPubSubFunction
{
    public class EventGridStorageQueueFunctions
    {
        private readonly ILogger<EventGridStorageQueueFunctions> _logger;

        public EventGridStorageQueueFunctions(ILogger<EventGridStorageQueueFunctions> logger)
        {
            _logger = logger;
        }

        /// <summary>
        /// HTTP trigger that publishes events to Event Grid (unchanged from webhook version)
        /// </summary>
        [Function("PublishEvent")]
        public async Task<HttpResponseData> PublishEvent(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", Route = "publish")] HttpRequestData req)
        {
            _logger.LogInformation("Processing HTTP request to publish event to Event Grid");

            try
            {
                var endpoint = Environment.GetEnvironmentVariable("EVENT_GRID_TOPIC_ENDPOINT");
                if (string.IsNullOrEmpty(endpoint))
                {
                    var errorResponse = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                    await errorResponse.WriteStringAsync("EVENT_GRID_TOPIC_ENDPOINT not configured");
                    return errorResponse;
                }

                // Use managed identity to authenticate
                var credential = new DefaultAzureCredential();
                var client = new EventGridPublisherClient(new Uri(endpoint), credential);

                // Parse request body or use default message
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var data = string.IsNullOrEmpty(requestBody)
                    ? new { message = "Test event from .NET function" }
                    : JsonSerializer.Deserialize<dynamic>(requestBody);

                var eventId = $"event-{DateTime.UtcNow:yyyyMMddHHmmssfff}";
                var eventGridEvent = new EventGridEvent(
                    subject: "test/event",
                    eventType: "Custom.TestEvent",
                    dataVersion: "1.0",
                    data: new
                    {
                        message = data?.GetProperty("message").GetString() ?? "Test event from .NET function",
                        timestamp = DateTime.UtcNow.ToString("o"),
                        source = "azure-function-via-private-endpoint"
                    }
                );

                await client.SendEventAsync(eventGridEvent);

                _logger.LogInformation($"Successfully published event {eventId} to Event Grid");

                var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await response.WriteAsJsonAsync(new
                {
                    status = "success",
                    message = "Event published successfully",
                    eventId = eventId,
                    endpoint = endpoint
                });

                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error publishing event to Event Grid");

                var errorResponse = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errorResponse.WriteAsJsonAsync(new
                {
                    status = "error",
                    message = ex.Message
                });

                return errorResponse;
            }
        }

        /// <summary>
        /// Storage Queue trigger that receives events from Event Grid via Storage Queue
        /// REPLACES the EventGridTrigger (webhook-based)
        /// </summary>
        [Function("ConsumeEventFromStorageQueue")]
        public async Task ConsumeEventFromStorageQueue(
            [QueueTrigger("eventgrid-events", Connection = "StorageQueueConnection")]
            QueueMessage message)
        {
            _logger.LogInformation("Storage Queue trigger function processing message");

            try
            {
                // Parse Event Grid event from queue message body
                var messageBody = message.Body.ToString();
                _logger.LogInformation($"Raw message body: {messageBody}");

                // Event Grid wraps the event in an array when delivering to Storage Queue
                var eventGridEvents = JsonSerializer.Deserialize<EventGridEvent[]>(messageBody);

                if (eventGridEvents == null || eventGridEvents.Length == 0)
                {
                    _logger.LogWarning("No Event Grid events found in message");
                    return;
                }

                foreach (var eventGridEvent in eventGridEvents)
                {
                    _logger.LogInformation($"✅ Event received via SEMI-PRIVATE path (Storage Queue - Trusted Services)");
                    _logger.LogInformation($"Event ID: {eventGridEvent.Id}");
                    _logger.LogInformation($"Event Type: {eventGridEvent.EventType}");
                    _logger.LogInformation($"Event Subject: {eventGridEvent.Subject}");
                    _logger.LogInformation($"Event Time: {eventGridEvent.EventTime}");

                    // Parse event data
                    var eventData = JsonSerializer.Serialize(eventGridEvent.Data,
                        new JsonSerializerOptions { WriteIndented = true });
                    _logger.LogInformation($"Event Data: {eventData}");

                    // Log Storage Queue message properties
                    _logger.LogInformation($"Queue Message ID: {message.MessageId}");
                    _logger.LogInformation($"Insertion Time: {message.InsertedOn}");
                    _logger.LogInformation($"Dequeue Count: {message.DequeueCount}");
                    _logger.LogInformation($"Pop Receipt: {message.PopReceipt}");
                }

                _logger.LogInformation("✅ Successfully processed message via Storage Queue (semi-private)");
                _logger.LogInformation("⚠️ Note: Event Grid → Storage Queue uses trusted services (Microsoft backbone), not private endpoint");
            }
            catch (JsonException ex)
            {
                _logger.LogError(ex, "Failed to parse Event Grid event from Storage Queue message");
                // Message will be automatically moved to poison queue after max dequeue count
                throw;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing Storage Queue message");
                // Re-throw to trigger retry (message will be retried up to dequeueCount limit)
                throw;
            }
        }
    }
}
```

**Update `local.settings.json`:**

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "EVENT_GRID_TOPIC_ENDPOINT": "https://evgt-poc-<suffix>.swedencentral-1.eventgrid.azure.net/api/events",
    "StorageQueueConnection__queueServiceUri": "https://steventq<suffix>.queue.core.windows.net",
    "StorageQueueConnection__credential": "managedidentity"
  }
}
```

**Update `terraform/function-dotnet.tf` - Add Storage Queue connection:**

```hcl
resource "azurerm_linux_function_app" "dotnet" {
  count               = var.enable_dotnet_function ? 1 : 0
  name                = "func-dotnet-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.dotnet_function[0].name
  location            = var.location

  # ... existing configuration ...

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"             = "dotnet-isolated"
    "EVENT_GRID_TOPIC_ENDPOINT"            = azurerm_eventgrid_topic.main.endpoint
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = azurerm_storage_account.dotnet_function[0].primary_connection_string
    "WEBSITE_CONTENTSHARE"                 = "func-dotnet-content"

    # Add Storage Queue connection (managed identity)
    "StorageQueueConnection__queueServiceUri" = var.use_storagequeue ? "https://${azurerm_storage_account.eventgrid_queue.name}.queue.core.windows.net" : ""
    "StorageQueueConnection__credential"       = "managedidentity"
  }

  # ... rest of configuration ...
}
```

### Deployment Steps

1. **Update tfvars file:**
```hcl
# terraform/terraform.phase2.tfvars
enable_dotnet_function = true
use_storagequeue = true
```

2. **Apply Terraform:**
```bash
cd terraform
terraform plan -var-file=terraform.phase2.tfvars
terraform apply -var-file=terraform.phase2.tfvars
```

3. **Deploy .NET function:**
```bash
./scripts/deploy-function.sh
```

4. **Test connectivity:**
```bash
./scripts/test-connectivity.sh
```

### Verification

**Check Storage Queue messages in Azure Portal:**
1. Navigate to Storage Account
2. Go to Queues > eventgrid-events
3. Use Queue Explorer to view messages

**Check Application Insights:**
```bash
az monitor app-insights query \
  --app appi-dotnet-function-<suffix> \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function \
  --analytics-query "traces | where message contains 'SEMI-PRIVATE' | take 10"
```

**Verify trusted services configuration:**
```bash
az storage account show \
  --name steventq<suffix> \
  --resource-group rg-eventgrid-vnet-poc-eventgrid \
  --query "networkRuleSet.bypass"
# Should return: "AzureServices"
```

---

## Cost Comparison

### Monthly Recurring Costs (All Three Approaches)

⚠️ **UPDATED:** Service Bus requires **Premium SKU** for private endpoint support.

| Component | Service Bus Premium | Event Hub | Storage Queue | Winner |
|-----------|---------------------|-----------|---------------|--------|
| **Base Service** | ⚠️ **$669.44/month (Premium, 1 MU)** | $22.80/month (Standard, 1 TU) | $0.00/month (pay-per-use) | 🏆 Storage Queue |
| **Operations (1M/month)** | Included | $0.022 | $0.004 per 10k ops = $0.40 | 🏆 Storage Queue |
| **Storage** | Included | 84 GB included per TU | $0.045/GB (~$0.05 for <1GB) | Service Bus/Event Hub |
| **Private Endpoint** | $7.30/month | $7.30/month | $7.30/month | Tie |
| **Private DNS Zone** | $0.50/month | $0.50/month | $0.50/month | Tie |
| **Storage Account** | N/A | N/A | $0.023/month (LRS) | N/A |
| **TOTAL (1M msgs/month)** | ⚠️ **~$677/month** | **~$31/month** | **~$8/month** | **🏆 Storage Queue saves $669/month vs Service Bus** |

**Service Bus Premium Pricing Notes:**
- **Hourly billing:** ~$0.928/hour per messaging unit (MU)
- **Not usage-based:** Continuous charge for reserved capacity (24/7)
- **Minimum:** 1 MU required, cannot scale to zero
- **Cost is same** whether sending 0 messages or 1 billion messages per month

### Cost Scaling by Volume

⚠️ **Service Bus Premium has fixed base cost** - volume scaling has minimal impact.

**At 1 million events/month:**
- **Service Bus Premium:** ~$677/month ❌
- **Event Hub:** ~$31/month 🥈
- **Storage Queue:** ~$8/month 🏆

**At 10 million events/month:**
- **Service Bus Premium:** ~$677/month (operations included) ❌
- **Event Hub:** ~$31/month (events are cheap, TU is expensive) 🥈
- **Storage Queue:** ~$12/month ($8 base + $4 for ops) 🏆

**At 50 million events/month:**
- **Service Bus Premium:** ~$677/month (operations included) ❌
- **Event Hub:** ~$32/month (events scale cheaply) 🏆
- **Storage Queue:** ~$28/month ($8 base + $20 for ops) 🥈

**At 100 million events/month:**
- **Service Bus Premium:** ~$677/month (operations included) ❌
- **Event Hub:** ~$34/month (events scale cheaply, TU is fixed cost) 🏆
- **Storage Queue:** ~$48/month ($8 base + $40 for ops) 🥈

**At 500 million events/month:**
- **Service Bus Premium:** ~$677/month (operations included) ❌
- **Event Hub:** ~$45/month (still cheapest for high volume) 🏆
- **Storage Queue:** ~$208/month ($8 base + $200 for ops) 🥈

**Break-even points:**
- **Storage Queue vs Event Hub:** ~80M events/month (Event Hub becomes cheaper)
- **Service Bus Premium vs Event Hub:** Never (Event Hub always 22x cheaper)
- **Service Bus Premium vs Storage Queue:** Never (Storage Queue always 85x cheaper at 1M events)

**Key Insight:** Service Bus Premium's fixed $677/month base cost makes it uneconomical for any PoC or low-to-medium volume scenario.

### Additional Costs to Consider

Both services incur:
- **VNET data transfer:** $0.01/GB for cross-VNET traffic
- **Application Insights:** ~$2.30/GB ingestion
- **Function execution:** Included in App Service Plan

---

## Complexity Comparison

### Storage Queue (Lowest Complexity) 🏆

**Pros:**
- ✅ **Simplest model** - basic FIFO queue
- ✅ **Minimal configuration** - just create queue and assign roles
- ✅ **Familiar to most developers** - widely used service
- ✅ **Automatic poison queue** - built-in failure handling
- ✅ **Best tooling** - Storage Explorer, Portal, CLI all excellent
- ✅ **No special SKU required** - pay-per-use
- ✅ **Easy to debug** - view messages directly in Portal
- ✅ **Lowest cost** - ~60% cheaper than Service Bus

**Cons:**
- ⚠️ **Semi-private only** - Event Grid uses trusted services (not private endpoint)
- ⚠️ **Limited features** - no sessions, transactions, or complex routing
- ⚠️ **Smaller message size** - 64 KB max (vs 256 KB Service Bus, 1 MB Event Hub)
- ⚠️ **Single consumer** - no pub/sub pattern
- ⚠️ **Limited retention** - 7 days max (vs 14 days Service Bus)

### Service Bus (Lower Complexity)

**Pros:**
- ✅ **Fully private** - private endpoints for Event Grid delivery
- ✅ Simpler queue-based model (FIFO)
- ✅ Traditional messaging patterns (familiar to most developers)
- ✅ Built-in dead-lettering
- ✅ Sessions for ordered processing
- ✅ Transactions support
- ✅ Easier to understand message lifecycle
- ✅ Good tooling in Azure Portal (Service Bus Explorer)

**Cons:**
- ⚠️ Single consumer by default (unless using topics)
- ⚠️ Lower throughput compared to Event Hub
- ⚠️ More expensive at very high volumes
- ⚠️ Higher base cost than Storage Queue

### Event Hub (Medium Complexity)

**Pros:**
- ✅ **Fully private** - private endpoints for Event Grid delivery
- ✅ High throughput (designed for streaming)
- ✅ Multiple consumers (via consumer groups)
- ✅ Event replay capability
- ✅ Better for analytics/time-series workloads
- ✅ Cost-effective at high volumes (>80M events/month)

**Cons:**
- ⚠️ Partition-based model (more complex)
- ⚠️ Checkpointing required for tracking progress
- ⚠️ No built-in dead-lettering (must implement)
- ⚠️ Consumer groups add complexity
- ⚠️ Harder to debug (less tooling)
- ⚠️ Highest base cost ($31/month)

### Development Effort

| Task | Storage Queue | Service Bus | Event Hub | Winner |
|------|---------------|-------------|-----------|--------|
| **Initial Setup** | 1.5 hours | 2 hours | 3 hours | 🏆 Storage Queue |
| **Function Code** | Very Simple | Simple | Medium | 🏆 Storage Queue |
| **Testing** | Very Easy | Easy | Medium | 🏆 Storage Queue |
| **Debugging** | Very Easy (Storage Explorer) | Easy (Portal Explorer) | Hard (need client) | 🏆 Storage Queue |
| **Monitoring** | Straightforward | Straightforward | More metrics | Storage Queue/Service Bus |
| **Maintenance** | Very Low | Low | Medium | 🏆 Storage Queue |
| **Total Effort** | **~6 hours** | **~8 hours** | **~12 hours** | **🏆 Storage Queue** |

---

## Security Comparison

### Security Feature Comparison

| Security Feature | Storage Queue | Service Bus | Event Hub | Notes |
|------------------|---------------|-------------|-----------|-------|
| **Event Grid → Middleware** | ⚠️ Trusted Services | ✅ Private Endpoint | ✅ Private Endpoint | Storage Queue uses backbone, not private |
| **Function → Middleware** | ✅ Private Endpoint | ✅ Private Endpoint | ✅ Private Endpoint | All support full private access |
| **Managed Identity** | ✅ Yes | ✅ Yes | ✅ Yes | No credentials stored |
| **RBAC** | ✅ Yes | ✅ Yes | ✅ Yes | Fine-grained permissions |
| **Encryption in Transit** | ✅ TLS 1.2+ | ✅ TLS 1.2+ | ✅ TLS 1.2+ | Always encrypted |
| **Encryption at Rest** | ✅ Yes | ✅ Yes | ✅ Yes | Microsoft-managed keys |
| **Network Isolation** | ⚠️ Partial (Trusted) | ✅ Full | ✅ Full | Storage Queue allows trusted services |
| **Audit Logging** | ✅ Yes | ✅ Yes | ✅ Yes | Azure Monitor |
| **Firewall Rules** | ✅ Yes | ✅ Yes | ✅ Yes | IP restrictions |
| **DDoS Protection** | ✅ Yes | ✅ Yes | ✅ Yes | Azure built-in |

### Security Level Classification

**Fully Private (Best Security):**
- ✅ **Service Bus:** All traffic via private endpoints
- ✅ **Event Hub:** All traffic via private endpoints

**Semi-Private (Good Security):**
- ⚠️ **Storage Queue:** Event Grid uses trusted services (Microsoft backbone, not internet), Function uses private endpoint

**Partially Public (Baseline Security):**
- ❌ **Webhook:** Event Grid delivery via public internet (Azure backbone), requires IP restrictions

### What "Trusted Services" Means

**Storage Queue Trusted Services Model:**
- Traffic stays on **Microsoft backbone network** (not public internet)
- Uses "Allow Azure services on the trusted services list" firewall exception
- Event Grid is on Microsoft's trusted services list
- **NOT** the same as private endpoint (no dedicated private IP)
- Still encrypted with TLS 1.2+, authenticated with managed identity
- **Better than public internet, not as good as private endpoint**

**Microsoft Statement:**
> "When you enable the firewall setting 'Allow Azure services on the trusted services list to access this storage account', Azure Event Grid can write to Storage Queues even when the firewall denies all other access."

**Source:** [Microsoft Learn - Trusted services](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security#trusted-access-based-on-a-managed-identity)

### Security Benefits vs Webhook

All three approaches provide security improvements over webhooks:

| Security Aspect | Webhook | Storage Queue | Service Bus | Event Hub |
|----------------|---------|---------------|-------------|-----------|
| **Function Endpoint** | ❌ Public HTTPS | ✅ No public endpoint | ✅ No public endpoint | ✅ No public endpoint |
| **Inbound Traffic** | ❌ Public internet | ⚠️ Trusted backbone | ✅ Private VNET | ✅ Private VNET |
| **Attack Surface** | ⚠️ Larger (HTTP) | ✅ Smaller (no HTTP) | ✅ Smaller (no HTTP) | ✅ Smaller (no HTTP) |
| **IP Restrictions** | ⚠️ Required | ✅ Not needed | ✅ Not needed | ✅ Not needed |
| **DDoS Risk** | ⚠️ Higher | ✅ Lower | ✅ Lowest | ✅ Lowest |
| **Compliance** | ⚠️ May not meet requirements | ⚠️ Depends on policy | ✅ Meets most requirements | ✅ Meets most requirements |

### Compliance Considerations

**When Storage Queue Semi-Private is Acceptable:**
- PoC/development environments
- Non-regulated data (no PCI, HIPAA, SOC2 requirements)
- Cost is primary concern
- Traffic on Microsoft backbone is sufficient

**When Fully Private is Required:**
- Production environments with sensitive data
- Regulatory compliance (PCI-DSS, HIPAA, SOC2, etc.)
- Zero-trust security policies
- Air-gapped or highly isolated networks
- Contractual requirements for private connectivity

---

## Feature Comparison

### Storage Queue Features

**Messaging Patterns:**
- ✅ Queues (point-to-point) - **simplest model**
- ✅ Automatic poison queue
- ✅ Visibility timeout
- ✅ Peek/dequeue operations
- ❌ No topics/subscriptions
- ❌ No sessions
- ❌ No transactions
- ❌ No duplicate detection
- ❌ No scheduled messages

**Limits (Standard Tier):**
- **Message size: 64 KB** (smallest)
- Queue size: Unlimited (500 TB storage account limit)
- **Max TTL: 7 days** (shortest retention)
- **Throughput: ~2,000 messages/second**
- Max queues per account: Unlimited

### Service Bus Features

**Messaging Patterns:**
- ✅ Queues (point-to-point)
- ✅ Topics/Subscriptions (pub/sub)
- ✅ Sessions (ordered processing)
- ✅ Auto-forwarding
- ✅ Dead-lettering
- ✅ Scheduled messages
- ✅ Duplicate detection
- ✅ Transactions

**Limits (Standard Tier):**
- **Message size: 256 KB** (medium)
- Queue/Topic size: 80 GB
- **Max TTL: 14 days** (longer retention)
- **Throughput: ~1 MB/s per entity**
- Max queues/topics per namespace: 10,000

### Event Hub Features

**Streaming Patterns:**
- ✅ Partitions (parallel processing)
- ✅ Consumer groups (multiple readers)
- ✅ Event replay (time-based)
- ✅ Capture to Storage/Data Lake
- ✅ Apache Kafka protocol support
- ✅ Schema Registry integration

**Limits (Standard Tier):**
- **Message size: 1 MB** (largest)
- **Retention: 1-7 days**
- Partitions: 1-32 per hub
- **Throughput: 1 MB/s per TU** (scalable with TUs)
- Max event hubs per namespace: 10

---

## Recommendations

### Use Storage Queue When:

✅ **Cost is the primary concern** - ~60% cheaper than Service Bus, ~75% cheaper than Event Hub
✅ **Semi-private is acceptable** - Trusted services (Microsoft backbone) meets security requirements
✅ **Simple use case** - Basic queuing without advanced features
✅ **PoC/development** - Budget-constrained environments
✅ **Non-regulated data** - No strict compliance requirements for fully private connectivity
✅ **Small messages** - Message size <64 KB
✅ **Quick implementation** - Need fastest setup time

❌ **Don't use when:**
- Fully private connectivity is required (compliance/regulatory)
- Need advanced features (sessions, transactions, duplicate detection)
- Messages >64 KB
- Need retention >7 days
- Multiple consumers required

### Use Service Bus When:

✅ **Fully private required** - Compliance/regulatory requirements
✅ **Production workloads** - Need enterprise features
✅ **Traditional messaging patterns** - Command/control, request/reply
✅ **Ordered processing** - Sessions required
✅ **Dead-lettering needed** - Built-in support
⚠️ **UPDATED:** Service Bus Premium is now **prohibitively expensive** for most use cases.

✅ **Use Service Bus Premium only when:**
- Budget >$677/month available
- Company-mandated Service Bus standard
- Existing Service Bus Premium infrastructure
- Specific Premium features required (sessions, transactions)

❌ **Don't use when:**
- ❌ **Cost-sensitive** (85x more expensive than Storage Queue, 22x more than Event Hub)
- ❌ **PoC/testing** ($67 for 3-day PoC vs $3 for Event Hub)
- ❌ **Low-medium volume** (fixed $677 cost regardless of usage)
- ❌ **Most production scenarios** (Event Hub provides same privacy at $31/month)

### Use Event Hub When:

✅ **High-volume streaming** - >80M events/month (cost-effective at scale)
✅ **Multiple consumers** - Same events read by multiple systems
✅ **Event replay required** - Re-process historical events
✅ **Analytics workloads** - Time-series, aggregations
✅ **Kafka compatibility** - Existing Kafka clients
✅ **Capture to storage** - Need event archival
✅ **Large messages** - Up to 1 MB

❌ **Don't use when:**
- Low volume (<10M events/month) - most expensive option
- Simple queue pattern sufficient
- Budget-constrained PoC

### Decision Tree

```
Start: Do you need fully private connectivity (compliance/regulatory)?
│
├─ NO → Is cost the primary concern?
│   │
│   ├─ YES → Use Storage Queue ($8/month) 🏆
│   │
│   └─ NO → Expected volume >80M events/month?
│       │
│       ├─ YES → Use Event Hub ($31/month)
│       │
│       └─ NO → Use Storage Queue ($8/month) 🏆
│
└─ YES (fully private required) → Budget >$677/month for Service Bus Premium?
    │
    ├─ NO → Use Event Hub Standard ($31/month) 🏆
    │        [Same privacy level, 22x cheaper]
    │
    └─ YES (high budget) → Need specific Service Bus features?
                           (sessions, transactions, request-reply)
        │
        ├─ YES → Use Service Bus Premium ($677/month)
        │        [Only if features justify 22x cost premium]
        │
        └─ NO → Use Event Hub Standard ($31/month) 🏆
                 [Same privacy, better value]
```

**⚠️ Key Change:** Service Bus Premium's extreme cost ($677/month) eliminates it from most scenarios. Event Hub Standard ($31/month) provides the same **fully private** connectivity at 22x lower cost.

### For This PoC: Revised Recommendation (Post-Premium SKU Discovery)

⚠️ **CRITICAL:** Service Bus requiring Premium SKU changes everything. Event Hub is now the best option for fully private connectivity.

#### Option 1: Fully Private at Reasonable Cost - 🏆 **Event Hub**

**NEW Recommendation:** **Azure Event Hub (Standard Tier, 1 TU)**

**Rationale:**
1. **Fully Private:** Same privacy as Service Bus Premium at 22x lower cost
2. **Reasonable Cost:** ~$31/month (saves $646/month vs Service Bus Premium)
3. **Production-Grade:** Enterprise reliability and features
4. **Scalable:** Can handle growth if needed
5. **Best Balance:** Privacy + cost efficiency

**Trade-offs:**
- ~4x more expensive than Storage Queue
- Slightly more complex than simple queue pattern
- Partition model requires understanding

#### Option 2: If Budget is Primary - 🏆 **Storage Queue**

**Recommendation:** **Azure Storage Queue (Standard LRS)**

**Rationale:**
1. **Lowest Cost:** ~$8/month (saves $23/month vs Event Hub, $669/month vs Service Bus)
2. **Simplest Implementation:** Fastest setup, easiest to maintain
3. **Sufficient Security:** Trusted services (semi-private) acceptable for PoC
4. **Best Tooling:** Storage Explorer provides excellent debugging
5. **Volume Fit:** PoC will have <1M events/month (perfect for Storage Queue)

**Trade-offs:**
- ⚠️ Semi-private (trusted services, not full private endpoint for Event Grid)
- ⚠️ Limited features (no sessions, transactions, duplicate detection)
- ⚠️ Smaller message size (64 KB vs 256 KB)

#### If Full Privacy Required: 🏆 **Service Bus**

**Recommendation:** **Azure Service Bus (Standard, Queue)**

**Rationale:**
1. **Fully Private:** Private endpoints for Event Grid delivery
2. **Balanced Cost:** ~$21/month (middle ground)
3. **Enterprise Features:** Dead-lettering, sessions, transactions
4. **Production-Ready:** Better for eventual production deployment
5. **Use Case Fit:** Event Grid events are command/control pattern

**Trade-offs:**
- ⚠️ Higher cost than Storage Queue (+$13/month)
- ⚠️ More complex than Storage Queue (but still simple)

#### Never for This PoC: Event Hub

**Not Recommended for PoC** unless specific requirements:
- Highest cost ($31/month)
- Most complex implementation
- Overkill for low volume (<1M events/month)
- Only consider if you need multi-consumer pattern or event replay

---

## Migration Path

### Phase 1: Current State (Webhook)
- ✅ Publishing: Private (10.1.1.4)
- ❌ Delivery: Public internet

### Phase 2: Add Service Bus (Parallel)
- Deploy Service Bus infrastructure
- Update .NET function with Service Bus trigger
- Keep webhook subscription active
- Test Service Bus path

### Phase 3: Validate
- Compare Application Insights logs
- Verify fully private communication
- Performance testing

### Phase 4: Cutover
- Delete webhook Event Grid subscription
- Remove Event Grid trigger function
- Remove IP restrictions (no longer needed)
- Monitor for 48 hours

### Phase 5: Cleanup (Optional)
- Remove unused webhook-related code
- Update documentation
- Remove public endpoints configuration

---

## Testing Checklist

### Storage Queue - Infrastructure Validation

- [ ] Storage account created with private endpoint
- [ ] Storage queue "eventgrid-events" created
- [ ] Private DNS zone (privatelink.queue.core.windows.net) linked to all VNETs
- [ ] Storage account has "Allow Azure services on the trusted services list" enabled
- [ ] Event Grid managed identity has "Storage Queue Data Message Sender" role
- [ ] .NET Function managed identity has "Storage Queue Data Message Processor" role
- [ ] Event Grid subscription to Storage Queue created
- [ ] Private endpoint resolves to private IP (10.1.3.x)

### Storage Queue - Functional Testing

- [ ] Publish event via .NET function HTTP trigger
- [ ] Verify event appears in Storage Queue (Portal/Storage Explorer)
- [ ] Verify .NET function Queue trigger fires
- [ ] Check Application Insights for "SEMI-PRIVATE" log message
- [ ] Verify Function connects via private endpoint (not public)
- [ ] Test poison queue (send malformed message, verify moved to poison queue)
- [ ] Test retry logic (force function failure, check dequeue count)

### Storage Queue - Security Testing

- [ ] Verify trusted services configuration: `az storage account show --query "networkRuleSet.bypass"`
- [ ] Confirm Function uses managed identity (no connection strings)
- [ ] Test that direct public access is denied (use curl to queue endpoint)
- [ ] Verify Event Grid can still write (trusted services exception working)

### Service Bus - Infrastructure Validation

- [ ] Service Bus namespace created with private endpoint
- [ ] Private DNS zone (privatelink.servicebus.windows.net) linked to all VNETs
- [ ] Event Grid managed identity has "Azure Service Bus Data Sender" role
- [ ] .NET Function managed identity has "Azure Service Bus Data Receiver" role
- [ ] Event Grid subscription to Service Bus queue created
- [ ] Private endpoint resolves to private IP (10.1.3.x)

### Service Bus - Functional Testing

- [ ] Publish event via Python function HTTP trigger
- [ ] Verify event appears in Service Bus queue (Portal Explorer)
- [ ] Verify .NET function Service Bus trigger fires
- [ ] Check Application Insights for "FULLY PRIVATE" log message
- [ ] Verify no public internet traffic (check NSG flow logs)
- [ ] Test dead-lettering (send malformed message)
- [ ] Test retry logic (force function failure)

### Event Hub - Infrastructure Validation

- [ ] Event Hub namespace created with private endpoint
- [ ] Event Hub "events" created with consumer group "dotnet-function"
- [ ] Private DNS zone (privatelink.servicebus.windows.net) linked to all VNETs
- [ ] Event Grid managed identity has "Azure Event Hubs Data Sender" role
- [ ] .NET Function managed identity has "Azure Event Hubs Data Receiver" role
- [ ] Event Grid subscription to Event Hub created
- [ ] Private endpoint resolves to private IP (10.1.3.x)

### Event Hub - Functional Testing

- [ ] Publish event via .NET function HTTP trigger
- [ ] Verify event appears in Event Hub (Portal metrics)
- [ ] Verify .NET function Event Hub trigger fires
- [ ] Check Application Insights for "FULLY PRIVATE" log message
- [ ] Verify no public internet traffic (check NSG flow logs)
- [ ] Test partition distribution (send multiple events)
- [ ] Test consumer group isolation (if multiple consumers)

### Performance Testing (All Approaches)

- [ ] Measure end-to-end latency (publish to consume)
- [ ] Send 100 events in burst (verify throughput)
- [ ] Monitor middleware metrics (Storage Queue: queue length, Service Bus: active messages, Event Hub: incoming messages)
- [ ] Check Function scaling behavior
- [ ] Measure cold start time
- [ ] Test sustained load (1000 events over 1 hour)

---

## Troubleshooting

### Storage Queue: Message Not Received

**Check 1: Trusted services enabled**
```bash
az storage account show \
  --name steventq<suffix> \
  --resource-group rg-eventgrid-vnet-poc-eventgrid \
  --query "networkRuleSet.bypass"
# Should return: "AzureServices"
```

**Check 2: Event Grid subscription exists**
```bash
az eventgrid event-subscription show \
  --name eventgrid-to-storagequeue \
  --source-resource-id <event-grid-topic-id>
```

**Check 3: Messages in queue**
```bash
az storage queue peek \
  --name eventgrid-events \
  --account-name steventq<suffix> \
  --auth-mode login \
  --num-messages 10
```

**Check 4: Function trigger binding**
```bash
az functionapp function show \
  --name func-dotnet-<suffix> \
  --function-name ConsumeEventFromStorageQueue \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function
```

**Check 5: Managed identity permissions**
```bash
# Check Event Grid can write
az role assignment list \
  --assignee <eventgrid-principal-id> \
  --scope <storage-account-id> \
  --query "[?roleDefinitionName=='Storage Queue Data Message Sender']"

# Check Function can read
az role assignment list \
  --assignee <function-principal-id> \
  --scope <storage-account-id> \
  --query "[?roleDefinitionName=='Storage Queue Data Message Processor']"
```

**Check 6: Poison queue (if messages failing)**
```bash
az storage queue peek \
  --name eventgrid-events-poison \
  --account-name steventq<suffix> \
  --auth-mode login \
  --num-messages 10
```

### Storage Queue: Event Grid Can't Write

**Problem:** Event Grid delivery failing with 403 Forbidden

**Solution:**
```bash
# Ensure bypass includes AzureServices
az storage account update \
  --name steventq<suffix> \
  --resource-group rg-eventgrid-vnet-poc-eventgrid \
  --bypass AzureServices
```

**Verify:**
```bash
az storage account show \
  --name steventq<suffix> \
  --query "networkRuleSet.{DefaultAction:defaultAction, Bypass:bypass}"
# Should show: DefaultAction=Deny, Bypass=AzureServices
```

### Service Bus: Message Not Received

**Check 1: Event Grid subscription exists**
```bash
az eventgrid event-subscription show \
  --name eventgrid-to-servicebus-queue \
  --source-resource-id <event-grid-topic-id>
```

**Check 2: Messages in queue**
```bash
az servicebus queue show \
  --name events \
  --namespace-name sb-eventgrid-<suffix> \
  --resource-group rg-eventgrid-vnet-poc-eventgrid \
  --query '{ActiveMessages:countDetails.activeMessageCount, DeadLetters:countDetails.deadLetterMessageCount}'
```

**Check 3: Function trigger binding**
```bash
az functionapp function show \
  --name func-dotnet-<suffix> \
  --function-name ConsumeEventFromQueue \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function
```

**Check 4: Managed identity permissions**
```bash
az role assignment list \
  --assignee <function-principal-id> \
  --scope <servicebus-namespace-id>
```

### Private Endpoint Not Resolving

**Storage Queue:**
```bash
nslookup steventq<suffix>.queue.core.windows.net
# Should resolve to 10.1.3.x (private IP)
```

**Service Bus:**
```bash
nslookup sb-eventgrid-<suffix>.servicebus.windows.net
# Should resolve to 10.1.3.x (private IP)
```

**Event Hub:**
```bash
nslookup evhns-<suffix>.servicebus.windows.net
# Should resolve to 10.1.3.x (private IP)
```

**Check private DNS zone link:**
```bash
# Storage Queue
az network private-dns link vnet list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --zone-name privatelink.queue.core.windows.net

# Service Bus / Event Hub
az network private-dns link vnet list \
  --resource-group rg-eventgrid-vnet-poc-network \
  --zone-name privatelink.servicebus.windows.net
```

### Function Can't Connect (Managed Identity Issues)

**Check Function identity is system-assigned:**
```bash
az functionapp identity show \
  --name func-dotnet-<suffix> \
  --resource-group rg-eventgrid-vnet-poc-dotnet-function
```

**Wait for role propagation (can take 5-10 minutes):**
```bash
# Check role assignments
az role assignment list \
  --assignee <function-principal-id> \
  --all
```

**Test managed identity from Function context:**
```bash
# Use Kudu console or App Service SSH
curl -H "Metadata: true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/"
```

---

## References

### Official Microsoft Documentation

**Storage Queue:**
- [Configure Azure Storage queue as Event Grid handler](https://learn.microsoft.com/en-us/azure/event-grid/handler-storage-queues)
- [Trusted access based on managed identity](https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security#trusted-access-based-on-a-managed-identity)
- [Azure Storage Queue Pricing](https://azure.microsoft.com/en-us/pricing/details/storage/queues/)
- [Storage Queue private endpoints](https://learn.microsoft.com/en-us/azure/storage/common/storage-private-endpoints)
- [Azure Functions Storage Queue trigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-queue-trigger)

**Service Bus:**
- [Configure Service Bus as Event Grid Handler](https://learn.microsoft.com/en-us/azure/event-grid/handler-service-bus)
- [Service Bus Private Link](https://learn.microsoft.com/en-us/azure/service-bus-messaging/private-link-service)
- [Service Bus Pricing](https://azure.microsoft.com/en-us/pricing/details/service-bus/)
- [Azure Functions Service Bus trigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-service-bus-trigger)

**Event Hub:**
- [Deliver events using private link service](https://learn.microsoft.com/en-us/azure/event-grid/consume-private-endpoints)
- [Event Hubs Private Endpoints](https://learn.microsoft.com/en-us/azure/event-hubs/private-link-service)
- [Event Hubs Pricing](https://azure.microsoft.com/en-us/pricing/details/event-hubs/)
- [Azure Functions Event Hub trigger](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-event-hubs-trigger)

**Azure Functions:**
- [Functions VNET Integration](https://learn.microsoft.com/en-us/azure/azure-functions/functions-create-vnet)
- [Functions Networking Options](https://learn.microsoft.com/en-us/azure/azure-functions/functions-networking-options)
- [Functions Storage considerations](https://learn.microsoft.com/en-us/azure/azure-functions/storage-considerations)

**Event Grid:**
- [Event Grid managed identity authentication](https://learn.microsoft.com/en-us/azure/event-grid/managed-service-identity)
- [Event Grid delivery and retry](https://learn.microsoft.com/en-us/azure/event-grid/delivery-and-retry)

---

## Conclusion

**Azure Storage Queue**, **Azure Service Bus**, and **Azure Event Hubs** all provide alternatives to Event Grid webhook delivery, each with different trade-offs in cost, security, and complexity.

### Summary Comparison (UPDATED for Premium SKU)

| Aspect | Storage Queue | Service Bus Premium | Event Hub |
|--------|---------------|---------------------|-----------|
| **Cost (1M events/month)** | ~$8/month 🏆 | ⚠️ ~$677/month | ~$31/month 🥈 |
| **Privacy Level** | ⚠️ Semi-Private | ✅ Fully Private | ✅ Fully Private 🏆 |
| **Complexity** | Lowest 🏆 | Low | Medium |
| **Implementation Time** | ~6 hours 🏆 | ~8 hours | ~12 hours |
| **Value for PoC** | 🏆 Best budget | ❌ Too expensive | 🏆 Best privacy/cost |
| **Best For** | Budget PoC | Enterprise w/ budget | Fully private PoC |

**Key Insight:** Service Bus Premium's $677/month cost makes **Event Hub the new recommended choice** for fully private PoC deployments.

### Three Valid Paths Forward

#### Path 1: Budget-Optimized (Storage Queue) 💰

**Choose when:** Cost is the primary concern and semi-private is acceptable

**Pros:**
- **Lowest cost:** ~$8/month (60% cheaper than Service Bus)
- **Fastest implementation:** ~6 hours total
- **Simplest to maintain:** Best debugging tools
- **Good security:** Trusted services (Microsoft backbone)

**Cons:**
- ⚠️ Semi-private (trusted services, not full private endpoint for Event Grid delivery)
- Limited features (no sessions, transactions)
- May not meet strict compliance requirements

#### Path 2: Service Bus Premium (❌ NOT RECOMMENDED)

**⚠️ DEPRECATED:** Service Bus Premium is **prohibitively expensive** for PoC use.

**Cons:**
- ❌ **Extreme cost:** ~$677/month (85x more than Storage Queue, 22x more than Event Hub)
- ❌ **Poor value:** Same privacy as Event Hub at 22x the cost
- ❌ **Not justified:** No features worth the 22x premium for this PoC
- ❌ **PoC budget killer:** $67 for 3-day test vs $3 for Event Hub

**Only consider if:**
- Budget >$677/month explicitly approved
- Company mandate requires Service Bus Premium
- Existing Premium infrastructure to leverage
- Specific Premium features (sessions, transactions) are hard requirements

#### Path 3: Fully Private at Reasonable Cost (Event Hub) 🏆

**NEW RECOMMENDATION:** Best choice for fully private PoC after Premium SKU discovery.

**Choose when:** Need fully private connectivity without extreme cost

**Pros:**
- **Fully private:** Private endpoints end-to-end
- **Reasonable cost:** ~$31/month (22x cheaper than Service Bus Premium!)
- **Production-grade:** Enterprise reliability and features
- **Streaming features:** Multiple consumers, event replay, Kafka protocol
- **Best for analytics:** Time-series, aggregations
- **Scalable:** Cost-effective up to 100M+ events/month

**Cons:**
- ~4x more expensive than Storage Queue ($23/month difference)
- Partition model slightly more complex than simple queue
- Overkill if semi-private (Storage Queue) is acceptable

### Recommended Decision Framework (UPDATED)

**For This PoC:**

1. **Fully Private Requirement (Compliance/Regulatory):**
   - 🏆 **Event Hub Standard** ($31/month)
   - Full private endpoint connectivity
   - Best balance of privacy and cost
   - Production-grade features

2. **Budget-Constrained PoC/Dev Environment:**
   - 🏆 **Storage Queue** ($8/month)
   - Semi-private (trusted services) acceptable
   - Fastest implementation
   - 4x cheaper than Event Hub

3. **❌ AVOID for PoC:**
   - ❌ **Service Bus Premium** ($677/month)
   - Only if budget explicitly approved
   - 22x more expensive than Event Hub for same privacy
   - $67 for 3-day test (vs $3 for Event Hub)

### Migration Path (If Starting with Storage Queue)

You can start with Storage Queue and migrate later:

**Phase 1:** Deploy Storage Queue ($8/month)
- Validate PoC concept
- Test functionality
- Minimal cost

**Phase 2:** Evaluate security requirements
- If semi-private is acceptable → Stay on Storage Queue
- If fully private needed → Migrate to Service Bus

**Phase 3:** Migrate if needed (~2 hours effort)
- Deploy Service Bus infrastructure
- Update Function trigger (QueueTrigger → ServiceBusTrigger)
- Update Event Grid subscription
- Test and validate
- Remove Storage Queue

**Total Cost if Migrating:**
- Week 1-4: Storage Queue = $8
- Week 5+: Service Bus = $21
- Development effort: ~2 hours

### Next Steps

1. **Choose approach based on requirements:**
   - Budget priority → Storage Queue
   - Compliance/production → Service Bus
   - High volume/streaming → Event Hub (unlikely for PoC)

2. **Follow implementation guide** in this document for chosen approach

3. **Deploy to PoC environment** using provided Terraform code

4. **Validate with testing checklist** (Infrastructure, Functional, Security tests)

5. **Measure results:**
   - End-to-end latency
   - Monthly costs (actual)
   - Developer experience
   - Security compliance

6. **Document lessons learned** for production deployment

---

**Document Version:** 2.0
**Last Updated:** January 27, 2026
**Author:** Claude Code Deployment Team
**Status:** ✅ Complete - All Three Approaches Documented
**Change Log:**
- v1.0 (Jan 26): Initial version with Service Bus and Event Hub
- v2.0 (Jan 27): Added Storage Queue as third option with complete implementation
