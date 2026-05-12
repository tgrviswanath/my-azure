"""
schema_evolution_demo.py — Delta Lake schema evolution on Azure Databricks.

Run this in a Databricks notebook or as a Databricks job.
Requires: Delta Lake (included in Databricks Runtime 7.0+)

Demonstrates:
    1. Create Delta table v1
    2. Evolve schema (add column) with mergeSchema
    3. Partition pruning
    4. OPTIMIZE + ZORDER
    5. Time travel (VERSION AS OF)
"""

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, year, month, dayofmonth, lit
from delta.tables import DeltaTable

spark = SparkSession.builder \
    .appName("SchemaEvolutionDemo") \
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension") \
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog") \
    .getOrCreate()

DELTA_PATH = "/mnt/datalake/orders_delta"


def create_v1_table():
    """Create Delta table with v1 schema."""
    print("\n── Step 1: Create Delta table v1 ──────────────────────────")
    data = [
        ("ORD-001", "Widget A", 29.99, "2024-01-15"),
        ("ORD-002", "Widget B", 49.99, "2024-01-15"),
        ("ORD-003", "Widget C", 19.99, "2024-01-16"),
        ("ORD-004", "Widget A", 39.99, "2024-01-16"),
        ("ORD-005", "Widget B", 59.99, "2024-01-17"),
    ]
    df = spark.createDataFrame(data, ["order_id", "product", "amount", "order_date"])
    df.write.format("delta") \
        .partitionBy("product") \
        .mode("overwrite") \
        .save(DELTA_PATH)
    print(f"[+] Delta table v1 created at {DELTA_PATH}")
    print(f"    Schema: {df.schema.simpleString()}")
    print(f"    Rows: {df.count()}")


def evolve_schema():
    """Add customer_tier column — backward compatible."""
    print("\n── Step 2: Evolve schema (add customer_tier) ───────────────")
    data_v2 = [
        ("ORD-006", "Widget A", 45.00, "2024-01-18", "gold"),
        ("ORD-007", "Widget B", 65.00, "2024-01-18", "silver"),
        ("ORD-008", "Widget C", 25.00, "2024-01-19", "bronze"),
    ]
    df_v2 = spark.createDataFrame(
        data_v2,
        ["order_id", "product", "amount", "order_date", "customer_tier"]
    )
    # mergeSchema=True allows adding new columns
    df_v2.write.format("delta") \
        .option("mergeSchema", "true") \
        .mode("append") \
        .save(DELTA_PATH)
    print("[+] Schema evolved — customer_tier column added")

    # Read back and show
    df = spark.read.format("delta").load(DELTA_PATH)
    print(f"    New schema: {df.schema.simpleString()}")
    df.show(10)
    print("    Note: v1 rows have null for customer_tier (backward compatible)")


def demonstrate_partition_pruning():
    """Show partition pruning — only reads Widget A partition."""
    print("\n── Step 3: Partition pruning ────────────────────────────────")
    df = spark.read.format("delta").load(DELTA_PATH)

    # Filter on partition column — Spark skips other partitions
    df_widget_a = df.filter("product = 'Widget A'")
    print("[+] Query: product = 'Widget A'")
    print("    Physical plan (shows PartitionFilters):")
    df_widget_a.explain()
    df_widget_a.show()


def optimize_and_zorder():
    """Compact small files and co-locate data with ZORDER."""
    print("\n── Step 4: OPTIMIZE + ZORDER ────────────────────────────────")
    spark.sql(f"""
        OPTIMIZE delta.`{DELTA_PATH}`
        ZORDER BY (order_id)
    """)
    print("[+] OPTIMIZE + ZORDER completed")
    print("    Small files compacted, data co-located by order_id")

    # Show table history
    history = spark.sql(f"DESCRIBE HISTORY delta.`{DELTA_PATH}`")
    history.select("version", "timestamp", "operation").show(5)


def time_travel():
    """Read previous versions of the Delta table."""
    print("\n── Step 5: Time travel ──────────────────────────────────────")

    # Read version 0 (before schema evolution)
    df_v0 = spark.read.format("delta") \
        .option("versionAsOf", 0) \
        .load(DELTA_PATH)
    print("[+] Version 0 (original schema):")
    print(f"    Schema: {df_v0.schema.simpleString()}")
    df_v0.show()

    # Read version 1 (after schema evolution)
    df_v1 = spark.read.format("delta") \
        .option("versionAsOf", 1) \
        .load(DELTA_PATH)
    print("[+] Version 1 (evolved schema):")
    print(f"    Schema: {df_v1.schema.simpleString()}")
    df_v1.show()


def main():
    print("=" * 60)
    print("  Delta Lake Schema Evolution Demo")
    print("=" * 60)

    create_v1_table()
    evolve_schema()
    demonstrate_partition_pruning()
    optimize_and_zorder()
    time_travel()

    print("\n[+] Demo complete.")


if __name__ == "__main__":
    main()
