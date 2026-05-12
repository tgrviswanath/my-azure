"""
db_operations.py — Connect to Azure SQL Database and perform CRUD operations.

Prerequisites:
    pip install pyodbc

    # Install ODBC Driver 18 for SQL Server:
    # macOS: brew install msodbcsql18
    # Ubuntu: https://learn.microsoft.com/en-us/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server
    # Windows: https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server

Run:
    python code/db_operations.py
"""

import os
import pyodbc
from datetime import datetime


# Connection configuration — set via environment variables or update directly
SERVER   = os.environ.get("SQL_SERVER",   "sql-lab-server.database.windows.net")
DATABASE = os.environ.get("SQL_DATABASE", "labdb")
USERNAME = os.environ.get("SQL_USERNAME", "sqladmin")
PASSWORD = os.environ.get("SQL_PASSWORD", "YourPass123!")

CONN_STR = (
    f"DRIVER={{ODBC Driver 18 for SQL Server}};"
    f"SERVER={SERVER},1433;"
    f"DATABASE={DATABASE};"
    f"UID={USERNAME};"
    f"PWD={PASSWORD};"
    f"Encrypt=yes;"
    f"TrustServerCertificate=no;"
    f"Connection Timeout=30;"
)


def get_connection() -> pyodbc.Connection:
    """Create and return a database connection."""
    return pyodbc.connect(CONN_STR)


def create_tables(conn: pyodbc.Connection) -> None:
    """Create the orders table if it doesn't exist."""
    print("\n[*] Creating tables...")
    cursor = conn.cursor()

    cursor.execute("""
        IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='orders' AND xtype='U')
        CREATE TABLE orders (
            id           INT IDENTITY(1,1) PRIMARY KEY,
            customer_name NVARCHAR(100) NOT NULL,
            product      NVARCHAR(100) NOT NULL,
            amount       DECIMAL(10,2) NOT NULL,
            status       NVARCHAR(20)  DEFAULT 'pending',
            created_at   DATETIME2     DEFAULT GETDATE()
        )
    """)
    conn.commit()
    print("[+] Table 'orders' ready.")


def insert_sample_data(conn: pyodbc.Connection) -> None:
    """Insert 5 sample orders."""
    print("\n[*] Inserting sample data...")
    cursor = conn.cursor()

    orders = [
        ("Alice Johnson",  "Azure VM B2s",          30.37, "completed"),
        ("Bob Smith",      "Azure Storage 100GB",    2.30,  "completed"),
        ("Carol White",    "Azure SQL Basic",         4.99,  "pending"),
        ("David Brown",    "Azure CDN 50GB",          4.35,  "completed"),
        ("Eve Davis",      "Azure Functions 1M calls", 0.20, "pending"),
    ]

    # Use parameterized query — never format SQL with user input
    cursor.executemany(
        "INSERT INTO orders (customer_name, product, amount, status) VALUES (?, ?, ?, ?)",
        orders
    )
    conn.commit()
    print(f"[+] Inserted {len(orders)} orders.")


def query_all_orders(conn: pyodbc.Connection) -> None:
    """Query and display all orders."""
    print("\n[*] All Orders:")
    print("-" * 75)
    cursor = conn.cursor()

    cursor.execute("SELECT id, customer_name, product, amount, status, created_at FROM orders ORDER BY id")
    rows = cursor.fetchall()

    print(f"  {'ID':<4} {'Customer':<18} {'Product':<28} {'Amount':>8} {'Status':<12}")
    print(f"  {'-'*4} {'-'*18} {'-'*28} {'-'*8} {'-'*12}")

    for row in rows:
        print(f"  {row.id:<4} {row.customer_name:<18} {row.product:<28} ${row.amount:>7.2f} {row.status:<12}")

    print(f"\n  Total rows: {len(rows)}")


def query_summary(conn: pyodbc.Connection) -> None:
    """Query order summary grouped by status."""
    print("\n[*] Order Summary by Status:")
    print("-" * 45)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            status,
            COUNT(*) AS order_count,
            SUM(amount) AS total_amount,
            AVG(amount) AS avg_amount
        FROM orders
        GROUP BY status
        ORDER BY total_amount DESC
    """)
    rows = cursor.fetchall()

    print(f"  {'Status':<12} {'Count':>6} {'Total':>10} {'Average':>10}")
    print(f"  {'-'*12} {'-'*6} {'-'*10} {'-'*10}")

    for row in rows:
        print(f"  {row.status:<12} {row.order_count:>6} ${row.total_amount:>9.2f} ${row.avg_amount:>9.2f}")


def update_order_status(conn: pyodbc.Connection, order_id: int, new_status: str) -> None:
    """Update the status of a specific order."""
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE orders SET status = ? WHERE id = ?",
        (new_status, order_id)
    )
    conn.commit()
    print(f"\n[+] Updated order {order_id} status to '{new_status}'")


def get_server_info(conn: pyodbc.Connection) -> None:
    """Display SQL Server version and current database."""
    cursor = conn.cursor()
    cursor.execute("SELECT @@VERSION AS version, DB_NAME() AS db_name, GETDATE() AS server_time")
    row = cursor.fetchone()
    version_short = row.version.split('\n')[0] if row.version else "Unknown"
    print(f"\n[*] Server Info:")
    print(f"    Version:  {version_short}")
    print(f"    Database: {row.db_name}")
    print(f"    Time:     {row.server_time}")


def main():
    print("=" * 75)
    print("  Azure SQL Database Operations Demo")
    print("=" * 75)
    print(f"[*] Connecting to: {SERVER}/{DATABASE}")

    try:
        conn = get_connection()
        print("[+] Connected successfully!")

        get_server_info(conn)
        create_tables(conn)
        insert_sample_data(conn)
        query_all_orders(conn)
        query_summary(conn)

        # Update one order
        update_order_status(conn, 3, "completed")
        query_summary(conn)

        conn.close()
        print("\n[+] All operations completed successfully.")

    except pyodbc.Error as e:
        print(f"\n[!] Database error: {e}")
        print("[!] Check: server name, firewall rules, credentials")
        print(f"[!] Server: {SERVER}")
    except Exception as e:
        print(f"\n[!] Error: {e}")


if __name__ == "__main__":
    main()
