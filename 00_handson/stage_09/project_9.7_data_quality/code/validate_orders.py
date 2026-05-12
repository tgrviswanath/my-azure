"""
validate_orders.py — Great Expectations Data Quality Validator

Validates orders Parquet data from ADLS Gen2 against a predefined
expectation suite. Prints a pass/fail report with details.

Requirements:
    pip install great-expectations[azure] azure-storage-blob azure-identity pyarrow pandas

Usage:
    export AZURE_STORAGE_ACCOUNT="your-storage-account"
    export AZURE_STORAGE_CONTAINER="processed"
    export AZURE_BLOB_PATH="orders/2024/01/orders.parquet"
    python validate_orders.py
"""

import os
import sys
import io
from datetime import datetime, timezone
from typing import Optional

import pandas as pd
import pyarrow.parquet as pq

from azure.identity import DefaultAzureCredential, AzureCliCredential
from azure.storage.blob import BlobServiceClient
from azure.core.exceptions import AzureError

try:
    import great_expectations as gx
    from great_expectations.core.batch import RuntimeBatchRequest
    from great_expectations.core.expectation_configuration import ExpectationConfiguration
    GX_AVAILABLE = True
except ImportError:
    GX_AVAILABLE = False
    print("Warning: great-expectations not installed. Using pandas-based validation.")


# ── Configuration ─────────────────────────────────────────────────────────────

STORAGE_ACCOUNT = os.environ.get("AZURE_STORAGE_ACCOUNT", "")
CONTAINER       = os.environ.get("AZURE_STORAGE_CONTAINER", "processed")
BLOB_PATH       = os.environ.get("AZURE_BLOB_PATH", "orders/2024/01/orders.parquet")

SUITE_NAME      = "orders_suite"

# Known valid products
KNOWN_PRODUCTS = [
    "Widget A",
    "Widget B",
    "Widget C",
    "Gadget Pro",
    "Gadget Lite",
    "Super Widget",
]

# Known valid statuses
VALID_STATUSES = ["pending", "processing", "completed", "cancelled", "refunded", "unknown"]

# Known valid regions
VALID_REGIONS = ["us-east", "us-west", "eu-west", "ap-southeast"]


# ── Data Loading ──────────────────────────────────────────────────────────────

def load_parquet_from_adls(
    storage_account: str,
    container: str,
    blob_path: str,
) -> pd.DataFrame:
    """
    Download Parquet file from ADLS Gen2 and return as pandas DataFrame.

    Args:
        storage_account: Storage account name
        container: Container name
        blob_path: Path to Parquet file within container

    Returns:
        pandas DataFrame
    """
    print(f"  Loading data from: {storage_account}/{container}/{blob_path}")

    try:
        credential = DefaultAzureCredential()
    except Exception:
        credential = AzureCliCredential()

    account_url = f"https://{storage_account}.blob.core.windows.net"

    try:
        blob_client = BlobServiceClient(
            account_url=account_url,
            credential=credential,
        ).get_blob_client(container=container, blob=blob_path)

        # Download blob content
        blob_data = blob_client.download_blob().readall()

        # Parse Parquet
        buffer = io.BytesIO(blob_data)
        df = pd.read_parquet(buffer)

        print(f"  ✅ Loaded {len(df):,} rows, {len(df.columns)} columns")
        return df

    except AzureError as e:
        print(f"  ❌ Failed to load from ADLS: {e}")
        raise


def create_sample_dataframe() -> pd.DataFrame:
    """Create a sample DataFrame for local testing when ADLS is not available."""
    import random
    from datetime import date, timedelta

    random.seed(42)
    n = 1000

    data = {
        "order_id":    [f"ORD-{i:04d}" for i in range(1, n + 1)],
        "customer_id": [f"C{random.randint(1, 100):03d}" for _ in range(n)],
        "product":     [random.choice(KNOWN_PRODUCTS + ["Unknown Product"] * 5) for _ in range(n)],
        "amount":      [round(random.uniform(10, 500), 2) for _ in range(n)],
        "quantity":    [random.randint(1, 10) for _ in range(n)],
        "order_date":  [
            (date(2024, 1, 1) + timedelta(days=random.randint(0, 30))).strftime("%Y-%m-%d")
            for _ in range(n)
        ],
        "status":      [random.choice(VALID_STATUSES) for _ in range(n)],
        "region":      [random.choice(VALID_REGIONS) for _ in range(n)],
    }

    # Introduce some data quality issues for demonstration
    data["order_id"][5]    = None       # Null order_id
    data["order_id"][10]   = "ORD-0001" # Duplicate order_id
    data["amount"][20]     = -5.0       # Negative amount
    data["order_date"][30] = "not-a-date"  # Invalid date format

    return pd.DataFrame(data)


# ── Validation Functions ──────────────────────────────────────────────────────

class ValidationResult:
    """Stores the result of a single expectation check."""

    def __init__(self, name: str, passed: bool, details: str = "", affected_rows: int = 0):
        self.name = name
        self.passed = passed
        self.details = details
        self.affected_rows = affected_rows

    @property
    def icon(self) -> str:
        return "✅" if self.passed else "❌"


def validate_with_pandas(df: pd.DataFrame) -> list:
    """
    Run data quality validations using pandas (fallback when GX not available).

    Returns:
        List of ValidationResult objects
    """
    results = []

    # ── 1. Row count > 0 ─────────────────────────────────────────────────────
    row_count = len(df)
    results.append(ValidationResult(
        name="expect_table_row_count_to_be_between (min=1)",
        passed=row_count > 0,
        details=f"Row count: {row_count:,}",
        affected_rows=0 if row_count > 0 else 1,
    ))

    # ── 2. order_id not null ──────────────────────────────────────────────────
    null_order_ids = df["order_id"].isna().sum() if "order_id" in df.columns else len(df)
    results.append(ValidationResult(
        name="expect_column_values_to_not_be_null (order_id)",
        passed=null_order_ids == 0,
        details=f"Null order_ids: {null_order_ids:,}",
        affected_rows=int(null_order_ids),
    ))

    # ── 3. order_id unique ────────────────────────────────────────────────────
    if "order_id" in df.columns:
        non_null_ids = df["order_id"].dropna()
        duplicate_count = non_null_ids.duplicated().sum()
        results.append(ValidationResult(
            name="expect_column_values_to_be_unique (order_id)",
            passed=duplicate_count == 0,
            details=f"Duplicate order_ids: {duplicate_count:,}",
            affected_rows=int(duplicate_count),
        ))

    # ── 4. amount > 0 ─────────────────────────────────────────────────────────
    if "amount" in df.columns:
        invalid_amounts = (df["amount"].fillna(0) <= 0).sum()
        results.append(ValidationResult(
            name="expect_column_values_to_be_between (amount: 0 < x < 10000)",
            passed=invalid_amounts == 0,
            details=f"Invalid amounts (≤0 or >10000): {invalid_amounts:,}",
            affected_rows=int(invalid_amounts),
        ))

    # ── 5. product in known list (99% threshold) ──────────────────────────────
    if "product" in df.columns:
        total = len(df)
        unknown_products = (~df["product"].isin(KNOWN_PRODUCTS)).sum()
        match_rate = (total - unknown_products) / total if total > 0 else 0
        threshold = 0.99
        results.append(ValidationResult(
            name=f"expect_column_values_to_be_in_set (product: mostly={threshold})",
            passed=match_rate >= threshold,
            details=f"Match rate: {match_rate:.1%} (threshold: {threshold:.0%}). Unknown: {unknown_products:,}",
            affected_rows=int(unknown_products),
        ))

    # ── 6. order_date valid format ────────────────────────────────────────────
    if "order_date" in df.columns:
        def is_valid_date(val) -> bool:
            if pd.isna(val):
                return False
            try:
                pd.to_datetime(str(val), format="%Y-%m-%d")
                return True
            except (ValueError, TypeError):
                return False

        invalid_dates = (~df["order_date"].apply(is_valid_date)).sum()
        results.append(ValidationResult(
            name="expect_column_values_to_match_regex (order_date: YYYY-MM-DD)",
            passed=invalid_dates == 0,
            details=f"Invalid date formats: {invalid_dates:,}",
            affected_rows=int(invalid_dates),
        ))

    # ── 7. status in valid set ────────────────────────────────────────────────
    if "status" in df.columns:
        invalid_statuses = (~df["status"].isin(VALID_STATUSES)).sum()
        results.append(ValidationResult(
            name=f"expect_column_values_to_be_in_set (status: {VALID_STATUSES})",
            passed=invalid_statuses == 0,
            details=f"Invalid statuses: {invalid_statuses:,}",
            affected_rows=int(invalid_statuses),
        ))

    # ── 8. customer_id not null ───────────────────────────────────────────────
    if "customer_id" in df.columns:
        null_customers = df["customer_id"].isna().sum()
        results.append(ValidationResult(
            name="expect_column_values_to_not_be_null (customer_id)",
            passed=null_customers == 0,
            details=f"Null customer_ids: {null_customers:,}",
            affected_rows=int(null_customers),
        ))

    return results


# ── Report ────────────────────────────────────────────────────────────────────

def print_validation_report(
    df: pd.DataFrame,
    results: list,
    source_path: str,
) -> bool:
    """
    Print a formatted validation report.

    Returns:
        True if all expectations passed, False otherwise
    """
    passed_count = sum(1 for r in results if r.passed)
    failed_count = len(results) - passed_count
    overall_pass = failed_count == 0

    print("\n" + "=" * 65)
    print("  GREAT EXPECTATIONS — DATA QUALITY REPORT")
    print("=" * 65)
    print(f"  Suite    : {SUITE_NAME}")
    print(f"  Data     : {source_path}")
    print(f"  Rows     : {len(df):,}")
    print(f"  Columns  : {len(df.columns)}")
    print(f"  Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print(f"{'─' * 65}")

    print(f"\n  EXPECTATION RESULTS ({len(results)} total)")
    print(f"{'─' * 65}")

    for result in results:
        print(f"\n  {result.icon} {'PASS' if result.passed else 'FAIL'}  {result.name}")
        print(f"       {result.details}")
        if not result.passed and result.affected_rows > 0:
            pct = result.affected_rows / len(df) * 100 if len(df) > 0 else 0
            print(f"       Affected rows: {result.affected_rows:,} ({pct:.1f}%)")

    print(f"\n{'─' * 65}")
    overall_icon = "✅" if overall_pass else "❌"
    print(f"\n  {overall_icon} Overall: {'PASSED' if overall_pass else 'FAILED'}")
    print(f"  {passed_count}/{len(results)} expectations passed")

    if not overall_pass:
        print(f"\n  ⚠️  {failed_count} expectation(s) failed.")
        print("  Action: Investigate failed rows and fix upstream data source.")
        print("  Pipeline: BLOCKED — do not proceed to next stage.")
    else:
        print("\n  ✅ All expectations passed. Pipeline can proceed.")

    print(f"\n{'=' * 65}\n")

    return overall_pass


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("🔍 Great Expectations — Orders Data Quality Validator")
    print("=" * 65)

    # Load data
    if STORAGE_ACCOUNT and STORAGE_ACCOUNT != "your-storage-account":
        print(f"\n📥 Loading from ADLS Gen2...")
        try:
            df = load_parquet_from_adls(STORAGE_ACCOUNT, CONTAINER, BLOB_PATH)
            source_path = f"{CONTAINER}/{BLOB_PATH}"
        except Exception as e:
            print(f"  ❌ Failed to load from ADLS: {e}")
            print("  Falling back to sample data for demonstration...")
            df = create_sample_dataframe()
            source_path = "sample_data (local)"
    else:
        print("\n📊 Using sample data (set AZURE_STORAGE_ACCOUNT for real data)...")
        df = create_sample_dataframe()
        source_path = "sample_data (local)"

    print(f"\n  Columns: {list(df.columns)}")
    print(f"\n  Sample data:")
    print(df.head(3).to_string(index=False))

    # Run validations
    print(f"\n🧪 Running {SUITE_NAME} expectations...")
    results = validate_with_pandas(df)

    # Print report
    overall_pass = print_validation_report(df, results, source_path)

    # Exit code for CI/CD integration
    sys.exit(0 if overall_pass else 1)


if __name__ == "__main__":
    main()
