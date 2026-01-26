using System.Text.Json;
using Azure.Identity;
using Azure.Messaging.EventGrid;
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
        _logger.LogInformation("Publishing event to Event Grid via private endpoint");

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
}