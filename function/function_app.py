import json
import logging
import os
from datetime import datetime

import azure.functions as func
from azure.eventgrid import EventGridEvent, EventGridPublisherClient
from azure.identity import DefaultAzureCredential

app = func.FunctionApp()


@app.route(route="publish", methods=["POST", "GET"], auth_level=func.AuthLevel.ANONYMOUS)
def publish_event(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP trigger function that publishes events to Event Grid via private endpoint.
    """
    logging.info('Processing HTTP request to publish event to Event Grid')

    try:
        endpoint = os.environ.get("EVENT_GRID_TOPIC_ENDPOINT")
        if not endpoint:
            return func.HttpResponse(
                "EVENT_GRID_TOPIC_ENDPOINT not configured",
                status_code=500
            )

        credential = DefaultAzureCredential()
        client = EventGridPublisherClient(endpoint, credential)

        req_body = {}
        try:
            req_body = req.get_json()
        except ValueError:
            req_body = {"message": "Test event from Azure Function"}

        event_id = f"event-{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}"
        event = EventGridEvent(
            event_type="Custom.TestEvent",
            data={
                "message": req_body.get("message", "Test event from Azure Function"),
                "timestamp": datetime.utcnow().isoformat(),
                "source": "azure-function-via-private-endpoint"
            },
            subject="test/event",
            data_version="1.0"
        )

        client.send(event)

        logging.info(f'Successfully published event {event_id} to Event Grid')

        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "message": f"Event {event_id} published successfully",
                "endpoint": endpoint
            }),
            mimetype="application/json",
            status_code=200
        )

    except Exception as e:
        logging.error(f'Error publishing event: {str(e)}')
        return func.HttpResponse(
            json.dumps({
                "status": "error",
                "message": str(e)
            }),
            mimetype="application/json",
            status_code=500
        )


@app.event_grid_trigger(arg_name="event")
def consume_event(event: func.EventGridEvent):
    """
    Event Grid trigger function that consumes events from Event Grid topic.
    This function proves that the VNET peering and private endpoint connectivity works.
    """
    logging.info('Event Grid trigger function processed an event')

    event_data = {
        "id": event.id,
        "event_type": event.event_type,
        "subject": event.subject,
        "event_time": event.event_time.isoformat() if event.event_time else None,
        "data": event.get_json(),
        "topic": event.topic
    }

    logging.info(f'Event ID: {event.id}')
    logging.info(f'Event Type: {event.event_type}')
    logging.info(f'Event Subject: {event.subject}')
    logging.info(f'Raw Event Data: {json.dumps(event.get_json(), indent=2)}')
    logging.info(f'Event data: {json.dumps(event_data, indent=2)}')

    logging.info(
        '✅ Successfully received event via private endpoint - VNET peering connectivity confirmed!')
