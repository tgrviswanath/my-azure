"""
log_shipper.py — Ship custom logs to Azure Log Analytics using the Logs Ingestion API.

Usage:
    pip install azure-identity azure-monitor-ingestion
    python code/log_shipper.py --workspace-id <id> --message "test log"
    python code/log_shipper.py --workspace-id <id> --file /var/log/app.log
"""

import argparse
import json
import sys
from datetime import datetime, timezone

from azure.identity import DefaultAzureCredential
from azure.monitor.ingestion import LogsIngestionClient


def send_log(endpoint: str, rule_id: str, stream_name: str, messages: list[dict]) -> None:
    """Send log entries to Log Analytics via Logs Ingestion API."""
    credential = DefaultAzureCredential()
    client = LogsIngestionClient(endpoint=endpoint, credential=credential)

    client.upload(rule_id=rule_id, stream_name=stream_name, logs=messages)
    print(f"[+] Sent {len(messages)} log entries to Log Analytics.")


def build_log_entry(message: str, level: str = "INFO", source: str = "log_shipper") -> dict:
    return {
        "TimeGenerated": datetime.now(timezone.utc).isoformat(),
        "Level": level,
        "Source": source,
        "Message": message,
        "Host": "local-machine",
    }


def tail_file(filepath: str, endpoint: str, rule_id: str, stream_name: str) -> None:
    """Tail a log file and ship new lines to Log Analytics."""
    import time
    print(f"[*] Tailing {filepath} → Log Analytics...")
    with open(filepath, "r") as f:
        f.seek(0, 2)  # Seek to end
        while True:
            line = f.readline()
            if line:
                entry = build_log_entry(line.strip())
                send_log(endpoint, rule_id, stream_name, [entry])
            else:
                time.sleep(1)


def main():
    parser = argparse.ArgumentParser(description="Ship logs to Azure Log Analytics")
    parser.add_argument("--endpoint",    required=True, help="DCE endpoint URL")
    parser.add_argument("--rule-id",     required=True, help="Data Collection Rule ID")
    parser.add_argument("--stream-name", default="Custom-AppLogs_CL")
    parser.add_argument("--message",     help="Single log message to send")
    parser.add_argument("--file",        help="Log file to tail and ship")
    parser.add_argument("--level",       default="INFO", choices=["DEBUG","INFO","WARN","ERROR"])
    args = parser.parse_args()

    if args.message:
        entry = build_log_entry(args.message, args.level)
        send_log(args.endpoint, args.rule_id, args.stream_name, [entry])
    elif args.file:
        tail_file(args.file, args.endpoint, args.rule_id, args.stream_name)
    else:
        # Send sample batch
        entries = [
            build_log_entry("Application started", "INFO"),
            build_log_entry("Processing 100 orders", "INFO"),
            build_log_entry("Slow query detected: 2.3s", "WARN"),
            build_log_entry("Order ORD-001 processed", "INFO"),
        ]
        send_log(args.endpoint, args.rule_id, args.stream_name, entries)


if __name__ == "__main__":
    main()
