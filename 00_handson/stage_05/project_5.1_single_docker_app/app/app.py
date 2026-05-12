from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "version": os.getenv("APP_VERSION", "1.0.0")})

@app.route("/")
def index():
    return jsonify({"message": "Hello from Docker on Azure!"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
