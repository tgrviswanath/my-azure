"""
metrics_exporter.py — Flask app exposing Prometheus /metrics endpoint.

Usage:
    pip install flask prometheus-client
    python code/metrics_exporter.py
    curl http://localhost:8080/metrics
"""

import random
import time
from flask import Flask, jsonify, request, Response
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# ── Prometheus metrics ────────────────────────────────────────────────────────
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"]
)

REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "endpoint"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
)

ACTIVE_REQUESTS = Gauge(
    "active_requests",
    "Number of active requests being processed"
)

ORDER_COUNT = Counter("orders_processed_total", "Total orders processed", ["status"])
REVENUE = Counter("revenue_total_usd", "Total revenue in USD")


def track_request(func):
    """Decorator to track request metrics."""
    import functools
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        ACTIVE_REQUESTS.inc()
        start = time.time()
        status = 200
        try:
            response = func(*args, **kwargs)
            if hasattr(response, "status_code"):
                status = response.status_code
            return response
        except Exception:
            status = 500
            raise
        finally:
            duration = time.time() - start
            REQUEST_COUNT.labels(request.method, request.path, status).inc()
            REQUEST_DURATION.labels(request.method, request.path).observe(duration)
            ACTIVE_REQUESTS.dec()
    return wrapper


@app.route("/health")
@track_request
def health():
    return jsonify({"status": "healthy"})


@app.route("/api/orders")
@track_request
def list_orders():
    time.sleep(random.uniform(0.05, 0.3))
    orders = [{"id": f"ORD-{i:03d}", "amount": round(random.uniform(10, 100), 2)} for i in range(5)]
    ORDER_COUNT.labels("success").inc(len(orders))
    REVENUE.inc(sum(o["amount"] for o in orders))
    return jsonify({"orders": orders})


@app.route("/api/slow")
@track_request
def slow():
    time.sleep(random.uniform(1.0, 3.0))
    return jsonify({"message": "slow response"})


@app.route("/metrics")
def metrics():
    """Prometheus metrics endpoint."""
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    print("[*] Starting metrics exporter on :8080")
    print("[*] Metrics: http://localhost:8080/metrics")
    print("""
Example PromQL queries:
  # Request rate
  rate(http_requests_total[5m])

  # P99 latency
  histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

  # Error rate %
  rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) * 100
""")
    app.run(host="0.0.0.0", port=8080)
