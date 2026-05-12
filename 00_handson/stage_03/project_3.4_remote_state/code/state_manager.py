"""
state_manager.py — Manage Terraform remote state on Azure Storage.

Commands:
    bootstrap    Create storage account + container for Terraform state
    list         List all state files in the container
    break-lock   Break a stuck blob lease lock

Usage:
    python state_manager.py bootstrap --resource-group rg-tfstate --storage-account stterraformstateXXXXXX
    python state_manager.py list --storage-account stterraformstateXXXXXX
    python state_manager.py break-lock --storage-account stterraformstateXXXXXX --blob project/terraform.tfstate

Requirements:
    pip install azure-storage-blob azure-mgmt-storage azure-identity
"""

import argparse
import sys
from datetime import datetime
from azure.identity import DefaultAzureCredential
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.storage.models import (
    StorageAccountCreateParameters,
    Sku,
    Kind,
    BlobServiceProperties,
    BlobRetentionPolicy,
    StorageAccountUpdateParameters,
)
from azure.storage.blob import BlobServiceClient, BlobLeaseClient
from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError, HttpResponseError


def ok(msg: str) -> None:
    print(f"  \033[92m✔\033[0m  {msg}")

def warn(msg: str) -> None:
    print(f"  \033[93m⚠\033[0m  {msg}")

def fail(msg: str) -> None:
    print(f"  \033[91m✘\033[0m  {msg}")

def info(msg: str) -> None:
    print(f"  \033[94mℹ\033[0m  {msg}")

def section(title: str) -> None:
    print(f"\n{'─' * 60}")
    print(f"  {title}")
    print(f"{'─' * 60}")


# ─────────────────────────────────────────────
# Bootstrap
# ─────────────────────────────────────────────

def cmd_bootstrap(
    credential: DefaultAzureCredential,
    subscription_id: str,
    resource_group: str,
    storage_account_name: str,
    container_name: str,
    location: str,
) -> None:
    section("Bootstrap: Create Terraform State Storage")

    storage_client = StorageManagementClient(credential, subscription_id)

    # 1. Create storage account
    info(f"Creating storage account: {storage_account_name}")
    try:
        poller = storage_client.storage_accounts.begin_create(
            resource_group,
            storage_account_name,
            StorageAccountCreateParameters(
                sku=Sku(name="Standard_LRS"),
                kind=Kind.STORAGE_V2,
                location=location,
                enable_https_traffic_only=True,
                minimum_tls_version="TLS1_2",
                allow_blob_public_access=False,
                tags={
                    "purpose": "terraform-state",
                    "managed_by": "state_manager.py",
                },
            ),
        )
        account = poller.result()
        ok(f"Storage account created: {account.name}")
    except ResourceExistsError:
        ok(f"Storage account already exists: {storage_account_name}")

    # 2. Enable blob versioning and soft delete
    info("Enabling blob versioning and soft delete...")
    storage_client.blob_services.set_service_properties(
        resource_group,
        storage_account_name,
        BlobServiceProperties(
            is_versioning_enabled=True,
            delete_retention_policy=BlobRetentionPolicy(enabled=True, days=30),
        ),
    )
    ok("Blob versioning enabled (30-day soft delete)")

    # 3. Create container
    info(f"Creating container: {container_name}")
    blob_service_client = BlobServiceClient(
        account_url=f"https://{storage_account_name}.blob.core.windows.net",
        credential=credential,
    )
    try:
        blob_service_client.create_container(container_name)
        ok(f"Container created: {container_name}")
    except ResourceExistsError:
        ok(f"Container already exists: {container_name}")

    # 4. Print backend config
    section("Terraform Backend Configuration")
    print(f"""
  Add this to your terraform block in main.tf:

  \033[94mterraform {{
    backend "azurerm" {{
      resource_group_name  = "{resource_group}"
      storage_account_name = "{storage_account_name}"
      container_name       = "{container_name}"
      key                  = "your-project/terraform.tfstate"
    }}
  }}\033[0m

  Then run:
    terraform init
    # or if migrating from local state:
    terraform init -migrate-state
""")


# ─────────────────────────────────────────────
# List state files
# ─────────────────────────────────────────────

def cmd_list(
    credential: DefaultAzureCredential,
    storage_account_name: str,
    container_name: str,
) -> None:
    section(f"State Files in {storage_account_name}/{container_name}")

    blob_service_client = BlobServiceClient(
        account_url=f"https://{storage_account_name}.blob.core.windows.net",
        credential=credential,
    )

    try:
        container_client = blob_service_client.get_container_client(container_name)
        blobs = list(container_client.list_blobs(include=["metadata", "versions"]))
    except ResourceNotFoundError:
        fail(f"Container '{container_name}' not found in storage account '{storage_account_name}'")
        return

    if not blobs:
        warn("No state files found")
        return

    # Filter to only .tfstate files
    state_blobs = [b for b in blobs if b.name.endswith(".tfstate")]

    ok(f"Found {len(state_blobs)} state file(s)")
    print(f"\n  {'Name':<50} {'Size':>8} {'Modified':<25} {'Lease'}")
    print(f"  {'─' * 100}")

    for blob in state_blobs:
        size = f"{blob.size:,} B" if blob.size else "0 B"
        modified = blob.last_modified.strftime("%Y-%m-%d %H:%M:%S") if blob.last_modified else "Unknown"
        lease = blob.lease.status if blob.lease else "unlocked"
        lease_color = "\033[91m" if lease == "locked" else "\033[92m"
        print(f"  {blob.name:<50} {size:>8} {modified:<25} {lease_color}{lease}\033[0m")

    # Show versions if any
    version_blobs = [b for b in blobs if b.version_id and b.name.endswith(".tfstate")]
    if version_blobs:
        print(f"\n  Versions: {len(version_blobs)} historical version(s) stored")
        info("Use Azure Portal or az storage blob list --include versions to see all versions")


# ─────────────────────────────────────────────
# Break lock
# ─────────────────────────────────────────────

def cmd_break_lock(
    credential: DefaultAzureCredential,
    storage_account_name: str,
    container_name: str,
    blob_name: str,
) -> None:
    section(f"Break Lock: {blob_name}")

    blob_service_client = BlobServiceClient(
        account_url=f"https://{storage_account_name}.blob.core.windows.net",
        credential=credential,
    )

    blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_name)

    # Check current lease status
    try:
        props = blob_client.get_blob_properties()
        lease_status = props.lease.status
        lease_state = props.lease.state
        info(f"Current lease status: {lease_status}")
        info(f"Current lease state:  {lease_state}")
    except ResourceNotFoundError:
        fail(f"Blob not found: {blob_name}")
        return

    if lease_status == "unlocked":
        ok("Blob is not locked — nothing to do")
        return

    # Break the lease
    warn(f"Breaking lease on: {blob_name}")
    warn("Only do this if you are sure no terraform apply is running!")

    confirm = input("\n  Type 'yes' to break the lease: ")
    if confirm.strip().lower() != "yes":
        print("  Cancelled.")
        return

    try:
        lease_client = BlobLeaseClient(blob_client)
        lease_client.break_lease(lease_break_period=0)
        ok("Lease broken successfully")
        ok("You can now run terraform apply")
    except HttpResponseError as e:
        fail(f"Failed to break lease: {e.message}")


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def get_subscription_id(credential: DefaultAzureCredential) -> str:
    from azure.mgmt.subscription import SubscriptionClient
    sub_client = SubscriptionClient(credential)
    subscriptions = list(sub_client.subscriptions.list())
    if not subscriptions:
        print("\nERROR: No subscriptions found. Run 'az login' first.")
        sys.exit(1)
    return subscriptions[0].subscription_id


def main() -> None:
    parser = argparse.ArgumentParser(description="Terraform remote state manager for Azure")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # bootstrap
    p_bootstrap = subparsers.add_parser("bootstrap", help="Create state storage infrastructure")
    p_bootstrap.add_argument("--resource-group", required=True)
    p_bootstrap.add_argument("--storage-account", required=True)
    p_bootstrap.add_argument("--container", default="tfstate")
    p_bootstrap.add_argument("--location", default="eastus")
    p_bootstrap.add_argument("--subscription-id")

    # list
    p_list = subparsers.add_parser("list", help="List state files")
    p_list.add_argument("--storage-account", required=True)
    p_list.add_argument("--container", default="tfstate")

    # break-lock
    p_lock = subparsers.add_parser("break-lock", help="Break a stuck state lock")
    p_lock.add_argument("--storage-account", required=True)
    p_lock.add_argument("--container", default="tfstate")
    p_lock.add_argument("--blob", required=True, help="Blob path (e.g. project/terraform.tfstate)")

    args = parser.parse_args()

    print("\n╔══════════════════════════════════════════════════════════╗")
    print("║         Terraform State Manager for Azure                ║")
    print(f"║  Command: {args.command:<47}║")
    print("╚══════════════════════════════════════════════════════════╝")

    credential = DefaultAzureCredential()

    if args.command == "bootstrap":
        subscription_id = args.subscription_id or get_subscription_id(credential)
        cmd_bootstrap(
            credential,
            subscription_id,
            args.resource_group,
            args.storage_account,
            args.container,
            args.location,
        )
    elif args.command == "list":
        cmd_list(credential, args.storage_account, args.container)
    elif args.command == "break-lock":
        cmd_break_lock(credential, args.storage_account, args.container, args.blob)

    print(f"\n{'═' * 60}")
    print("  Done.")
    print(f"{'═' * 60}\n")


if __name__ == "__main__":
    main()
