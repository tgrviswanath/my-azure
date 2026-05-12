"""
backup_manager.py — Manage Azure storage snapshots
Usage:
  python backup_manager.py create --account ACCOUNT --container CONTAINER
  python backup_manager.py list   --account ACCOUNT --container CONTAINER
"""

import argparse
from datetime import datetime
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient


def get_client(account_name: str) -> BlobServiceClient:
    credential = DefaultAzureCredential()
    return BlobServiceClient(
        account_url=f"https://{account_name}.blob.core.windows.net",
        credential=credential
    )


def create_snapshot(account: str, container: str) -> None:
    client = get_client(account)
    container_client = client.get_container_client(container)
    
    print(f"Creating snapshots for all blobs in {container}...")
    for blob in container_client.list_blobs():
        blob_client = container_client.get_blob_client(blob.name)
        snapshot = blob_client.create_snapshot()
        print(f"✅ Snapshot created: {blob.name} → {snapshot['snapshot']}")


def list_snapshots(account: str, container: str) -> None:
    client = get_client(account)
    container_client = client.get_container_client(container)
    
    print(f"\nSnapshots in {account}/{container}:")
    print("-" * 80)
    for blob in container_client.list_blobs(include=["snapshots"]):
        snapshot_time = blob.snapshot or "current"
        print(f"  {blob.name:<50} {snapshot_time}")


def main():
    parser = argparse.ArgumentParser(description="Azure Blob snapshot manager")
    subparsers = parser.add_subparsers(dest="command")

    create_p = subparsers.add_parser("create")
    create_p.add_argument("--account", required=True)
    create_p.add_argument("--container", required=True)

    list_p = subparsers.add_parser("list")
    list_p.add_argument("--account", required=True)
    list_p.add_argument("--container", required=True)

    args = parser.parse_args()

    if args.command == "create":
        create_snapshot(args.account, args.container)
    elif args.command == "list":
        list_snapshots(args.account, args.container)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
