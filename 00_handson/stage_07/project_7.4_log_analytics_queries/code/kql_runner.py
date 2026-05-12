"""
kql_runner.py — Run KQL queries against Azure Log Analytics Workspace.

Usage:
    pip install azure-identity azure-monitor-query
    export LOG_ANALYTICS_WORKSPACE_ID="<workspace-id>"

    python code/kql_runner.py --query "AzureActivity | take 10"
    python code/kql_runner.py --file queries/activity_log_queries.kql
    python code/kql_runner.py --preset failed-ops
    python code/kql_runner.py --preset top-callers
"""

import argparse
import os
import sys
from datetime import timedelta

from azure.identity import DefaultAzureCredential
from azure.monitor.query import LogsQueryClient, LogsQueryStatus


# ── Preset queries ────────────────────────────────────────────────────────────
PRESETS = {
    "failed-ops": """
AzureActivity
| where TimeGenerated > ago(24h)
| where ActivityStatusValue == 'Failure'
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup
| order by TimeGenerated desc
| take 20
""",
    "top-callers": """
AzureActivity
| where TimeGenerated > ago(24h)
| summarize OperationCount = count() by Caller
| order by OperationCount desc
| take 10
""",
    "role-changes": """
AzureActivity
| where TimeGenerated > ago(7d)
| where OperationNameValue contains 'roleAssignments'
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup
| order by TimeGenerated desc
""",
    "resource-deletions": """
AzureActivity
| where TimeGenerated > ago(7d)
| where OperationNameValue endswith '/delete'
| where ActivityStatusValue == 'Success'
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup
| order by TimeGenerated desc
""",
    "hourly-trend": """
AzureActivity
| where TimeGenerated > ago(7d)
| summarize count() by bin(TimeGenerated, 1h), ActivityStatusValue
| order by TimeGenerated desc
""",
}


def run_query(workspace_id: str, query: str, timespan: timedelta = timedelta(days=1)) -> None:
    """Execute a KQL query and print results."""
    credential = DefaultAzureCredential()
    client = LogsQueryClient(credential)

    print(f"\n[*] Running query against workspace: {workspace_id}")
    print(f"    Timespan: last {timespan.days} day(s)\n")

    response = client.query_workspace(
        workspace_id=workspace_id,
        query=query,
        timespan=timespan,
    )

    if response.status == LogsQueryStatus.SUCCESS:
        for table in response.tables:
            # Print column headers
            headers = [col.name for col in table.columns]
            col_widths = [max(len(h), 15) for h in headers]

            header_line = "  " + "  ".join(f"{h:<{w}}" for h, w in zip(headers, col_widths))
            print(header_line)
            print("  " + "-" * (len(header_line) - 2))

            # Print rows
            for row in table.rows:
                row_line = "  " + "  ".join(
                    f"{str(v)[:w]:<{w}}" for v, w in zip(row, col_widths)
                )
                print(row_line)

            print(f"\n  Rows returned: {len(table.rows)}")

    elif response.status == LogsQueryStatus.PARTIAL:
        print("[WARN] Partial results returned.")
        for table in response.partial_data:
            for row in table.rows:
                print(f"  {row}")
        if response.partial_error:
            print(f"[ERR] {response.partial_error}")
    else:
        print(f"[ERR] Query failed: {response}")


def main():
    parser = argparse.ArgumentParser(
        description="Run KQL queries against Log Analytics Workspace",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""Presets: {', '.join(PRESETS.keys())}

Examples:
  python code/kql_runner.py --preset failed-ops
  python code/kql_runner.py --preset top-callers
  python code/kql_runner.py --query "AzureActivity | take 5"
  python code/kql_runner.py --file queries/activity_log_queries.kql"""
    )
    parser.add_argument("--workspace-id", default=os.environ.get("LOG_ANALYTICS_WORKSPACE_ID"),
                        help="Log Analytics workspace ID (or set LOG_ANALYTICS_WORKSPACE_ID env var)")
    parser.add_argument("--query",   help="KQL query string")
    parser.add_argument("--file",    help="Path to .kql file")
    parser.add_argument("--preset",  choices=list(PRESETS.keys()), help="Use a preset query")
    parser.add_argument("--days",    type=int, default=1, help="Timespan in days (default: 1)")
    args = parser.parse_args()

    if not args.workspace_id:
        print("[ERR] Set --workspace-id or LOG_ANALYTICS_WORKSPACE_ID environment variable")
        sys.exit(1)

    if args.preset:
        query = PRESETS[args.preset]
    elif args.file:
        with open(args.file) as f:
            query = f.read()
    elif args.query:
        query = args.query
    else:
        print("[ERR] Provide --query, --file, or --preset")
        sys.exit(1)

    run_query(args.workspace_id, query, timedelta(days=args.days))


if __name__ == "__main__":
    main()
