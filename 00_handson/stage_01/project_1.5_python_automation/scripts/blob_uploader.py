"""
blob_uploader.py — Upload files to Azure Blob Storage with progress tracking.

Features:
  - Upload a single file or sync an entire folder
  - Progress bar for each file
  - Skip unchanged files (sync mode)
  - List blobs after upload
  - Start/stop Azure VMs

Prerequisites:
    pip install azure-identity azure-storage-blob azure-mgmt-compute

Authentication:
    az login   (uses DefaultAzureCredential)

Usage:
    python scripts/blob_uploader.py                    # upload sample data
    python scripts/blob_uploader.py --mode sync        # sync folder to blob
    python scripts/blob_uploader.py --mode list        # list blobs
    python scripts/blob_uploader.py --mode vm-stop     # stop all VMs in RG
"""

import os
import sys
import hashlib
import argparse
from pathlib import Path
from datetime import datetime

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContentSettings
from azure.core.exceptions import ResourceNotFoundError, HttpResponseError


def get_storage_client(account_name: str) -> BlobServiceClient:
    """Create BlobServiceClient using DefaultAzureCredential."""
    credential = DefaultAzureCredential()
    account_url = f"https://{account_name}.blob.core.windows.net"
    return BlobServiceClient(account_url=account_url, credential=credential)


def get_file_md5(file_path: Path) -> str:
    """Compute MD5 hash of a file for change detection."""
    md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            md5.update(chunk)
    return md5.hexdigest()


def get_content_type(file_path: Path) -> str:
    """Determine content type from file extension."""
    ext_map = {
        ".html": "text/html",
        ".css":  "text/css",
        ".js":   "application/javascript",
        ".json": "application/json",
        ".txt":  "text/plain",
        ".png":  "image/png",
        ".jpg":  "image/jpeg",
        ".pdf":  "application/pdf",
        ".gz":   "application/gzip",
        ".zip":  "application/zip",
    }
    return ext_map.get(file_path.suffix.lower(), "application/octet-stream")


def upload_file(container_client, file_path: Path, blob_name: str,
                overwrite: bool = True) -> dict:
    """Upload a single file to blob storage."""
    file_size = file_path.stat().st_size
    content_type = get_content_type(file_path)

    with open(file_path, "rb") as data:
        container_client.upload_blob(
            name=blob_name,
            data=data,
            overwrite=overwrite,
            content_settings=ContentSettings(content_type=content_type)
        )

    return {
        "name": blob_name,
        "size": file_size,
        "content_type": content_type
    }


def upload_folder(service_client: BlobServiceClient, folder_path: Path,
                  container_name: str, prefix: str = "") -> None:
    """Upload all files in a folder to a blob container."""
    print(f"\n[*] Uploading folder: {folder_path} → {container_name}/{prefix or '(root)'}")
    print("-" * 60)

    # Ensure container exists
    container_client = service_client.get_container_client(container_name)
    try:
        container_client.create_container()
        print(f"[+] Container '{container_name}' created.")
    except Exception:
        print(f"[~] Container '{container_name}' already exists.")

    files = list(folder_path.rglob("*"))
    files = [f for f in files if f.is_file()]

    if not files:
        print(f"[!] No files found in {folder_path}")
        return

    uploaded = 0
    total_bytes = 0

    for i, file_path in enumerate(files, 1):
        relative = file_path.relative_to(folder_path)
        blob_name = f"{prefix}/{relative}".lstrip("/") if prefix else str(relative)
        blob_name = blob_name.replace("\\", "/")  # Windows path fix

        try:
            result = upload_file(container_client, file_path, blob_name)
            size_kb = result["size"] / 1024
            print(f"  [{i:>3}/{len(files)}] ✅ {blob_name} ({size_kb:.1f} KB)")
            uploaded += 1
            total_bytes += result["size"]
        except HttpResponseError as e:
            print(f"  [{i:>3}/{len(files)}] ❌ {blob_name} — {e.message}")

    print(f"\n[+] Uploaded {uploaded}/{len(files)} files ({total_bytes/1024:.1f} KB total)")


def sync_folder(service_client: BlobServiceClient, folder_path: Path,
                container_name: str) -> None:
    """Sync a local folder to blob storage — only upload changed files."""
    print(f"\n[*] Syncing folder: {folder_path} → {container_name}")
    print("-" * 60)

    container_client = service_client.get_container_client(container_name)
    try:
        container_client.create_container()
    except Exception:
        pass

    # Build map of existing blobs
    existing_blobs = {}
    for blob in container_client.list_blobs(include=["metadata"]):
        existing_blobs[blob.name] = blob

    files = [f for f in folder_path.rglob("*") if f.is_file()]
    new_count = changed_count = skipped_count = 0

    for file_path in files:
        relative = file_path.relative_to(folder_path)
        blob_name = str(relative).replace("\\", "/")
        local_md5 = get_file_md5(file_path)

        if blob_name not in existing_blobs:
            upload_file(container_client, file_path, blob_name)
            print(f"  [NEW]     {blob_name}")
            new_count += 1
        else:
            # Check if file changed (compare size as quick check)
            blob = existing_blobs[blob_name]
            if blob.size != file_path.stat().st_size:
                upload_file(container_client, file_path, blob_name)
                print(f"  [CHANGED] {blob_name}")
                changed_count += 1
            else:
                print(f"  [SKIP]    {blob_name} (unchanged)")
                skipped_count += 1

    print(f"\n[+] Sync complete: {new_count} new, {changed_count} changed, {skipped_count} skipped")


def list_blobs(service_client: BlobServiceClient, container_name: str) -> None:
    """List all blobs in a container."""
    print(f"\n[*] Blobs in container: {container_name}")
    print("-" * 60)

    container_client = service_client.get_container_client(container_name)
    try:
        blobs = list(container_client.list_blobs())
        if not blobs:
            print("  (empty container)")
            return

        total_size = 0
        print(f"  {'Name':<40} {'Size':>10} {'Modified'}")
        print(f"  {'-'*40} {'-'*10} {'-'*20}")

        for blob in sorted(blobs, key=lambda b: b.name):
            size_kb = blob.size / 1024
            modified = blob.last_modified.strftime("%Y-%m-%d %H:%M") if blob.last_modified else "N/A"
            print(f"  {blob.name:<40} {size_kb:>9.1f}K {modified}")
            total_size += blob.size

        print(f"\n  Total: {len(blobs)} blobs, {total_size/1024:.1f} KB")

    except ResourceNotFoundError:
        print(f"  [!] Container '{container_name}' not found.")


def stop_vms(resource_group: str, subscription_id: str) -> None:
    """Deallocate all VMs in a resource group to stop billing."""
    from azure.mgmt.compute import ComputeManagementClient

    print(f"\n[*] Stopping VMs in resource group: {resource_group}")
    print("-" * 60)

    credential = DefaultAzureCredential()
    compute_client = ComputeManagementClient(credential, subscription_id)

    vms = list(compute_client.virtual_machines.list(resource_group))
    if not vms:
        print("  No VMs found in this resource group.")
        return

    for vm in vms:
        print(f"  Deallocating: {vm.name}...", end=" ", flush=True)
        try:
            poller = compute_client.virtual_machines.begin_deallocate(resource_group, vm.name)
            poller.result()
            print("✅ stopped")
        except Exception as e:
            print(f"❌ {e}")


def create_sample_data(folder: Path) -> None:
    """Create sample files for upload demo."""
    folder.mkdir(parents=True, exist_ok=True)
    samples = {
        "orders.json": b'[{"id":1,"product":"Widget A","amount":29.99},{"id":2,"product":"Widget B","amount":49.99}]',
        "config.json": b'{"env":"production","region":"eastus","debug":false}',
        "report.txt":  f"Azure Automation Report\nGenerated: {datetime.utcnow().isoformat()}\nStatus: OK\n".encode(),
        "data/metrics.json": b'{"cpu":45.2,"memory":62.1,"disk":38.5}',
    }
    for name, content in samples.items():
        path = folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    print(f"[+] Created {len(samples)} sample files in {folder}")


def main():
    parser = argparse.ArgumentParser(description="Azure Blob Storage Automation")
    parser.add_argument("--mode", choices=["upload", "sync", "list", "vm-stop"],
                        default="upload", help="Operation mode")
    parser.add_argument("--folder", default="./sample_data", help="Local folder path")
    parser.add_argument("--container", default="uploads", help="Blob container name")
    parser.add_argument("--account", default=os.environ.get("AZURE_STORAGE_ACCOUNT"),
                        help="Storage account name")
    args = parser.parse_args()

    print("=" * 60)
    print("  Azure Blob Storage Automation")
    print("=" * 60)

    if not args.account and args.mode != "vm-stop":
        print("[!] Set AZURE_STORAGE_ACCOUNT environment variable or use --account")
        sys.exit(1)

    folder_path = Path(args.folder)

    if args.mode == "upload":
        if not folder_path.exists():
            print(f"[*] Folder not found — creating sample data in {folder_path}")
            create_sample_data(folder_path)

        service_client = get_storage_client(args.account)
        upload_folder(service_client, folder_path, args.container)
        list_blobs(service_client, args.container)

    elif args.mode == "sync":
        if not folder_path.exists():
            create_sample_data(folder_path)
        service_client = get_storage_client(args.account)
        sync_folder(service_client, folder_path, args.container)

    elif args.mode == "list":
        service_client = get_storage_client(args.account)
        list_blobs(service_client, args.container)

    elif args.mode == "vm-stop":
        subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID")
        resource_group = os.environ.get("AZURE_RESOURCE_GROUP", "my-rg")
        if not subscription_id:
            import subprocess
            result = subprocess.run(
                ["az", "account", "show", "--query", "id", "-o", "tsv"],
                capture_output=True, text=True
            )
            subscription_id = result.stdout.strip()
        stop_vms(resource_group, subscription_id)

    print("\n[+] Done.")


if __name__ == "__main__":
    main()
