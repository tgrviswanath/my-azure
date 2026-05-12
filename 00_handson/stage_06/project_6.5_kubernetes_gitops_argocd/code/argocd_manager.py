"""
argocd_manager.py — Manage ArgoCD applications via CLI wrapper.

Usage:
    pip install subprocess (stdlib)
    # Requires: argocd CLI installed and logged in
    # argocd login localhost:8080 --username admin --password <pass> --insecure

    python code/argocd_manager.py status
    python code/argocd_manager.py sync   --app handson-app
    python code/argocd_manager.py diff   --app handson-app
    python code/argocd_manager.py rollback --app handson-app --revision 3
"""

import argparse
import subprocess
import sys


def run_argocd(args: list[str], capture: bool = False) -> tuple[int, str]:
    cmd = ["argocd"] + args
    print(f"  $ argocd {' '.join(args)}")
    if capture:
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.returncode, result.stdout
    return subprocess.run(cmd).returncode, ""


def cmd_status() -> int:
    """List all ArgoCD applications and their sync status."""
    print(f"\n{'='*60}")
    print(f"  ArgoCD Application Status")
    print(f"{'='*60}\n")
    rc, _ = run_argocd(["app", "list"])
    return rc


def cmd_sync(app: str, prune: bool = False) -> int:
    """Sync an ArgoCD application to match Git state."""
    print(f"\n[*] Syncing application: {app}")
    args = ["app", "sync", app]
    if prune:
        args.append("--prune")
    rc, _ = run_argocd(args)
    if rc == 0:
        print(f"[+] {app} synced successfully.")
        run_argocd(["app", "get", app])
    else:
        print(f"[ERR] Sync failed for {app}.")
    return rc


def cmd_diff(app: str) -> int:
    """Show diff between Git state and live cluster state."""
    print(f"\n[*] Diff for application: {app}")
    rc, output = run_argocd(["app", "diff", app], capture=True)
    if output.strip():
        print(output)
    else:
        print("[+] No diff — cluster matches Git state.")
    return rc


def cmd_rollback(app: str, revision: int) -> int:
    """Rollback application to a previous revision."""
    print(f"\n[*] Rolling back {app} to revision {revision}")
    rc, _ = run_argocd(["app", "rollback", app, str(revision)])
    if rc == 0:
        print(f"[+] Rollback to revision {revision} complete.")
    else:
        print(f"[ERR] Rollback failed.")
    return rc


def cmd_history(app: str) -> int:
    """Show deployment history for an application."""
    print(f"\n[*] History for application: {app}")
    rc, _ = run_argocd(["app", "history", app])
    return rc


def main():
    parser = argparse.ArgumentParser(description="ArgoCD application manager")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="List all applications")

    p_sync = sub.add_parser("sync", help="Sync application to Git state")
    p_sync.add_argument("--app",   required=True)
    p_sync.add_argument("--prune", action="store_true", help="Delete resources removed from Git")

    p_diff = sub.add_parser("diff", help="Show diff between Git and cluster")
    p_diff.add_argument("--app", required=True)

    p_rollback = sub.add_parser("rollback", help="Rollback to previous revision")
    p_rollback.add_argument("--app",      required=True)
    p_rollback.add_argument("--revision", required=True, type=int)

    p_history = sub.add_parser("history", help="Show deployment history")
    p_history.add_argument("--app", required=True)

    args = parser.parse_args()

    if args.command == "status":
        rc = cmd_status()
    elif args.command == "sync":
        rc = cmd_sync(args.app, args.prune)
    elif args.command == "diff":
        rc = cmd_diff(args.app)
    elif args.command == "rollback":
        rc = cmd_rollback(args.app, args.revision)
    elif args.command == "history":
        rc = cmd_history(args.app)
    else:
        rc = 1

    sys.exit(rc)


if __name__ == "__main__":
    main()
