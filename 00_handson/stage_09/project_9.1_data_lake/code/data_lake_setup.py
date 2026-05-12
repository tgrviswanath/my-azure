"""
Project 9.1 — Azure Data Lake Storage Gen2 Setup
Uses azure-storage-file-datalake to create filesystems, set ACLs,
upload sample data, and list the data lake structure.
"""

import os
import io
import csv
import json
import random
from datetime import datetime, timedelta
from azure.identity import DefaultAzureCredential, ClientSecretCredential
from azure.storage.filedatalake import (
    DataLakeServiceClient,
    DataLakeFileClient,
    FileSystemClient,
)
from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError


# ─── Configuration ────────────────────────────────────────────────────────────

STORAGE_ACCOUNT_NAME = os.environ.get("AZURE_STORAGE_ACCOUNT_NAME", "your-adls-account")
TENANT_ID            = os.environ.get("AZURE_TENANT_ID")
CLIENT_ID            = os.environ.get("AZURE_CLIENT_ID")
CLIENT_SECRET        = os.environ.get("AZURE_CLIENT_SECRET")

ZONES = ["raw", "processed", "curated", "archive"]


# ─── Authentication ───────────────────────────────────────────────────────────

def get_service_client() -> DataLakeServiceClient:
    """
    Returns an authenticated DataLakeServiceClient.
    Uses ClientSecretCredential if env vars are set, otherwise DefaultAzureCredential
    (which supports managed identity, VS Code login, Azure CLI, etc.)
    """
    account_url = f"https://{STORAGE_ACCOUNT_NAME}.dfs.core.windows.net"

    if TENANT_ID and CLIENT_ID and CLIENT_SECRET:
        credential = ClientSecretCredential(
            tenant_id=TENANT_ID,
            client_id=CLIENT_ID,
            client_secret=CLIENT_SECRET,
        )
        print(f"  Auth: ClientSecretCredential (service principal)")
    else:
        credential = DefaultAzureCredential()
        print(f"  Auth: DefaultAzureCredential (CLI / managed identity)")

    return DataLakeServiceClient(account_url=account_url, credential=credential)


# ─── Filesystem (Container) Operations ───────────────────────────────────────

def create_filesystems(service_client: DataLakeServiceClient) -> dict:
    """Create the four zone filesystems if they don't already exist."""
    print("\n[1] Creating filesystems (zones)...")
    filesystems = {}

    for zone in ZONES:
        try:
            fs_client = service_client.create_file_system(file_system=zone)
            print(f"  ✓ Created filesystem: {zone}")
        except ResourceExistsError:
            fs_client = service_client.get_file_system_client(file_system=zone)
            print(f"  ~ Already exists: {zone}")

        filesystems[zone] = fs_client

    return filesystems


# ─── Directory Structure ──────────────────────────────────────────────────────

def create_directory_structure(filesystems: dict) -> None:
    """Create the zone-specific directory hierarchy."""
    print("\n[2] Creating directory structure...")

    raw_dirs = [
        "orders/year=2024/month=01",
        "orders/year=2024/month=02",
        "customers/year=2024/month=01",
        "products/year=2024/month=01",
        "transactions/year=2024/month=01",
    ]

    processed_dirs = [
        "orders/year=2024/month=01",
        "customers/year=2024/month=01",
        "products/year=2024/month=01",
    ]

    curated_dirs = [
        "daily_revenue",
        "customer_segments",
        "product_performance",
    ]

    archive_dirs = [
        "orders/year=2023",
        "customers/year=2023",
    ]

    dir_map = {
        "raw":       raw_dirs,
        "processed": processed_dirs,
        "curated":   curated_dirs,
        "archive":   archive_dirs,
    }

    for zone, dirs in dir_map.items():
        fs_client = filesystems[zone]
        for directory in dirs:
            try:
                dir_client = fs_client.create_directory(directory)
                print(f"  ✓ {zone}/{directory}")
            except ResourceExistsError:
                print(f"  ~ {zone}/{directory} (exists)")


# ─── ACL Management ───────────────────────────────────────────────────────────

def set_directory_acls(filesystems: dict, ingest_oid: str = None, process_oid: str = None) -> None:
    """
    Set POSIX-style ACLs on zone directories.
    If OIDs are not provided, demonstrates the ACL format only.
    """
    print("\n[3] Setting directory ACLs...")

    # Default ACL entries (owner=rwx, group=r-x, other=---)
    default_acl = "user::rwx,group::r-x,other::---"

    # If service principal OIDs are provided, add named user entries
    if ingest_oid:
        raw_acl = f"{default_acl},user:{ingest_oid}:rwx,default:user:{ingest_oid}:rwx"
    else:
        raw_acl = default_acl
        print("  ⚠ No ingest SP OID provided — using default ACL for raw/")

    if process_oid:
        processed_acl = f"{default_acl},user:{process_oid}:rwx,default:user:{process_oid}:rwx"
    else:
        processed_acl = default_acl
        print("  ⚠ No process SP OID provided — using default ACL for processed/")

    # Set ACL on raw/ root
    raw_dir = filesystems["raw"].get_directory_client("/")
    raw_dir.set_access_control(acl=raw_acl)
    print(f"  ✓ raw/ ACL: {raw_acl}")

    # Set ACL on processed/ root
    proc_dir = filesystems["processed"].get_directory_client("/")
    proc_dir.set_access_control(acl=processed_acl)
    print(f"  ✓ processed/ ACL: {processed_acl}")

    # Curated is read-only for most consumers
    curated_acl = "user::rwx,group::r-x,other::r--"
    cur_dir = filesystems["curated"].get_directory_client("/")
    cur_dir.set_access_control(acl=curated_acl)
    print(f"  ✓ curated/ ACL: {curated_acl}")

    # Archive is read-only
    archive_acl = "user::rwx,group::r--,other::---"
    arch_dir = filesystems["archive"].get_directory_client("/")
    arch_dir.set_access_control(acl=archive_acl)
    print(f"  ✓ archive/ ACL: {archive_acl}")


# ─── Sample Data Generation ───────────────────────────────────────────────────

def generate_sample_orders(num_records: int = 50) -> str:
    """Generate sample CSV order data."""
    products = ["Laptop", "Mouse", "Keyboard", "Monitor", "Headset", "Webcam", "Desk"]
    regions  = ["North", "South", "East", "West", "Central"]

    rows = ["order_id,customer_id,product,amount,region,order_date"]
    base_date = datetime(2024, 1, 1)

    for i in range(1, num_records + 1):
        order_date = base_date + timedelta(days=random.randint(0, 30))
        rows.append(
            f"ORD-{i:05d},"
            f"CUST-{random.randint(1, 200):04d},"
            f"{random.choice(products)},"
            f"{round(random.uniform(10.0, 2000.0), 2)},"
            f"{random.choice(regions)},"
            f"{order_date.strftime('%Y-%m-%d')}"
        )

    return "\n".join(rows)


def generate_sample_customers(num_records: int = 20) -> str:
    """Generate sample CSV customer data."""
    segments = ["Premium", "Standard", "Basic"]
    rows = ["customer_id,name,email,segment,signup_date"]

    for i in range(1, num_records + 1):
        rows.append(
            f"CUST-{i:04d},"
            f"Customer {i},"
            f"customer{i}@example.com,"
            f"{random.choice(segments)},"
            f"2024-01-{random.randint(1, 28):02d}"
        )

    return "\n".join(rows)


# ─── Upload Sample Data ───────────────────────────────────────────────────────

def upload_sample_data(filesystems: dict) -> None:
    """Upload sample CSV files to the raw zone."""
    print("\n[4] Uploading sample data to raw/...")

    # Upload orders CSV
    orders_data = generate_sample_orders(50)
    orders_bytes = orders_data.encode("utf-8")

    file_client = filesystems["raw"].get_file_client(
        "orders/year=2024/month=01/orders_20240101.csv"
    )
    file_client.upload_data(orders_bytes, overwrite=True, length=len(orders_bytes))
    print(f"  ✓ Uploaded raw/orders/year=2024/month=01/orders_20240101.csv ({len(orders_bytes)} bytes)")

    # Upload second batch
    orders_data_2 = generate_sample_orders(30)
    orders_bytes_2 = orders_data_2.encode("utf-8")
    file_client_2 = filesystems["raw"].get_file_client(
        "orders/year=2024/month=01/orders_20240115.csv"
    )
    file_client_2.upload_data(orders_bytes_2, overwrite=True, length=len(orders_bytes_2))
    print(f"  ✓ Uploaded raw/orders/year=2024/month=01/orders_20240115.csv ({len(orders_bytes_2)} bytes)")

    # Upload customers CSV
    customers_data = generate_sample_customers(20)
    customers_bytes = customers_data.encode("utf-8")
    cust_client = filesystems["raw"].get_file_client(
        "customers/year=2024/month=01/customers_20240101.csv"
    )
    cust_client.upload_data(customers_bytes, overwrite=True, length=len(customers_bytes))
    print(f"  ✓ Uploaded raw/customers/year=2024/month=01/customers_20240101.csv ({len(customers_bytes)} bytes)")

    # Upload a metadata JSON file
    metadata = {
        "source": "orders_system",
        "ingestion_timestamp": datetime.utcnow().isoformat(),
        "record_count": 50,
        "schema_version": "1.0",
        "columns": ["order_id", "customer_id", "product", "amount", "region", "order_date"],
    }
    meta_bytes = json.dumps(metadata, indent=2).encode("utf-8")
    meta_client = filesystems["raw"].get_file_client(
        "orders/year=2024/month=01/_metadata.json"
    )
    meta_client.upload_data(meta_bytes, overwrite=True, length=len(meta_bytes))
    print(f"  ✓ Uploaded raw/orders/year=2024/month=01/_metadata.json")


# ─── List Data Lake Structure ─────────────────────────────────────────────────

def list_data_lake_structure(service_client: DataLakeServiceClient) -> None:
    """Print the full data lake directory tree."""
    print("\n[5] Data Lake Structure:")
    print(f"  adls://{STORAGE_ACCOUNT_NAME}/")

    for zone in ZONES:
        try:
            fs_client = service_client.get_file_system_client(file_system=zone)
            print(f"  ├── {zone}/")

            paths = list(fs_client.get_paths(recursive=True))
            for i, path in enumerate(paths):
                is_last = (i == len(paths) - 1)
                prefix = "  │   └── " if is_last else "  │   ├── "
                icon = "📁" if path.is_directory else "📄"
                size_str = f" ({path.content_length:,} bytes)" if not path.is_directory and path.content_length else ""
                print(f"  │   ├── {icon} {path.name}{size_str}")

        except Exception as e:
            print(f"  ├── {zone}/ (error: {e})")

    print()


# ─── Read and Verify Uploaded Data ────────────────────────────────────────────

def verify_uploaded_data(filesystems: dict) -> None:
    """Read back the uploaded orders file and print first 5 rows."""
    print("\n[6] Verifying uploaded data (first 5 rows of orders):")

    file_client = filesystems["raw"].get_file_client(
        "orders/year=2024/month=01/orders_20240101.csv"
    )

    download = file_client.download_file()
    content = download.readall().decode("utf-8")
    lines = content.strip().split("\n")

    print(f"  Total rows (including header): {len(lines)}")
    print()
    for line in lines[:6]:
        print(f"  {line}")


# ─── Get ACL Info ─────────────────────────────────────────────────────────────

def print_acl_info(filesystems: dict) -> None:
    """Print ACL information for each zone root directory."""
    print("\n[7] ACL Information:")

    for zone in ZONES:
        try:
            dir_client = filesystems[zone].get_directory_client("/")
            acl_props = dir_client.get_access_control()
            print(f"  {zone}/")
            print(f"    owner : {acl_props.get('owner', 'N/A')}")
            print(f"    group : {acl_props.get('group', 'N/A')}")
            print(f"    acl   : {acl_props.get('acl', 'N/A')}")
        except Exception as e:
            print(f"  {zone}/ — could not read ACL: {e}")


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  Azure Data Lake Storage Gen2 — Setup Script")
    print(f"  Account: {STORAGE_ACCOUNT_NAME}")
    print(f"  Time   : {datetime.utcnow().isoformat()}Z")
    print("=" * 60)

    # Authenticate
    print("\n[0] Authenticating...")
    service_client = get_service_client()
    print(f"  ✓ Connected to {STORAGE_ACCOUNT_NAME}.dfs.core.windows.net")

    # Create filesystems
    filesystems = create_filesystems(service_client)

    # Create directory structure
    create_directory_structure(filesystems)

    # Set ACLs (pass OIDs if you have them)
    ingest_oid  = os.environ.get("INGEST_SP_OID")
    process_oid = os.environ.get("PROCESS_SP_OID")
    set_directory_acls(filesystems, ingest_oid=ingest_oid, process_oid=process_oid)

    # Upload sample data
    upload_sample_data(filesystems)

    # List structure
    list_data_lake_structure(service_client)

    # Verify data
    verify_uploaded_data(filesystems)

    # Print ACL info
    print_acl_info(filesystems)

    print("\n" + "=" * 60)
    print("  ✅ Data Lake setup complete!")
    print(f"  DFS endpoint: https://{STORAGE_ACCOUNT_NAME}.dfs.core.windows.net")
    print("  Zones: raw (Bronze) | processed (Silver) | curated (Gold) | archive")
    print("=" * 60)


if __name__ == "__main__":
    main()
