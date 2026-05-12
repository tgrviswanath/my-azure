"""
azurite_demo.py — Test Azure Storage services locally using Azurite.

Prerequisites:
    docker compose up -d   (starts Azurite)
    pip install azure-storage-blob azure-storage-queue

Run:
    python code/azurite_demo.py
"""

from azure.storage.blob import BlobServiceClient
from azure.storage.queue import QueueServiceClient

# Azurite connection string — works with UseDevelopmentStorage=true
CONN_STR = (
    "DefaultEndpointsProtocol=http;"
    "AccountName=devstoreaccount1;"
    "AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;"
    "BlobEndpoint=http://localhost:10000/devstoreaccount1;"
    "QueueEndpoint=http://localhost:10001/devstoreaccount1;"
)


def demo_blob_storage():
    print("\n" + "=" * 60)
    print("  Blob Storage Demo")
    print("=" * 60)
    client = BlobServiceClient.from_connection_string(CONN_STR)
    container_name = "local-demo"
    container = client.get_container_client(container_name)

    try:
        container.create_container()
        print(f"[+] Container '{container_name}' created.")
    except Exception:
        print(f"[~] Container '{container_name}' already exists.")

    files = [
        ("orders.json", b'[{"id":1,"product":"Widget A","amount":29.99}]'),
        ("config.json", b'{"env":"local","debug":true}'),
        ("readme.txt",  b"Local Azurite demo file"),
    ]
    for name, data in files:
        container.upload_blob(name=name, data=data, overwrite=True)
        print(f"[+] Uploaded: {name}")

    blobs = list(container.list_blobs())
    print(f"\n[*] Blobs in container ({len(blobs)}):")
    for blob in blobs:
        print(f"    {blob.name} ({blob.size} bytes)")

    # Download and verify one blob
    downloaded = container.download_blob("config.json").readall()
    print(f"\n[*] Downloaded config.json: {downloaded.decode()}")


def demo_queue_storage():
    print("\n" + "=" * 60)
    print("  Queue Storage Demo")
    print("=" * 60)
    client = QueueServiceClient.from_connection_string(CONN_STR)
    queue_name = "local-orders-queue"
    queue = client.get_queue_client(queue_name)

    try:
        queue.create_queue()
        print(f"[+] Queue '{queue_name}' created.")
    except Exception:
        print(f"[~] Queue '{queue_name}' already exists.")

    messages = ["order-001", "order-002", "order-003"]
    for msg in messages:
        queue.send_message(msg)
        print(f"[+] Sent: {msg}")

    print(f"\n[*] Receiving messages:")
    received = queue.receive_messages(max_messages=10)
    count = 0
    for msg in received:
        print(f"    [{msg.id[:8]}] {msg.content}")
        queue.delete_message(msg)
        count += 1
    print(f"[*] Processed and deleted {count} messages.")


def main():
    print("\n" + "=" * 60)
    print("  Azurite Demo — Azure Services Running Locally")
    print("=" * 60)
    print("[*] Connecting to Azurite at localhost:10000/10001")

    try:
        demo_blob_storage()
        demo_queue_storage()
        print("\n[+] All operations ran against Azurite — zero Azure cost.\n")
    except Exception as e:
        print(f"\n[!] Error: {e}")
        print("[!] Make sure Azurite is running: docker compose up -d")


if __name__ == "__main__":
    main()
