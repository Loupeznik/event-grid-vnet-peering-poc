using System.Text.Json;
using Azure.Identity;
using Azure.Messaging.EventGrid;
using Azure.Messaging.EventHubs;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Extensions.EventGrid;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace EventGridPubSubFunction;

public class EventGridFunctions
{
    private readonly ILogger<EventGridFunctions> _logger;

    public EventGridFunctions(ILogger<EventGridFunctions> logger)
    {
        _logger = logger;
    }

    [Function("PublishEvent")]
    public async Task<HttpResponseData> PublishEvent(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", Route = "publish")]
        HttpRequestData req)
    {
        // Log source IP information
        var clientIp = req.Headers.TryGetValues("X-Forwarded-For", out var forwardedFor)
            ? forwardedFor.First().Split(',')[0].Trim()
            : "unknown";
        var originalHost = req.Headers.TryGetValues("X-Original-Host", out var host)
            ? host.First()
            : "unknown";

        _logger.LogInformation("Publishing event to Event Grid via private endpoint");
        _logger.LogInformation("Source IP (X-Forwarded-For): {ClientIp}", clientIp);
        _logger.LogInformation("Original Host: {OriginalHost}", originalHost);

        var endpoint = Environment.GetEnvironmentVariable("EVENT_GRID_TOPIC_ENDPOINT");
        if (string.IsNullOrEmpty(endpoint))
        {
            _logger.LogError("EVENT_GRID_TOPIC_ENDPOINT environment variable not set");
            var errorResponse = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            await errorResponse.WriteAsJsonAsync(new { error = "Event Grid endpoint not configured" });
            return errorResponse;
        }

        var message = "Test event from .NET Function";
        try
        {
            var requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            if (!string.IsNullOrEmpty(requestBody))
            {
                var data = JsonSerializer.Deserialize<Dictionary<string, object>>(requestBody);
                if (data != null && data.ContainsKey("message"))
                {
                    message = data["message"].ToString() ?? message;
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse request body, using default message");
        }

        try
        {
            var client = new EventGridPublisherClient(new Uri(endpoint), new DefaultAzureCredential());
            var eventId = $"event-{DateTime.UtcNow:yyyyMMddHHmmssfff}";

            var eventGridEvent = new EventGridEvent(
                subject: "test/event",
                eventType: "Custom.TestEvent",
                dataVersion: "1.0",
                data: new
                {
                    message,
                    timestamp = DateTime.UtcNow.ToString("o"),
                    source = "azure-function-via-private-endpoint"
                })
            {
                Id = eventId
            };

            await client.SendEventAsync(eventGridEvent);

            _logger.LogInformation("Successfully published event {EventId} to Event Grid via managed identity",
                eventId);

            var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new
            {
                status = "success",
                message = "Event published successfully",
                eventId,
                endpoint
            });
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish event to Event Grid");
            var errorResponse = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            await errorResponse.WriteAsJsonAsync(new { error = ex.Message });
            return errorResponse;
        }
    }

    [Function("ConsumeEvent")]
    public void ConsumeEvent([EventGridTrigger] EventGridEvent eventGridEvent)
    {
        _logger.LogInformation("=== Event Grid Trigger Fired ===");
        _logger.LogWarning("⚠️ Note: Event Grid webhook delivery comes via public internet (Azure Event Grid service IPs)");
        _logger.LogInformation("Event ID: {EventId}", eventGridEvent.Id);
        _logger.LogInformation("Event Type: {EventType}", eventGridEvent.EventType);
        _logger.LogInformation("Subject: {Subject}", eventGridEvent.Subject);
        _logger.LogInformation("Event Time: {EventTime}", eventGridEvent.EventTime);

        try
        {
            var data = eventGridEvent.Data.ToObjectFromJson<Dictionary<string, object>>();
            var formattedData = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
            _logger.LogInformation("Event Data:\n{Data}", formattedData);
            _logger.LogInformation(
                "✅ Successfully received event via private endpoint - VNET peering connectivity confirmed!");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to deserialize event data");
        }
    }

    [Function("ConsumeEventFromEventHub")]
    public async Task ConsumeEventFromEventHub(
        [EventHubTrigger("events", Connection = "EventHubConnection")]
        EventData[] events)
    {
        _logger.LogInformation("=== Event Hub Trigger Fired ===");
        _logger.LogInformation("✅ Event Hub connection via PRIVATE ENDPOINT (VNET peering - fully private path)");
        _logger.LogInformation("Received {Count} events from Event Hub", events.Length);

        foreach (var eventData in events)
        {
            try
            {
                var eventBody = eventData.EventBody.ToString();

                // Event Grid wraps events in an array when delivering to Event Hub
                var eventGridEvents = JsonSerializer.Deserialize<EventGridEvent[]>(eventBody);
                
                if (eventGridEvents == null || eventGridEvents.Length == 0)
                {
                    _logger.LogWarning("No Event Grid events found in Event Hub message");
                    continue;
                }

                foreach (var eventGridEvent in eventGridEvents)
                {
                    _logger.LogInformation("=== Event Grid Event from Event Hub ===");
                    _logger.LogInformation("Event ID: {EventId}", eventGridEvent.Id);
                    _logger.LogInformation("Event Type: {EventType}", eventGridEvent.EventType);
                    _logger.LogInformation("Subject: {Subject}", eventGridEvent.Subject);
                    _logger.LogInformation("Event Time: {EventTime}", eventGridEvent.EventTime);
                    _logger.LogInformation("Sequence Number: {SequenceNumber}", eventData.SequenceNumber);
                    _logger.LogInformation("Partition Key: {PartitionKey}", eventData.PartitionKey);

                    var data = eventGridEvent.Data.ToObjectFromJson<Dictionary<string, object>>();
                    var formattedData = JsonSerializer.Serialize(data,
                        new JsonSerializerOptions { WriteIndented = true });
                    _logger.LogInformation("Event Data:\n{Data}", formattedData);

                    _logger.LogInformation(
                        "✅ Successfully received event via FULLY PRIVATE path (Event Grid → Event Hub → Function)");
                }
            }
            catch (JsonException ex)
            {
                _logger.LogError(ex, "Failed to parse Event Grid event from Event Hub");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing Event Hub event");
                throw;
            }
        }

        await Task.CompletedTask;
    }
}