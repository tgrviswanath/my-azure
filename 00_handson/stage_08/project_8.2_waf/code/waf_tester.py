"""
waf_tester.py — Test WAF rules by sending malicious and legitimate requests.

Usage:
    pip install requests
    python code/waf_tester.py --url https://your-app-gateway-ip
"""

import argparse
import sys
import time
try:
    import requests
    requests.packages.urllib3.disable_warnings()
except ImportError:
    print("[ERR] pip install requests")
    sys.exit(1)

TESTS = [
    ("Legitimate GET /",           "/",                                          {},                                          200),
    ("Legitimate GET /health",     "/health",                                    {},                                          200),
    ("SQL Injection (query param)","/?id=1' OR '1'='1",                          {},                                          403),
    ("SQL Injection (body)",       "/api/login",                                 {"username": "admin' --", "password": "x"},  403),
    ("XSS (query param)",          "/?q=<script>alert(1)</script>",              {},                                          403),
    ("XSS (header)",               "/",                                          {},                                          403),  # via User-Agent
    ("Path traversal",             "/../../../etc/passwd",                       {},                                          403),
    ("Bad bot user-agent",         "/",                                          {},                                          403),  # via User-Agent
]

BAD_BOT_UA = "sqlmap/1.0-dev-nongit-20230101"
XSS_UA     = "<script>alert(1)</script>"


def run_test(base_url: str, name: str, path: str, body: dict, expected: int, ua: str = None) -> tuple[bool, int]:
    url = base_url.rstrip("/") + path
    headers = {"User-Agent": ua} if ua else {}
    try:
        if body:
            resp = requests.post(url, json=body, headers=headers, timeout=10, verify=False, allow_redirects=False)
        else:
            resp = requests.get(url, headers=headers, timeout=10, verify=False, allow_redirects=False)
        return resp.status_code == expected, resp.status_code
    except requests.exceptions.ConnectionError:
        return expected == 403, 0  # Connection refused = blocked
    except Exception as e:
        return False, -1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True, help="Base URL of the application")
    args = parser.parse_args()

    print(f"\n{'='*65}")
    print(f"  WAF Rule Tester")
    print(f"{'='*65}")
    print(f"  Target: {args.url}\n")

    results = []

    # Standard tests
    for name, path, body, expected in TESTS[:2]:
        passed, got = run_test(args.url, name, path, body, expected)
        results.append((name, expected, got, passed))
        time.sleep(0.2)

    # SQL injection
    passed, got = run_test(args.url, "SQL Injection", "/?id=1' OR '1'='1", {}, 403)
    results.append(("SQL Injection (query param)", 403, got, passed))

    # XSS
    passed, got = run_test(args.url, "XSS", "/?q=<script>alert(1)</script>", {}, 403)
    results.append(("XSS (query param)", 403, got, passed))

    # Bad bot user-agent
    passed, got = run_test(args.url, "Bad Bot UA", "/", {}, 403, ua=BAD_BOT_UA)
    results.append(("Bad bot user-agent", 403, got, passed))

    # Path traversal
    passed, got = run_test(args.url, "Path traversal", "/../../../etc/passwd", {}, 403)
    results.append(("Path traversal", 403, got, passed))

    # Print results
    print(f"  {'Test':<35} {'Expected':>8} {'Got':>6} {'Result'}")
    print(f"  {'-'*35} {'-'*8} {'-'*6} {'-'*6}")
    passed_count = 0
    for name, expected, got, passed in results:
        icon = "✅ PASS" if passed else "❌ FAIL"
        print(f"  {name:<35} {expected:>8} {got:>6} {icon}")
        if passed:
            passed_count += 1

    print(f"\n  Result: {passed_count}/{len(results)} tests passed")
    print(f"{'='*65}\n")
    sys.exit(0 if passed_count == len(results) else 1)


if __name__ == "__main__":
    main()
