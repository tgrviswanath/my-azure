import azure.functions as func
import json
import logging

app = func.FunctionApp()


@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="orders",
    connection="SERVICE_BUS_CONNECTION_STRING"
)
def process_order(msg: func.ServiceBusMessage) -> None:
    order = json.loads(msg.get_body().decode("utf-8"))
    logging.info(f"Processing order: {order['order_id']}")

    # Simulate processing
    total = order["quantity"] * order["price"]
    logging.info(f"Order total: ${total:.2f} — Product: {order['product']}")
    # On exception, message goes to dead-letter queue after max retries


@app.service_bus_queue_trigger(
    arg_name="dlq_msg",
    queue_name="orders/$deadletterqueue",
    connection="SERVICE_BUS_CONNECTION_STRING"
)
def handle_dead_letter(dlq_msg: func.ServiceBusMessage) -> None:
    body = dlq_msg.get_body().decode("utf-8")
    reason = dlq_msg.dead_letter_reason
    logging.error(f"Dead-letter message — Reason: {reason} — Body: {body}")
    # Send alert, store for manual review
