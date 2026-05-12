"""
health_check.py — Check health of all containers in the multi-container stack.

Usage:
    pip install requests
    docker compose up -d
    python code/health_check.py
"""

import sys
import time
try:
    import requests
except ImportError:
    print("[ERR] pip install requests")
    sys.exit(1)

SERVICES = [
    ("Backend API",  "http://localhost:3000/health"),
    ("Frontend",     "http://localhost:80"),
]

PASS = "\033[92m[PASS]\033[0m"
FAIL = "\033[91m[FAIL]\033[0m"


def check_service(name: str, url: str, timeout: int = 5) -> bool:
    try:
        resp = requests.get(url, timeout=timeout)
        ok = resp.status_code < 400
        icon = PASS if ok else FAIL
        print(f"  {icon} {name:<20} {url:<40} HTTP {resp.status_code}")
        return ok
    except requests.exceptions.ConnectionError:
        print(f"  {FAIL} {name:<20} {url:<40} CONNECTION REFUSED")
        return False
    except Exception as e:
        print(f"  {FAIL} {name:<20} {url:<40} {e}")
        return False


def main():
    print(f"\n{'='*70}")
    print(f"  Multi-container Stack Health Check")
    print(f"{'='*70}\n")

    results = [check_service(name, url) for name, url in SERVICES]

    print(f"\n{'='*70}")
    passed = sum(results)
    total = len(results)
    if all(results):
        print(f"  \033[92m[OK]\033[0m All {total}/{total} services healthy.")
    else:
        print(f"  \033[91m[FAIL]\033[0m {passed}/{total} services healthy.")
        print(f"  Run: docker compose logs to debug")
    print(f"{'='*70}\n")

    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
