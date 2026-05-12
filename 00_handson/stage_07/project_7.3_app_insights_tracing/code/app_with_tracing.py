"""
app_with_tracing.py — Flask app instrumented with Application Insights.

Usage:
    pip install flask opencensus-ext-azure opencensus-ext-flask
    export APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=xxx;..."
    python code/app_with_tracing.py
"""

import os
import time
import random
from flask import Flask, jsonify, request
from opencensus.ext.azure.log_exporter import AzureLogHandler
from opencensus.ext.azure.trace_exporter import AzureExporter
from opencensus.ext.flask.flask_middleware import FlaskMiddleware
from opencensus.trace.samplers import ProbabilitySampler
import logging

app = Flask(__name__)

# Get connection string from environment
CONN_STR = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING", "")

# Set up distributed tracing middleware
if CONN_STR:
    middleware = FlaskMiddleware(
        app,
        exporter=AzureExporter(connection_string=CONN_STR),
        sampler=ProbabilitySampler(rate=1.0),  # 100% sampling for dev
    )

# Set up structured logging to App Insights
logger = logging.getLogger(__name__)
if CONN_STR:
    logger.addHandler(AzureLogHandler(connection_string=CONN_STR))
logger.setLevel(logging.INFO)


@app.route("/health")
def health():
    return jsonify({"status": "healthy", "service": "handson-api"})


@app.route("/api/orders")
def list_orders():
    """Simulate order listing with variable latency."""
    start = time.time()

    # Simulate DB query latency
    time.sleep(random.uniform(0.05, 0.3))

    orders = [
        {"id": f"ORD-{i:03d}", "product": f"Widget {chr(65+i)}", "amount": round(random.uniform(10, 100), 2)}
        for i in range(random.randint(3, 10))
    ]

    duration_ms = (time.time() - start) * 1000
    logger.info(f"Listed {len(orders)} orders in {duration_ms:.1f}ms",
                extra={"custom_dimensions": {"order_count": len(orders), "duration_ms": duration_ms}})

    return jsonify({"orders": orders, "count": len(orders)})


@app.route("/api/users/<user_id>")
def get_user(user_id: str):
    """Simulate user lookup — occasionally raises exception."""
    if random.random() < 0.1:  # 10% error rate for demo
        logger.error(f"User {user_id} not found", exc_info=True)
        return jsonify({"error": "User not found"}), 404

    return jsonify({"id": user_id, "name": f"User {user_id}", "email": f"user{user_id}@example.com"})


@app.route("/api/slow")
def slow_endpoint():
    """Simulate a slow endpoint — visible in Performance blade."""
    time.sleep(random.uniform(1.0, 3.0))
    return jsonify({"message": "slow response"})


if __name__ == "__main__":
    print(f"[*] Starting app with App Insights tracing")
    print(f"[*] Connection string: {'configured' if CONN_STR else 'NOT SET — set APPLICATIONINSIGHTS_CONNECTION_STRING'}")
    app.run(host="0.0.0.0", port=5000, debug=False)
