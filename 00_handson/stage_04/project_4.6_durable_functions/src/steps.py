import azure.functions as func
import azure.durable_functions as df
import json

app = df.DFApp(http_auth_level=func.AuthLevel.ANONYMOUS)


# HTTP starter
@app.route(route="orchestrators/{functionName}")
@app.durable_client_input(client_name="client")
async def http_start(req: func.HttpRequest, client: df.DurableOrchestrationClient) -> func.HttpResponse:
    payload = req.get_json()
    instance_id = await client.start_new(req.route_params["functionName"], client_input=payload)
    return client.create_check_status_response(req, instance_id)


# Orchestrator
@app.orchestration_trigger(context_name="context")
def document_workflow(context: df.DurableOrchestrationContext):
    payload = context.get_input()

    # Step 1: Validate
    validation = yield context.call_activity("validate_document", payload)
    if not validation["valid"]:
        return {"status": "rejected", "reason": validation["reason"]}

    # Step 2: Process
    result = yield context.call_activity("process_document", payload)

    # Step 3: Notify
    yield context.call_activity("send_notification", {
        "document_id": payload["document_id"],
        "status": "completed",
        "result": result,
    })

    return {"status": "completed", "document_id": payload["document_id"]}


# Activity: Validate
@app.activity_trigger(input_name="payload")
def validate_document(payload: dict) -> dict:
    filename = payload.get("filename", "")
    if not filename.endswith((".pdf", ".docx", ".txt")):
        return {"valid": False, "reason": f"Unsupported file type: {filename}"}
    return {"valid": True}


# Activity: Process
@app.activity_trigger(input_name="payload")
def process_document(payload: dict) -> dict:
    # Simulate processing
    return {"pages": 10, "word_count": 2500, "document_id": payload["document_id"]}


# Activity: Notify
@app.activity_trigger(input_name="payload")
def send_notification(payload: dict) -> str:
    print(f"📧 Notification: Document {payload['document_id']} — {payload['status']}")
    return "notification_sent"
