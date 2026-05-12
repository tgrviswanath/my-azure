"""
adf_trigger.py — Azure Data Factory Pipeline Trigger & Monitor

Triggers an ADF pipeline run, polls for completion, and prints ETL statistics.

Requirements:
    pip install azure-identity azure-mgmt-datafactory

Usage:
    export AZURE_SUBSCRIPTION_ID="your-subscription-id"
    export ADF_RESOURCE_GROUP="rg-adf-etl-lab"
    export ADF_FACTORY_NAME="adf-etl-lab"
    export ADF_PIPELINE_NAME="pl_copy_orders"
    python adf_trigger.py
"""

import os
import sys
import time
from datetime import datetime, timezone, timedelta
from typing import Optional

from azure.identity import DefaultAzureCredential, AzureCliCredential
from azure.mgmt.datafactory import DataFactoryManagementClient
from azure.mgmt.datafactory.models import (
    RunFilterParameters,
    RunQueryFilter,
    RunQueryFilterOperand,
    RunQueryFilterOperator,
)
from azure.core.exceptions import AzureError


# ── Configuration ─────────────────────────────────────────────────────────────

SUBSCRIPTION_ID = os.environ.get("AZURE_SUBSCRIPTION_ID", "")
RESOURCE_GROUP  = os.environ.get("ADF_RESOURCE_GROUP", "rg-adf-etl-lab")
FACTORY_NAME    = os.environ.get("ADF_FACTORY_NAME", "adf-etl-lab")
PIPELINE_NAME   = os.environ.get("ADF_PIPELINE_NAME", "pl_copy_orders")

POLL_INTERVAL_SECONDS = 10
MAX_WAIT_MINUTES      = 30


# ── Client ────────────────────────────────────────────────────────────────────

def get_adf_client(subscription_id: str) -> DataFactoryManagementClient:
    try:
        credential = DefaultAzureCredential()
        return DataFactoryManagementClient(credential, subscription_id)
    except Exception:
        credential = AzureCliCredential()
        return DataFactoryManagementClient(credential, subscription_id)


# ── Pipeline Operations ───────────────────────────────────────────────────────

def trigger_pipeline(
    client: DataFactoryManagementClient,
    resource_group: str,
    factory_name: str,
    pipeline_name: str,
    parameters: Optional[dict] = None,
) -> str:
    """
    Trigger a pipeline run and return the run ID.

    Args:
        client: ADF management client
        resource_group: Resource group name
        factory_name: Data factory name
        pipeline_name: Pipeline name to trigger
        parameters: Optional pipeline parameters dict

    Returns:
        Run ID string
    """
    print(f"  Triggering pipeline: {pipeline_name}")
    run_response = client.pipelines.create_run(
        resource_group_name=resource_group,
        factory_name=factory_name,
        pipeline_name=pipeline_name,
        parameters=parameters or {},
    )
    run_id = run_response.run_id
    print(f"  ✅ Pipeline run started. Run ID: {run_id}")
    return run_id


def poll_pipeline_run(
    client: DataFactoryManagementClient,
    resource_group: str,
    factory_name: str,
    run_id: str,
    poll_interval: int = POLL_INTERVAL_SECONDS,
    max_wait_minutes: int = MAX_WAIT_MINUTES,
) -> dict:
    """
    Poll a pipeline run until it completes or times out.

    Returns:
        Dict with final run status and statistics
    """
    print(f"\n  Polling run {run_id}...")
    start_time = time.time()
    max_wait_seconds = max_wait_minutes * 60
    last_status = None

    while True:
        elapsed = time.time() - start_time
        if elapsed > max_wait_seconds:
            print(f"\n  ⏰ Timeout after {max_wait_minutes} minutes.")
            break

        try:
            run = client.pipeline_runs.get(
                resource_group_name=resource_group,
                factory_name=factory_name,
                run_id=run_id,
            )

            status = run.status
            if status != last_status:
                timestamp = datetime.now(timezone.utc).strftime("%H:%M:%S")
                print(f"  [{timestamp}] Status: {status}")
                last_status = status

            # Terminal states
            if status in ("Succeeded", "Failed", "Cancelled"):
                return {
                    "run_id": run_id,
                    "status": status,
                    "pipeline_name": run.pipeline_name,
                    "run_start": run.run_start,
                    "run_end": run.run_end,
                    "duration_ms": run.duration_in_ms,
                    "message": run.message,
                    "parameters": run.parameters,
                }

            # Still running — show progress indicator
            dots = "." * (int(elapsed) % 4 + 1)
            print(f"  [{elapsed:.0f}s] {status}{dots}", end="\r")

        except AzureError as e:
            print(f"\n  ⚠️  Error polling run: {e}")

        time.sleep(poll_interval)

    return {"run_id": run_id, "status": "Timeout"}


def get_activity_runs(
    client: DataFactoryManagementClient,
    resource_group: str,
    factory_name: str,
    run_id: str,
) -> list:
    """Get activity-level run details for a pipeline run."""
    try:
        now = datetime.now(timezone.utc)
        filter_params = RunFilterParameters(
            last_updated_after=now - timedelta(hours=24),
            last_updated_before=now + timedelta(hours=1),
            filters=[
                RunQueryFilter(
                    operand=RunQueryFilterOperand.PIPELINE_RUN_ID,
                    operator=RunQueryFilterOperator.EQUALS,
                    values=[run_id],
                )
            ],
        )

        result = client.activity_runs.query_by_pipeline_run(
            resource_group_name=resource_group,
            factory_name=factory_name,
            run_id=run_id,
            filter_parameters=filter_params,
        )
        return list(result.value or [])
    except AzureError as e:
        print(f"  ⚠️  Error getting activity runs: {e}")
        return []


def get_recent_pipeline_runs(
    client: DataFactoryManagementClient,
    resource_group: str,
    factory_name: str,
    pipeline_name: str,
    hours_back: int = 24,
) -> list:
    """Get recent pipeline runs for statistics."""
    try:
        now = datetime.now(timezone.utc)
        filter_params = RunFilterParameters(
            last_updated_after=now - timedelta(hours=hours_back),
            last_updated_before=now + timedelta(hours=1),
            filters=[
                RunQueryFilter(
                    operand=RunQueryFilterOperand.PIPELINE_NAME,
                    operator=RunQueryFilterOperator.EQUALS,
                    values=[pipeline_name],
                )
            ],
        )

        result = client.pipeline_runs.query_by_factory(
            resource_group_name=resource_group,
            factory_name=factory_name,
            filter_parameters=filter_params,
        )
        return list(result.value or [])
    except AzureError as e:
        print(f"  ⚠️  Error getting recent runs: {e}")
        return []


# ── Report ────────────────────────────────────────────────────────────────────

def format_duration(ms: Optional[int]) -> str:
    """Format milliseconds as human-readable duration."""
    if ms is None:
        return "N/A"
    seconds = ms / 1000
    if seconds < 60:
        return f"{seconds:.1f}s"
    minutes = seconds / 60
    if minutes < 60:
        return f"{minutes:.1f}m"
    return f"{minutes / 60:.1f}h"


def print_etl_report(
    run_result: dict,
    activity_runs: list,
    recent_runs: list,
) -> None:
    """Print a formatted ETL run report."""
    print("\n" + "=" * 65)
    print("  ADF ETL PIPELINE RUN REPORT")
    print(f"  Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print("=" * 65)

    # Current run summary
    status = run_result.get("status", "Unknown")
    status_icon = "✅" if status == "Succeeded" else "❌" if status == "Failed" else "⚠️"

    print(f"\n  {status_icon} Run Status: {status}")
    print(f"  Run ID      : {run_result.get('run_id', 'N/A')}")
    print(f"  Pipeline    : {run_result.get('pipeline_name', PIPELINE_NAME)}")
    print(f"  Duration    : {format_duration(run_result.get('duration_ms'))}")

    if run_result.get("run_start"):
        print(f"  Started     : {run_result['run_start'].strftime('%Y-%m-%d %H:%M:%S UTC')}")
    if run_result.get("run_end"):
        print(f"  Ended       : {run_result['run_end'].strftime('%Y-%m-%d %H:%M:%S UTC')}")

    if run_result.get("message") and status == "Failed":
        print(f"  Error       : {run_result['message'][:150]}")

    # Activity runs breakdown
    if activity_runs:
        print(f"\n  {'─' * 55}")
        print(f"  ACTIVITY BREAKDOWN ({len(activity_runs)} activities)")
        print(f"  {'─' * 55}")

        for activity in activity_runs:
            act_status = activity.status or "Unknown"
            act_icon = "✅" if act_status == "Succeeded" else "❌"
            act_name = activity.activity_name or "Unknown"
            act_type = activity.activity_type or "Unknown"
            act_dur = format_duration(activity.duration_in_ms)

            print(f"\n  {act_icon} {act_name} ({act_type})")
            print(f"     Duration : {act_dur}")
            print(f"     Status   : {act_status}")

            # Copy activity statistics
            if hasattr(activity, "output") and activity.output:
                output = activity.output
                if isinstance(output, dict):
                    rows_read    = output.get("rowsRead", output.get("dataRead", "N/A"))
                    rows_written = output.get("rowsCopied", output.get("dataWritten", "N/A"))
                    throughput   = output.get("throughput", "N/A")
                    print(f"     Rows Read   : {rows_read:,}" if isinstance(rows_read, int) else f"     Rows Read   : {rows_read}")
                    print(f"     Rows Written: {rows_written:,}" if isinstance(rows_written, int) else f"     Rows Written: {rows_written}")
                    if throughput != "N/A":
                        print(f"     Throughput  : {throughput:.2f} MB/s" if isinstance(throughput, float) else f"     Throughput  : {throughput}")

    # Historical statistics
    if recent_runs:
        print(f"\n  {'─' * 55}")
        print(f"  LAST 24 HOURS STATISTICS ({len(recent_runs)} runs)")
        print(f"  {'─' * 55}")

        succeeded = sum(1 for r in recent_runs if r.status == "Succeeded")
        failed    = sum(1 for r in recent_runs if r.status == "Failed")
        durations = [r.duration_in_ms for r in recent_runs if r.duration_in_ms]

        print(f"  Total Runs  : {len(recent_runs)}")
        print(f"  Succeeded   : {succeeded}")
        print(f"  Failed      : {failed}")
        success_rate = (succeeded / len(recent_runs) * 100) if recent_runs else 0
        print(f"  Success Rate: {success_rate:.1f}%")

        if durations:
            avg_dur = sum(durations) / len(durations)
            min_dur = min(durations)
            max_dur = max(durations)
            print(f"  Avg Duration: {format_duration(int(avg_dur))}")
            print(f"  Min Duration: {format_duration(min_dur)}")
            print(f"  Max Duration: {format_duration(max_dur)}")

    print(f"\n{'=' * 65}\n")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print("🏭 Azure Data Factory Pipeline Trigger")
    print("=" * 65)

    if not SUBSCRIPTION_ID:
        print("❌ Error: AZURE_SUBSCRIPTION_ID environment variable not set.")
        sys.exit(1)

    print(f"  Subscription : {SUBSCRIPTION_ID}")
    print(f"  Resource Group: {RESOURCE_GROUP}")
    print(f"  Factory      : {FACTORY_NAME}")
    print(f"  Pipeline     : {PIPELINE_NAME}")

    # Initialize client
    print("\n🔐 Authenticating...")
    client = get_adf_client(SUBSCRIPTION_ID)
    print("  ✅ Authenticated")

    # Trigger pipeline
    print("\n🚀 Triggering pipeline run...")
    try:
        run_id = trigger_pipeline(
            client, RESOURCE_GROUP, FACTORY_NAME, PIPELINE_NAME
        )
    except AzureError as e:
        print(f"  ❌ Failed to trigger pipeline: {e}")
        sys.exit(1)

    # Poll for completion
    run_result = poll_pipeline_run(
        client, RESOURCE_GROUP, FACTORY_NAME, run_id
    )

    # Get activity details
    print("\n📊 Fetching activity run details...")
    activity_runs = get_activity_runs(
        client, RESOURCE_GROUP, FACTORY_NAME, run_id
    )

    # Get recent run history
    print("📈 Fetching recent run history...")
    recent_runs = get_recent_pipeline_runs(
        client, RESOURCE_GROUP, FACTORY_NAME, PIPELINE_NAME
    )

    # Print report
    print_etl_report(run_result, activity_runs, recent_runs)

    # Exit with appropriate code
    if run_result.get("status") == "Succeeded":
        print("✅ ETL pipeline completed successfully.")
        sys.exit(0)
    else:
        print(f"❌ ETL pipeline {run_result.get('status', 'unknown')}.")
        sys.exit(1)


if __name__ == "__main__":
    main()
