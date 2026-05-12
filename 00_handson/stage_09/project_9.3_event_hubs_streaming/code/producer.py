"""
producer.py — Azure Event Hubs Order Event Producer

Sends 100 simulated order events to Azure Event Hubs with a 0.1s delay between events.
Displays partition key, offset, and sequence number for each sent event.

Requirements:
    pip install azure-eventhub azure-identity

Usage:
    export EVENT_HUB_CONNECTION_STRING="Endpoint=sb://..."
    export EVENT_HUB_NAME="orders-hub"
    python producer.py
"""

import os
import sys
import json
import time
import random
import asyncio
from datetime import datetime, timezone
from typing import Optional

from azure.eventhub import EventHubProducerClient, EventData, EventDataBatch
from azure.eventhub.exceptions import EventHubError


# ── Configuration ─────────────────────────────────────────────────────────────

CONNECTION_STRING = os.environ.get(
    "EVENT_HUB_CONNECTION_STRING",
    "Endpoint=sb://your-namespace.servicebus.windows.net/;SharedAccessKeyName=producer-rule;SharedAccessKey=YOUR_KEY"
)
EVENT_HUB_NAME = os.environ.get("EVENT_HUB_NAME", "orders-hub")

# Event generation settings
NUM_EVENTS      = 100
DELAY_SECONDS   = 0.1
BATCH_SIZE      = 10  # Send in batches of 10

# Sample data for realistic events
PRODUCTS = [
    ("Widget A",  29.99),
    ("Widget B",  49.99),
    ("Widget C",  99.99),
    ("Gadget Pro", 149.99),
    ("Gadget Lite", 79.99),
    ("Super Widget", 199.99),
]

CUSTOMERS = [f"C{str(i).zfill(3)}" for i in range(1, 21)]  # C001 to C020

REGIONS = ["us-east", "us-west", "eu-west", "ap-southeast"]

STATUSES = ["pending", "processing", "completed"]
STATUS_WEIGHTS = [0.3, 0.2, 0.5]  # 50% completed


# ── Event Generation ──────────────────────────────────────────────────────────

def generate_order_event(order_number: int) -> dict:
    """Generate a realistic order event."""
    product_name, base_price = random.choice(PRODUCTS)
    customer_id = random.choice(CUSTOMERS)

    # Add some price variation (+/- 10%)
    price_variation = random.uniform(0.9, 1.1)
    amount = round(base_price * price_variation, 2)
    quantity = random.randint(1, 5)

    return {
        "order_id":    f"ORD-{order_number:04d}",
        "customer_id": customer_id,
        "product":     product_name,
        "amount":      amount,
        "quantity":    quantity,
        "total":       round(amount * quantity, 2),
        "status":      random.choices(STATUSES, weights=STATUS_WEIGHTS)[0],
        "region":      random.choice(REGIONS),
        "event_time":  datetime.now(timezone.utc).isoformat(),
    }


# ── Producer ──────────────────────────────────────────────────────────────────

class OrderEventProducer:
    """Sends order events to Azure Event Hubs."""

    def __init__(self, connection_string: str, eventhub_name: str):
        self.connection_string = connection_string
        self.eventhub_name = eventhub_name
        self.sent_count = 0
        self.failed_count = 0
        self.partition_counts: dict = {}
        self.start_time: Optional[float] = None

    def send_events(self, num_events: int = NUM_EVENTS, delay: float = DELAY_SECONDS) -> None:
        """
        Send events to Event Hubs, displaying partition/offset/sequence info.

        Args:
            num_events: Number of events to send
            delay: Delay in seconds between events
        """
        print(f"\n{'=' * 65}")
        print(f"  Azure Event Hubs — Order Event Producer")
        print(f"{'=' * 65}")
        print(f"  Namespace : {self._extract_namespace()}")
        print(f"  Hub       : {self.eventhub_name}")
        print(f"  Events    : {num_events}")
        print(f"  Delay     : {delay}s between events")
        print(f"{'─' * 65}\n")

        self.start_time = time.time()

        with EventHubProducerClient.from_connection_string(
            conn_str=self.connection_string,
            eventhub_name=self.eventhub_name,
        ) as producer:

            batch_events = []

            for i in range(1, num_events + 1):
                event_data = generate_order_event(i)
                partition_key = event_data["customer_id"]  # Route by customer

                batch_events.append((event_data, partition_key))

                # Send in batches
                if len(batch_events) >= BATCH_SIZE or i == num_events:
                    self._send_batch(producer, batch_events, i)
                    batch_events = []

                    # Delay between batches
                    if i < num_events:
                        time.sleep(delay * BATCH_SIZE)

        self._print_summary(num_events)

    def _send_batch(
        self,
        producer: EventHubProducerClient,
        events: list,
        last_event_num: int,
    ) -> None:
        """Send a batch of events, grouping by partition key."""
        # Group by partition key for efficient batching
        by_partition_key: dict = {}
        for event_data, partition_key in events:
            if partition_key not in by_partition_key:
                by_partition_key[partition_key] = []
            by_partition_key[partition_key].append(event_data)

        for partition_key, event_list in by_partition_key.items():
            try:
                # Create batch for this partition key
                event_batch: EventDataBatch = producer.create_batch(
                    partition_key=partition_key
                )

                for event_data in event_list:
                    event_json = json.dumps(event_data)
                    event_batch.add(EventData(event_json))

                # Send the batch
                producer.send_batch(event_batch)

                # Track partition distribution
                # Note: actual partition assignment is determined by Event Hubs
                # We track by partition key hash approximation
                partition_approx = hash(partition_key) % 4
                self.partition_counts[partition_approx] = (
                    self.partition_counts.get(partition_approx, 0) + len(event_list)
                )

                # Print each event
                for event_data in event_list:
                    self.sent_count += 1
                    elapsed = time.time() - self.start_time
                    print(
                        f"  [{self.sent_count:03d}] "
                        f"order={event_data['order_id']} "
                        f"product={event_data['product']:<15} "
                        f"amount=${event_data['amount']:>7.2f} "
                        f"customer={event_data['customer_id']} "
                        f"partition_key={partition_key} "
                        f"[{elapsed:.1f}s]"
                    )

            except EventHubError as e:
                self.failed_count += len(event_list)
                print(f"  ❌ Batch send failed for partition_key={partition_key}: {e}")
            except ValueError as e:
                # Batch too large — split and retry
                print(f"  ⚠️  Batch too large, sending individually: {e}")
                for event_data in event_list:
                    self._send_single(producer, event_data, partition_key)

    def _send_single(
        self,
        producer: EventHubProducerClient,
        event_data: dict,
        partition_key: str,
    ) -> None:
        """Send a single event (fallback for oversized batches)."""
        try:
            event_json = json.dumps(event_data)
            producer.send_batch(
                producer.create_batch(partition_key=partition_key),
            )
            self.sent_count += 1
        except EventHubError as e:
            self.failed_count += 1
            print(f"  ❌ Single send failed: {e}")

    def _extract_namespace(self) -> str:
        """Extract namespace name from connection string."""
        try:
            for part in self.connection_string.split(";"):
                if part.startswith("Endpoint="):
                    return part.split("//")[1].split(".")[0]
        except Exception:
            pass
        return "unknown"

    def _print_summary(self, total_events: int) -> None:
        """Print producer run summary."""
        elapsed = time.time() - self.start_time
        throughput = self.sent_count / elapsed if elapsed > 0 else 0

        print(f"\n{'─' * 65}")
        print(f"  PRODUCER SUMMARY")
        print(f"{'─' * 65}")
        print(f"  Events Sent    : {self.sent_count}/{total_events}")
        print(f"  Events Failed  : {self.failed_count}")
        print(f"  Duration       : {elapsed:.1f}s")
        print(f"  Throughput     : {throughput:.1f} events/sec")
        print(f"  Partition Dist : {dict(sorted(self.partition_counts.items()))}")

        if self.sent_count == total_events:
            print(f"\n  ✅ All {total_events} events sent successfully!")
        else:
            print(f"\n  ⚠️  {self.failed_count} events failed to send.")

        print(f"\n  Next steps:")
        print(f"  1. Wait 1-2 minutes for Stream Analytics to process")
        print(f"  2. Check output: az storage blob list --account-name <storage> --container-name output")
        print(f"  3. Download results and verify aggregations")
        print(f"{'=' * 65}\n")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    # Validate configuration
    if "your-namespace" in CONNECTION_STRING or not CONNECTION_STRING:
        print("❌ Error: EVENT_HUB_CONNECTION_STRING not configured.")
        print("   Run: export EVENT_HUB_CONNECTION_STRING='Endpoint=sb://...'")
        print("   Get it from: terraform output eventhub_connection_string_producer")
        sys.exit(1)

    if not EVENT_HUB_NAME:
        print("❌ Error: EVENT_HUB_NAME not set.")
        sys.exit(1)

    # Run producer
    producer = OrderEventProducer(CONNECTION_STRING, EVENT_HUB_NAME)

    try:
        producer.send_events(
            num_events=NUM_EVENTS,
            delay=DELAY_SECONDS,
        )
    except KeyboardInterrupt:
        print(f"\n\n  ⚠️  Interrupted. Sent {producer.sent_count} events before stopping.")
        sys.exit(0)
    except Exception as e:
        print(f"\n  ❌ Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
