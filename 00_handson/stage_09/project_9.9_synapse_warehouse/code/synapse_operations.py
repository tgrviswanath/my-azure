"""
synapse_operations.py — Azure Synapse Analytics SQL Pool operations.

Usage:
    pip install pyodbc
    export SYNAPSE_SERVER=synapse-handson-001.sql.azuresynapse.net
    export SYNAPSE_DB=sqldw
    export SYNAPSE_USER=sqladmin
    export SYNAPSE_PASS=YourPass123!
    python code/synapse_operations.py [setup|load|query|report]
"""

import os
import sys
import argparse
from decimal import Decimal

try:
    import pyodbc
except ImportError:
    print("[ERR] pip install pyodbc")
    sys.exit(1)


def get_connection():
    server   = os.environ.get("SYNAPSE_SERVER", "synapse-handson-001.sql.azuresynapse.net")
    database = os.environ.get("SYNAPSE_DB", "sqldw")
    username = os.environ.get("SYNAPSE_USER", "sqladmin")
    password = os.environ.get("SYNAPSE_PASS", "")

    conn_str = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={server},1433;"
        f"DATABASE={database};"
        f"UID={username};"
        f"PWD={password};"
        f"Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
    )
    return pyodbc.connect(conn_str)


def setup_tables(conn):
    """Create fact and dimension tables."""
    print("[*] Creating tables...")
    cursor = conn.cursor()

    cursor.execute("""
        IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'fact_orders')
        CREATE TABLE fact_orders (
            order_id    NVARCHAR(50)  NOT NULL,
            product     NVARCHAR(100) NOT NULL,
            customer_id NVARCHAR(50),
            amount      DECIMAL(10,2) NOT NULL,
            order_date  DATE          NOT NULL
        )
        WITH (
            DISTRIBUTION = HASH(order_id),
            CLUSTERED COLUMNSTORE INDEX
        )
    """)

    cursor.execute("""
        IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'dim_product')
        CREATE TABLE dim_product (
            product_name NVARCHAR(100),
            category     NVARCHAR(50),
            unit_price   DECIMAL(10,2)
        )
        WITH (DISTRIBUTION = REPLICATE)
    """)
    conn.commit()
    print("[+] Tables created.")


def load_sample_data(conn):
    """Insert sample data for demo."""
    print("[*] Loading sample data...")
    cursor = conn.cursor()
    rows = [
        ("ORD-001", "Widget A", "C001", 29.99, "2024-01-15"),
        ("ORD-002", "Widget B", "C002", 49.99, "2024-01-15"),
        ("ORD-003", "Widget C", "C001", 19.99, "2024-01-16"),
        ("ORD-004", "Widget A", "C003", 39.99, "2024-01-16"),
        ("ORD-005", "Widget B", "C002", 59.99, "2024-01-17"),
        ("ORD-006", "Widget C", "C004", 25.00, "2024-01-17"),
        ("ORD-007", "Widget A", "C001", 45.00, "2024-01-18"),
        ("ORD-008", "Widget B", "C003", 65.00, "2024-01-18"),
    ]
    cursor.executemany(
        "INSERT INTO fact_orders VALUES (?,?,?,?,?)", rows
    )
    conn.commit()
    print(f"[+] Loaded {len(rows)} rows.")


def run_queries(conn):
    """Run analytical queries."""
    cursor = conn.cursor()

    print("\n── Daily Revenue ──────────────────────────────────────────")
    cursor.execute("""
        SELECT order_date, SUM(amount) AS daily_revenue, COUNT(*) AS orders
        FROM fact_orders GROUP BY order_date ORDER BY order_date
    """)
    print(f"  {'Date':<12} {'Revenue':>12} {'Orders':>8}")
    print(f"  {'-'*12} {'-'*12} {'-'*8}")
    for row in cursor.fetchall():
        print(f"  {str(row[0]):<12} ${row[1]:>11.2f} {row[2]:>8}")

    print("\n── Top Products by Revenue ────────────────────────────────")
    cursor.execute("""
        SELECT product, SUM(amount) AS revenue, COUNT(*) AS orders
        FROM fact_orders GROUP BY product ORDER BY revenue DESC
    """)
    print(f"  {'Product':<15} {'Revenue':>12} {'Orders':>8}")
    print(f"  {'-'*15} {'-'*12} {'-'*8}")
    for row in cursor.fetchall():
        print(f"  {row[0]:<15} ${row[1]:>11.2f} {row[2]:>8}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", nargs="?", default="all",
                        choices=["setup", "load", "query", "all"])
    args = parser.parse_args()

    print(f"\n{'='*60}")
    print(f"  Synapse Analytics Operations")
    print(f"{'='*60}")

    try:
        conn = get_connection()
        print("[+] Connected to Synapse SQL Pool")

        if args.action in ("setup", "all"):
            setup_tables(conn)
        if args.action in ("load", "all"):
            load_sample_data(conn)
        if args.action in ("query", "all"):
            run_queries(conn)

        conn.close()
        print(f"\n[+] Done.\n")

    except pyodbc.Error as e:
        print(f"[ERR] Database error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
