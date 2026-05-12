"""order_publisher.py — Publish orders to Azure Service Bus"""
import json
import os
import uuid
from azure.servicebus import ServiceBusClient, ServiceBusMessage

CONN_STR = os.environ["SERVICE_BUS_CONNECTION_STRING"]
QUEUE_NAME = "orders"

orders = [
    {"order_id": str(uuid.uuid4()), "product": "Widget A", "quantity": 2, "price": 29.99},
    {"order_id": str(uuid.uuid4()), "product": "Widget B", "quantity": 1, "price": 49.99},
    {"order_id": str(uuid.uuid4()), "product": "Widget C", "quantity": 5, "price": 9.99},
]

with ServiceBusClient.from_connection_string(CONN_STR) as client:
    sender = client.get_queue_sender(queue_name=QUEUE_NAME)
    with sender:
        for order in orders:
            msg = ServiceBusMessage(json.dumps(order))
            sender.send_messages(msg)
            print(f"✅ Sent order: {order['order_id']}")
