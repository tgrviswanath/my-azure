"""
acr_manager.py — Manage Docker images in Azure Container Registry.

Usage:
    pip install azure-identity azure-mgmt-containerregistry
    # Docker must be running

    python code/acr_manager.py push  --registry acrhandson001 --repo myapp --tag v1.0
    python code/acr_manager.py list  --registry acrhandson001
    python code/acr_manager.py clean --registry acrhandson001 --repo myapp --keep 5
    python code/acr_manager.py build --registry acrhandson001 --repo myapp --tag v1.0 --context .
"""

import argparse
import subprocess
import sys
import json
from datetime import datetime

from azure.identity import DefaultAzureCredential, AzureCliCredential
from azure.mgmt.containerregistry import ContainerRegistryManagementClient
from azure.mgmt.resource import SubscriptionClient


# ── ANSI colors ───────────────────────────────────────────────────────────────
class C:
    RESET  = "\033[0m"
    GREEN  = "\033[92m"
    YELLOW = "\033[93m"
    RED    = "\033[91m"
    CYAN   = "\033[96m"
    BOLD   = "\033[1m"

def info(msg):  print(f"{C.CYAN}[INFO]{C.RESET}  {msg}")
def ok(msg):    print(f"{C.GREEN}[OK]{C.RESET}    {msg}")
def warn(msg):  print(f"{C.YELLOW}[WARN]{C.RESET}  {msg}")
def err(msg):   print(f"{C.RED}[ERR]{C.RESET}   {msg}", file=sys.stderr)


def get_subscription_id() -> str:
    credential = DefaultAzureCredential()
    return list(SubscriptionClient(credential).subscriptions.list())[0].subscription_id


def run(cmd: list[str]) -> int:
    """Run a shell command, stream output, return exit code."""
    info(f"$ {' '.join(cmd)}")
    return subprocess.run(cmd).returncode


def acr_login(registry: str) -> int:
    """Authenticate Docker to ACR using Azure CLI token."""
    info(f"Logging in to ACR: {registry}.azurecr.io")
    rc = run(["az", "acr", "login", "--name", registry])
    if rc == 0:
        ok("Docker logged in to ACR.")
    else:
        err("ACR login failed. Run: az login")
    return rc


# ── push ──────────────────────────────────────────────────────────────────────

def cmd_push(registry: str, repo: str, tag: str, dockerfile_dir: str) -> int:
    """Build image locally and push to ACR."""
    full_tag = f"{registry}.azurecr.io/{repo}:{tag}"
    info(f"Building and pushing: {full_tag}")

    rc = acr_login(registry)
    if rc != 0:
        return rc

    rc = run(["docker", "build", "-t", full_tag, dockerfile_dir])
    if rc != 0:
        err("Docker build failed.")
        return rc

    rc = run(["docker", "push", full_tag])
    if rc != 0:
        err("Docker push failed.")
        return rc

    ok(f"Image pushed: {full_tag}")
    return 0


# ── build (ACR Tasks — no local Docker needed) ────────────────────────────────

def cmd_build(registry: str, repo: str, tag: str, context: str) -> int:
    """Build image in ACR cloud (no local Docker required)."""
    full_tag = f"{repo}:{tag}"
    info(f"Building in ACR cloud: {registry}.azurecr.io/{full_tag}")
    rc = run([
        "az", "acr", "build",
        "--registry", registry,
        "--image", full_tag,
        context
    ])
    if rc == 0:
        ok(f"ACR build complete: {registry}.azurecr.io/{full_tag}")
    else:
        err("ACR build failed.")
    return rc


# ── list ──────────────────────────────────────────────────────────────────────

def cmd_list(registry: str, repo: str | None) -> int:
    """List repositories or tags in ACR."""
    if repo:
        info(f"Listing tags for {registry}.azurecr.io/{repo}")
        result = subprocess.run(
            ["az", "acr", "repository", "show-tags",
             "--name", registry, "--repository", repo,
             "--orderby", "time_desc", "--output", "json"],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            err(result.stderr)
            return result.returncode
        tags = json.loads(result.stdout)
        print(f"\n  Tags in {registry}.azurecr.io/{repo}:")
        for t in tags:
            print(f"    - {t}")
        print(f"\n  Total: {len(tags)} tag(s)")
    else:
        info(f"Listing repositories in {registry}.azurecr.io")
        result = subprocess.run(
            ["az", "acr", "repository", "list",
             "--name", registry, "--output", "json"],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            err(result.stderr)
            return result.returncode
        repos = json.loads(result.stdout)
        print(f"\n  Repositories in {registry}.azurecr.io:")
        for r in repos:
            print(f"    - {r}")
        print(f"\n  Total: {len(repos)} repository(ies)")
    return 0


# ── clean ─────────────────────────────────────────────────────────────────────

def cmd_clean(registry: str, repo: str, keep: int) -> int:
    """Delete old tags, keeping the N most recent."""
    info(f"Cleaning {registry}.azurecr.io/{repo} — keeping {keep} most recent tags")

    result = subprocess.run(
        ["az", "acr", "repository", "show-tags",
         "--name", registry, "--repository", repo,
         "--orderby", "time_desc", "--output", "json"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        err(result.stderr)
        return result.returncode

    tags = json.loads(result.stdout)
    if len(tags) <= keep:
        ok(f"Only {len(tags)} tag(s) — nothing to delete (keep={keep}).")
        return 0

    to_delete = tags[keep:]
    warn(f"Deleting {len(to_delete)} old tag(s)...")

    for tag in to_delete:
        rc = run([
            "az", "acr", "repository", "delete",
            "--name", registry,
            "--image", f"{repo}:{tag}",
            "--yes"
        ])
        if rc == 0:
            ok(f"Deleted: {repo}:{tag}")
        else:
            warn(f"Failed to delete: {repo}:{tag}")

    ok(f"Cleanup complete. {keep} tag(s) retained.")
    return 0


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Manage Docker images in Azure Container Registry.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  python code/acr_manager.py push  --registry acrhandson001 --repo myapp --tag v1.0
  python code/acr_manager.py build --registry acrhandson001 --repo myapp --tag v1.0 --context .
  python code/acr_manager.py list  --registry acrhandson001
  python code/acr_manager.py list  --registry acrhandson001 --repo myapp
  python code/acr_manager.py clean --registry acrhandson001 --repo myapp --keep 5"""
    )
    parser.add_argument("--registry", required=True, help="ACR registry name (without .azurecr.io)")

    sub = parser.add_subparsers(dest="command", required=True)

    p_push = sub.add_parser("push", help="Build locally and push to ACR")
    p_push.add_argument("--repo",       required=True)
    p_push.add_argument("--tag",        required=True)
    p_push.add_argument("--dockerfile", default=".", help="Dockerfile directory (default: .)")

    p_build = sub.add_parser("build", help="Build in ACR cloud (no local Docker)")
    p_build.add_argument("--repo",    required=True)
    p_build.add_argument("--tag",     required=True)
    p_build.add_argument("--context", default=".", help="Build context directory (default: .)")

    p_list = sub.add_parser("list", help="List repositories or tags")
    p_list.add_argument("--repo", default=None, help="Repository name (omit to list all repos)")

    p_clean = sub.add_parser("clean", help="Delete old tags, keep N most recent")
    p_clean.add_argument("--repo", required=True)
    p_clean.add_argument("--keep", required=True, type=int)

    args = parser.parse_args()

    if args.command == "push":
        rc = cmd_push(args.registry, args.repo, args.tag, args.dockerfile)
    elif args.command == "build":
        rc = cmd_build(args.registry, args.repo, args.tag, args.context)
    elif args.command == "list":
        rc = cmd_list(args.registry, args.repo)
    elif args.command == "clean":
        rc = cmd_clean(args.registry, args.repo, args.keep)
    else:
        rc = 1

    sys.exit(rc)


if __name__ == "__main__":
    main()
