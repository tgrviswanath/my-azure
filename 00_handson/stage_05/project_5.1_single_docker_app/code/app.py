"""
app.py — Flask application for single-service Docker demo.

Usage:
    pip install flask
    python code/app.py

    # Or with Docker:
    docker build -t handson-app .
    docker run -p 8080:8080 handson-app
    curl http://localhost:8080/health
"""

import os
import time
import random
from flask import Flask, jsonify, request

app = Flask(__name__)

START_TIME = time.time()


@app.route("/health")
def health():
    """Health check endpoint — used by AKS readiness/liveness probes."""
    return jsonify({
        "status": "healthy",
        "uptime_seconds": round(time.time() - START_TIME),
        "version": os.environ.get("APP_VERSION", "1.0.0"),
    })


@app.route("/")
def index():
    return jsonify({
        "message": "Handson Azure App",
        "version": os.environ.get("APP_VERSION", "1.0.0"),
        "endpoints": ["/health", "/api/items", "/api/items/<id>"],
    })


@app.route("/api/items")
def list_items():
    items = [
        {"id": i, "name": f"Item {i}", "price": round(random.uniform(10, 100), 2)}
        for i in range(1, 6)
    ]
    return jsonify({"items": items, "count": len(items)})


@app.route("/api/items/<int:item_id>")
def get_item(item_id: int):
    if item_id < 1 or item_id > 100:
        return jsonify({"error": "Item not found"}), 404
    return jsonify({"id": item_id, "name": f"Item {item_id}", "price": round(random.uniform(10, 100), 2)})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    debug = os.environ.get("DEBUG", "false").lower() == "true"
    print(f"[*] Starting app on port {port}")
    app.run(host="0.0.0.0", port=port, debug=debug)
