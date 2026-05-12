"""
pipeline_trigger.py — Trigger and monitor GitHub Actions workflows.

Usage:
    python pipeline_trigger.py \\
        --repo owner/repo-name \\
        --workflow terraform-apply.yml \\
        --token <github-pat> \\
        --ref main

    python pipeline_trigger.py \\
        --repo owner/repo-name \\
        --workflow terraform-plan.yml \\
        --token <github-pat> \\
        --list-runs

Requirements:
    pip install requests
    GitHub PAT with: repo, workflow scopes
"""

import argparse
import sys
import time
import urllib.request
import urllib.error
import json
from datetime import datetime


BASE_URL = "https://api.github.com"


# ─────────────────────────────────────────────
# GitHub API helpers
# ─────────────────────────────────────────────

def github_request(
    method: str,
    path: str,
    token: str,
    data: dict | None = None,
) -> tuple[int, dict | list | None]:
    """Make a GitHub API request."""
    url = f"{BASE_URL}{path}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
    }

    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req) as response:
            content = response.read()
            if content:
                return response.status, json.loads(content)
            return response.status, None
    except urllib.error.HTTPError as e:
        content = e.read()
        try:
            error_data = json.loads(content)
        except Exception:
            error_data = {"message": content.decode()}
        return e.code, error_data


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
# Workflow operations
# ─────────────────────────────────────────────

def trigger_workflow(
    repo: str,
    workflow: str,
    token: str,
    ref: str = "main",
    inputs: dict | None = None,
) -> bool:
    """Trigger a workflow_dispatch event."""
    section(f"Triggering Workflow: {workflow}")
    info(f"Repository: {repo}")
    info(f"Ref: {ref}")

    payload = {"ref": ref}
    if inputs:
        payload["inputs"] = inputs
        info(f"Inputs: {inputs}")

    status, response = github_request(
        "POST",
        f"/repos/{repo}/actions/workflows/{workflow}/dispatches",
        token,
        payload,
    )

    if status == 204:
        ok("Workflow triggered successfully")
        return True
    else:
        fail(f"Failed to trigger workflow (HTTP {status})")
        if response:
            fail(f"Error: {response.get('message', 'Unknown error')}")
        return False


def get_latest_run(repo: str, workflow: str, token: str, ref: str = "main") -> dict | None:
    """Get the most recent workflow run."""
    status, response = github_request(
        "GET",
        f"/repos/{repo}/actions/workflows/{workflow}/runs?branch={ref}&per_page=5",
        token,
    )

    if status != 200 or not response:
        return None

    runs = response.get("workflow_runs", [])
    return runs[0] if runs else None


def list_runs(repo: str, workflow: str, token: str, limit: int = 10) -> None:
    """List recent workflow runs."""
    section(f"Recent Runs: {workflow}")

    status, response = github_request(
        "GET",
        f"/repos/{repo}/actions/workflows/{workflow}/runs?per_page={limit}",
        token,
    )

    if status != 200 or not response:
        fail(f"Failed to list runs (HTTP {status})")
        return

    runs = response.get("workflow_runs", [])
    if not runs:
        warn("No runs found")
        return

    print(f"\n  {'#':<6} {'Status':<12} {'Conclusion':<12} {'Branch':<20} {'Started':<25} {'Duration'}")
    print(f"  {'─' * 90}")

    for run in runs:
        run_id = str(run["run_number"])
        status_val = run["status"]
        conclusion = run.get("conclusion") or "—"
        branch = run.get("head_branch", "?")[:20]
        started = run.get("created_at", "?")[:19].replace("T", " ")

        # Calculate duration
        if run.get("created_at") and run.get("updated_at"):
            try:
                start = datetime.fromisoformat(run["created_at"].replace("Z", "+00:00"))
                end = datetime.fromisoformat(run["updated_at"].replace("Z", "+00:00"))
                duration = str(end - start).split(".")[0]
            except Exception:
                duration = "?"
        else:
            duration = "?"

        # Color by conclusion
        if conclusion == "success":
            c_color = "\033[92m"
        elif conclusion in ("failure", "cancelled"):
            c_color = "\033[91m"
        elif status_val == "in_progress":
            c_color = "\033[93m"
        else:
            c_color = "\033[0m"

        print(f"  {run_id:<6} {status_val:<12} {c_color}{conclusion:<12}\033[0m {branch:<20} {started:<25} {duration}")


def poll_run(repo: str, run_id: int, token: str, timeout: int = 600) -> str:
    """Poll a workflow run until it completes."""
    section(f"Monitoring Run #{run_id}")
    info(f"Timeout: {timeout}s")
    info(f"URL: https://github.com/{repo}/actions/runs/{run_id}")

    start_time = time.time()
    last_status = None

    while time.time() - start_time < timeout:
        status, response = github_request(
            "GET",
            f"/repos/{repo}/actions/runs/{run_id}",
            token,
        )

        if status != 200 or not response:
            warn(f"Failed to get run status (HTTP {status})")
            time.sleep(10)
            continue

        run_status = response.get("status")
        conclusion = response.get("conclusion")
        elapsed = int(time.time() - start_time)

        if run_status != last_status:
            print(f"\n  [{elapsed:3d}s] Status: {run_status}", end="", flush=True)
            last_status = run_status

        if run_status == "completed":
            print()
            if conclusion == "success":
                ok(f"Workflow completed successfully (took {elapsed}s)")
            else:
                fail(f"Workflow {conclusion} (took {elapsed}s)")
            return conclusion or "unknown"

        print(".", end="", flush=True)
        time.sleep(15)

    print()
    warn(f"Timeout after {timeout}s — workflow still running")
    return "timeout"


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="GitHub Actions workflow trigger and monitor")
    parser.add_argument("--repo", required=True, help="GitHub repo (owner/name)")
    parser.add_argument("--workflow", required=True, help="Workflow filename (e.g. terraform-apply.yml)")
    parser.add_argument("--token", required=True, help="GitHub Personal Access Token")
    parser.add_argument("--ref", default="main", help="Branch/tag/SHA to run on (default: main)")
    parser.add_argument("--inputs", help="JSON string of workflow inputs (e.g. '{\"confirm\":\"apply\"}')")
    parser.add_argument("--list-runs", action="store_true", help="List recent runs and exit")
    parser.add_argument("--poll-run", type=int, help="Poll a specific run ID")
    parser.add_argument("--timeout", type=int, default=600, help="Poll timeout in seconds (default: 600)")
    parser.add_argument("--no-poll", action="store_true", help="Trigger without waiting for completion")
    args = parser.parse_args()

    print("\n╔══════════════════════════════════════════════════════════╗")
    print("║           GitHub Actions Pipeline Trigger                ║")
    print("╚══════════════════════════════════════════════════════════╝")

    if args.list_runs:
        list_runs(args.repo, args.workflow, args.token)
        return

    if args.poll_run:
        conclusion = poll_run(args.repo, args.poll_run, args.token, args.timeout)
        sys.exit(0 if conclusion == "success" else 1)

    # Parse inputs
    inputs = None
    if args.inputs:
        try:
            inputs = json.loads(args.inputs)
        except json.JSONDecodeError as e:
            fail(f"Invalid JSON for --inputs: {e}")
            sys.exit(1)

    # Trigger workflow
    triggered = trigger_workflow(args.repo, args.workflow, args.token, args.ref, inputs)
    if not triggered:
        sys.exit(1)

    if args.no_poll:
        info("Skipping poll (--no-poll). Check GitHub Actions for results.")
        return

    # Wait a moment for the run to appear
    info("Waiting for run to appear in GitHub API...")
    time.sleep(5)

    # Find the run we just triggered
    run = get_latest_run(args.repo, args.workflow, args.token, args.ref)
    if not run:
        warn("Could not find the triggered run. Check GitHub Actions manually.")
        sys.exit(0)

    run_id = run["id"]
    run_number = run["run_number"]
    info(f"Found run #{run_number} (ID: {run_id})")
    info(f"View at: https://github.com/{args.repo}/actions/runs/{run_id}")

    # Poll until complete
    conclusion = poll_run(args.repo, run_id, args.token, args.timeout)

    print(f"\n{'═' * 60}")
    if conclusion == "success":
        print(f"  \033[92m✔  Pipeline succeeded\033[0m")
    elif conclusion == "timeout":
        print(f"  \033[93m⚠  Pipeline timed out — still running\033[0m")
        print(f"  View: https://github.com/{args.repo}/actions/runs/{run_id}")
    else:
        print(f"  \033[91m✘  Pipeline {conclusion}\033[0m")
        print(f"  View: https://github.com/{args.repo}/actions/runs/{run_id}")
    print(f"{'═' * 60}\n")

    sys.exit(0 if conclusion == "success" else 1)


if __name__ == "__main__":
    main()
