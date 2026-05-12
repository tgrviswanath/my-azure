"""
load_test.py — Compare latency between Application Gateway (L7) and Azure Load Balancer (L4).

Usage:
    python load_test.py --appgw-url http://<appgw-ip> --lb-url http://<lb-ip>
    python load_test.py --appgw-url http://20.1.2.3 --lb-url http://20.4.5.6 --requests 500

Requirements:
    pip install requests
"""

import argparse
import statistics
import time
import concurrent.futures
from dataclasses import dataclass, field
from typing import Optional
import urllib.request
import urllib.error


@dataclass
class RequestResult:
    url: str
    status_code: int
    latency_ms: float
    error: Optional[str] = None


@dataclass
class BenchmarkResult:
    name: str
    url: str
    total_requests: int
    successful: int = 0
    failed: int = 0
    latencies: list[float] = field(default_factory=list)

    @property
    def success_rate(self) -> float:
        return (self.successful / self.total_requests * 100) if self.total_requests > 0 else 0

    @property
    def p50(self) -> float:
        return statistics.median(self.latencies) if self.latencies else 0

    @property
    def p95(self) -> float:
        if not self.latencies:
            return 0
        sorted_l = sorted(self.latencies)
        idx = int(len(sorted_l) * 0.95)
        return sorted_l[min(idx, len(sorted_l) - 1)]

    @property
    def p99(self) -> float:
        if not self.latencies:
            return 0
        sorted_l = sorted(self.latencies)
        idx = int(len(sorted_l) * 0.99)
        return sorted_l[min(idx, len(sorted_l) - 1)]

    @property
    def mean(self) -> float:
        return statistics.mean(self.latencies) if self.latencies else 0

    @property
    def stdev(self) -> float:
        return statistics.stdev(self.latencies) if len(self.latencies) > 1 else 0

    @property
    def min_latency(self) -> float:
        return min(self.latencies) if self.latencies else 0

    @property
    def max_latency(self) -> float:
        return max(self.latencies) if self.latencies else 0


# ─────────────────────────────────────────────
# HTTP request with timing
# ─────────────────────────────────────────────

def make_request(url: str, timeout: int = 10) -> RequestResult:
    """Make a single HTTP GET request and measure latency."""
    start = time.perf_counter()
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "AzureLBComparison/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as response:
            _ = response.read()
            elapsed_ms = (time.perf_counter() - start) * 1000
            return RequestResult(url=url, status_code=response.status, latency_ms=elapsed_ms)
    except urllib.error.HTTPError as e:
        elapsed_ms = (time.perf_counter() - start) * 1000
        return RequestResult(url=url, status_code=e.code, latency_ms=elapsed_ms)
    except Exception as e:
        elapsed_ms = (time.perf_counter() - start) * 1000
        return RequestResult(url=url, status_code=0, latency_ms=elapsed_ms, error=str(e))


# ─────────────────────────────────────────────
# Benchmark runner
# ─────────────────────────────────────────────

def run_benchmark(
    name: str,
    url: str,
    num_requests: int,
    concurrency: int,
    warmup: int = 10,
) -> BenchmarkResult:
    result = BenchmarkResult(name=name, url=url, total_requests=num_requests)

    print(f"\n  Running {name}...")
    print(f"  URL: {url}")
    print(f"  Requests: {num_requests} (concurrency: {concurrency}, warmup: {warmup})")

    # Warmup
    print(f"  Warming up ({warmup} requests)...", end="", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(make_request, url) for _ in range(warmup)]
        concurrent.futures.wait(futures)
    print(" done")

    # Actual benchmark
    print(f"  Benchmarking...", end="", flush=True)
    completed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(make_request, url) for _ in range(num_requests)]
        for future in concurrent.futures.as_completed(futures):
            r = future.result()
            if r.error is None and r.status_code in (200, 201, 204):
                result.successful += 1
                result.latencies.append(r.latency_ms)
            else:
                result.failed += 1
            completed += 1
            if completed % 50 == 0:
                print(".", end="", flush=True)
    print(f" done ({result.successful}/{num_requests} successful)")

    return result


# ─────────────────────────────────────────────
# Output
# ─────────────────────────────────────────────

def print_results(appgw: BenchmarkResult, lb: BenchmarkResult) -> None:
    print("\n")
    print("╔══════════════════════════════════════════════════════════════════╗")
    print("║              Load Balancer Comparison Results                    ║")
    print("╚══════════════════════════════════════════════════════════════════╝")

    header = f"  {'Metric':<25} {'App Gateway (L7)':>20} {'Load Balancer (L4)':>20}"
    print(f"\n{header}")
    print(f"  {'─' * 65}")

    def row(label: str, appgw_val: str, lb_val: str, highlight: bool = False) -> None:
        winner = ""
        try:
            av = float(appgw_val.replace(" ms", "").replace("%", ""))
            lv = float(lb_val.replace(" ms", "").replace("%", ""))
            if "ms" in appgw_val:
                winner = " ◄" if av < lv else ("" if av == lv else "")
                lb_winner = " ◄" if lv < av else ""
            else:
                winner = " ◄" if av > lv else ""
                lb_winner = " ◄" if lv > av else ""
        except ValueError:
            winner = ""
            lb_winner = ""

        print(f"  {label:<25} {appgw_val + winner:>20} {lb_val + lb_winner:>20}")

    row("Requests sent",     str(appgw.total_requests),          str(lb.total_requests))
    row("Successful",        str(appgw.successful),               str(lb.successful))
    row("Failed",            str(appgw.failed),                   str(lb.failed))
    row("Success rate",      f"{appgw.success_rate:.1f}%",        f"{lb.success_rate:.1f}%")
    print(f"  {'─' * 65}")
    row("Min latency",       f"{appgw.min_latency:.1f} ms",       f"{lb.min_latency:.1f} ms")
    row("Mean latency",      f"{appgw.mean:.1f} ms",              f"{lb.mean:.1f} ms")
    row("P50 latency",       f"{appgw.p50:.1f} ms",               f"{lb.p50:.1f} ms")
    row("P95 latency",       f"{appgw.p95:.1f} ms",               f"{lb.p95:.1f} ms")
    row("P99 latency",       f"{appgw.p99:.1f} ms",               f"{lb.p99:.1f} ms")
    row("Max latency",       f"{appgw.max_latency:.1f} ms",       f"{lb.max_latency:.1f} ms")
    row("Std deviation",     f"{appgw.stdev:.1f} ms",             f"{lb.stdev:.1f} ms")

    print(f"\n  {'─' * 65}")

    # Verdict
    if appgw.p95 > 0 and lb.p95 > 0:
        overhead_pct = ((appgw.p95 - lb.p95) / lb.p95) * 100
        print(f"\n  App Gateway P95 overhead vs Load Balancer: +{overhead_pct:.1f}%")

    print("\n  Recommendation:")
    print("  • Use Application Gateway for web apps needing path routing, SSL, WAF")
    print("  • Use Load Balancer for TCP/UDP workloads needing lowest latency")
    print(f"\n{'═' * 68}\n")


# ─────────────────────────────────────────────
# Path routing test
# ─────────────────────────────────────────────

def test_path_routing(appgw_url: str) -> None:
    print("\n─────────────────────────────────────────────────")
    print("  Path-Based Routing Test (App Gateway only)")
    print("─────────────────────────────────────────────────")

    paths = ["/", "/api/users", "/api/products", "/static/logo.png", "/health"]
    for path in paths:
        url = appgw_url.rstrip("/") + path
        r = make_request(url)
        status_color = "\033[92m" if r.status_code in (200, 404) else "\033[91m"
        print(f"  {path:<25} → {status_color}HTTP {r.status_code}\033[0m  ({r.latency_ms:.1f} ms)")


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Azure Load Balancer comparison tool")
    parser.add_argument("--appgw-url", required=True, help="Application Gateway URL")
    parser.add_argument("--lb-url", required=True, help="Load Balancer URL")
    parser.add_argument("--requests", type=int, default=200, help="Number of requests per endpoint")
    parser.add_argument("--concurrency", type=int, default=10, help="Concurrent workers")
    parser.add_argument("--warmup", type=int, default=10, help="Warmup requests")
    parser.add_argument("--skip-path-test", action="store_true", help="Skip path routing test")
    args = parser.parse_args()

    print("\n╔══════════════════════════════════════════════════════════════════╗")
    print("║         Azure Load Balancer Comparison Tool                      ║")
    print("╚══════════════════════════════════════════════════════════════════╝")

    appgw_result = run_benchmark(
        "Application Gateway (L7)",
        args.appgw_url,
        args.requests,
        args.concurrency,
        args.warmup,
    )

    lb_result = run_benchmark(
        "Azure Load Balancer (L4)",
        args.lb_url,
        args.requests,
        args.concurrency,
        args.warmup,
    )

    print_results(appgw_result, lb_result)

    if not args.skip_path_test:
        test_path_routing(args.appgw_url)


if __name__ == "__main__":
    main()
