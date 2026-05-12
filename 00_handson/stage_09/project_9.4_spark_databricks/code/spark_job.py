# spark_job.py — PySpark ETL Job for Azure Databricks
#
# Reads CSV from ADLS Gen2, cleans and transforms data,
# aggregates daily revenue by product, writes Delta table
# with year/month partitioning, demonstrates MERGE upsert
# and Delta time travel.
#
# Run this as a Databricks notebook or job.
# Requires: Databricks Runtime 13.3+ (includes Delta Lake)

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType, StructField,
    StringType, DecimalType, IntegerType, DateType
)
from delta.tables import DeltaTable
import datetime

# ── Configuration ─────────────────────────────────────────────────────────────

# In Databricks, use dbutils.widgets or job parameters
try:
    STORAGE_NAME = dbutils.widgets.get("storage_name")
except Exception:
    STORAGE_NAME = "your-storage-account-name"

RAW_PATH   = f"/mnt/raw/orders/2024/01/"
DELTA_PATH = f"/mnt/delta/orders_delta/"

# ── Spark Session ─────────────────────────────────────────────────────────────

# In Databricks, SparkSession is pre-created as 'spark'
# For local testing:
try:
    spark  # noqa: F821 — already exists in Databricks
except NameError:
    spark = (
        SparkSession.builder
        .appName("orders-etl")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
        .getOrCreate()
    )

spark.conf.set("spark.sql.shuffle.partitions", "8")  # Reduce for small datasets

print("=" * 60)
print("  Spark Orders ETL Job")
print(f"  Spark version: {spark.version}")
print(f"  Storage: {STORAGE_NAME}")
print("=" * 60)


# ── Step 1: Define Schema ─────────────────────────────────────────────────────

print("\n[1/7] Defining schema...")

orders_schema = StructType([
    StructField("order_id",    StringType(),  nullable=False),
    StructField("customer_id", StringType(),  nullable=True),
    StructField("product",     StringType(),  nullable=True),
    StructField("amount",      StringType(),  nullable=True),  # Read as string, cast later
    StructField("quantity",    StringType(),  nullable=True),
    StructField("order_date",  StringType(),  nullable=True),
    StructField("status",      StringType(),  nullable=True),
    StructField("region",      StringType(),  nullable=True),
])


# ── Step 2: Read CSV ──────────────────────────────────────────────────────────

print(f"\n[2/7] Reading CSV from {RAW_PATH}...")

df_raw = (
    spark.read
    .option("header", "true")
    .option("inferSchema", "false")
    .schema(orders_schema)
    .csv(RAW_PATH)
)

raw_count = df_raw.count()
print(f"  Raw rows: {raw_count:,}")
print(f"  Columns: {df_raw.columns}")

df_raw.show(5, truncate=False)


# ── Step 3: Clean Nulls ───────────────────────────────────────────────────────

print("\n[3/7] Cleaning data...")

# Count nulls before cleaning
null_counts = {
    col: df_raw.filter(F.col(col).isNull()).count()
    for col in ["order_id", "customer_id", "amount", "order_date"]
}
print(f"  Null counts before cleaning: {null_counts}")

df_clean = (
    df_raw
    # Drop rows with null primary keys
    .dropna(subset=["order_id", "customer_id"])
    # Fill optional nulls with defaults
    .fillna({
        "status": "unknown",
        "region": "unknown",
        "quantity": "1",
    })
    # Remove rows with invalid amounts
    .filter(F.col("amount").isNotNull())
    .filter(F.col("amount").cast("double") > 0)
    # Remove rows with invalid dates
    .filter(F.col("order_date").isNotNull())
    .filter(F.col("order_date").rlike(r"^\d{4}-\d{2}-\d{2}$"))
)

clean_count = df_clean.count()
dropped = raw_count - clean_count
print(f"  Clean rows: {clean_count:,} (dropped {dropped} invalid rows)")


# ── Step 4: Cast Types + Feature Engineering ──────────────────────────────────

print("\n[4/7] Casting types and engineering features...")

df_typed = (
    df_clean
    .withColumn("amount",       F.col("amount").cast(DecimalType(10, 2)))
    .withColumn("quantity",     F.col("quantity").cast(IntegerType()))
    .withColumn("order_date",   F.to_date(F.col("order_date"), "yyyy-MM-dd"))
    .withColumn("total_amount", F.round(F.col("amount") * F.col("quantity"), 2))
    .withColumn("year",         F.year(F.col("order_date")))
    .withColumn("month",        F.month(F.col("order_date")))
    .withColumn("day_of_week",  F.dayofweek(F.col("order_date")))
    .withColumn("is_weekend",   F.when(F.col("day_of_week").isin(1, 7), True).otherwise(False))
    .withColumn("ingested_at",  F.current_timestamp())
)

print("  Schema after type casting:")
df_typed.printSchema()
df_typed.show(5, truncate=False)


# ── Step 5: Aggregate Daily Revenue by Product ────────────────────────────────

print("\n[5/7] Aggregating daily revenue by product...")

df_daily_revenue = (
    df_typed
    .filter(F.col("status") == "completed")
    .groupBy("order_date", "product", "year", "month")
    .agg(
        F.sum("total_amount").alias("daily_revenue"),
        F.count("*").alias("order_count"),
        F.avg("amount").alias("avg_order_value"),
        F.sum("quantity").alias("total_units_sold"),
        F.countDistinct("customer_id").alias("unique_customers"),
    )
    .orderBy("order_date", "product")
)

print("  Daily revenue by product:")
df_daily_revenue.show(20, truncate=False)

total_revenue = df_daily_revenue.agg(F.sum("daily_revenue")).collect()[0][0]
print(f"  Total revenue (completed orders): ${total_revenue:,.2f}")


# ── Step 6: Write Delta Table with Partitioning ───────────────────────────────

print(f"\n[6/7] Writing Delta table to {DELTA_PATH}...")

(
    df_typed
    .write
    .format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .partitionBy("year", "month")
    .save(DELTA_PATH)
)

# Verify write
delta_count = spark.read.format("delta").load(DELTA_PATH).count()
print(f"  Delta table written. Row count: {delta_count:,}")

# Show Delta table history
print("\n  Delta table history:")
delta_table = DeltaTable.forPath(spark, DELTA_PATH)
delta_table.history().select("version", "timestamp", "operation", "operationMetrics").show(5, truncate=False)


# ── Step 7: MERGE (Upsert) Example ───────────────────────────────────────────

print("\n[7/7] Demonstrating Delta MERGE (upsert)...")

# Simulate new/updated orders arriving
new_orders_data = [
    # Updated order (order_id=1001, amount changed)
    ("1001", "C001", "Widget A", "35.99", "2", "2024-01-15", "completed", "us-east"),
    # New order
    ("9001", "C010", "Widget C", "99.99", "1", "2024-01-20", "completed", "us-west"),
    ("9002", "C011", "Widget A", "29.99", "3", "2024-01-20", "completed", "eu-west"),
]

df_new = (
    spark.createDataFrame(new_orders_data, schema=orders_schema)
    .withColumn("amount",       F.col("amount").cast(DecimalType(10, 2)))
    .withColumn("quantity",     F.col("quantity").cast(IntegerType()))
    .withColumn("order_date",   F.to_date(F.col("order_date"), "yyyy-MM-dd"))
    .withColumn("total_amount", F.round(F.col("amount") * F.col("quantity"), 2))
    .withColumn("year",         F.year(F.col("order_date")))
    .withColumn("month",        F.month(F.col("order_date")))
    .withColumn("day_of_week",  F.dayofweek(F.col("order_date")))
    .withColumn("is_weekend",   F.when(F.col("day_of_week").isin(1, 7), True).otherwise(False))
    .withColumn("ingested_at",  F.current_timestamp())
)

print(f"  New/updated orders to merge: {df_new.count()}")

# MERGE: update existing orders, insert new ones
(
    delta_table.alias("target")
    .merge(
        df_new.alias("source"),
        "target.order_id = source.order_id"
    )
    .whenMatchedUpdate(set={
        "amount":       "source.amount",
        "quantity":     "source.quantity",
        "total_amount": "source.total_amount",
        "status":       "source.status",
        "ingested_at":  "source.ingested_at",
    })
    .whenNotMatchedInsertAll()
    .execute()
)

post_merge_count = spark.read.format("delta").load(DELTA_PATH).count()
print(f"  Post-MERGE row count: {post_merge_count:,} (was {delta_count:,})")

# Show updated history
print("\n  Delta table history after MERGE:")
delta_table.history().select("version", "timestamp", "operation").show(5, truncate=False)


# ── Bonus: Time Travel ────────────────────────────────────────────────────────

print("\n[Bonus] Delta time travel...")

# Query version 0 (before MERGE)
df_v0 = spark.read.format("delta").option("versionAsOf", 0).load(DELTA_PATH)
print(f"  Version 0 (before MERGE): {df_v0.count():,} rows")

# Query current version
df_current = spark.read.format("delta").load(DELTA_PATH)
print(f"  Current version: {df_current.count():,} rows")

# Query by timestamp (1 hour ago)
one_hour_ago = (datetime.datetime.now() - datetime.timedelta(hours=1)).strftime("%Y-%m-%d %H:%M:%S")
try:
    df_ts = spark.read.format("delta").option("timestampAsOf", one_hour_ago).load(DELTA_PATH)
    print(f"  Version as of {one_hour_ago}: {df_ts.count():,} rows")
except Exception as e:
    print(f"  Timestamp query: {e}")


# ── Bonus: OPTIMIZE + ZORDER ──────────────────────────────────────────────────

print("\n[Bonus] OPTIMIZE + ZORDER...")

spark.sql(f"""
    OPTIMIZE delta.`{DELTA_PATH}`
    ZORDER BY (order_date, product)
""")

print("  OPTIMIZE + ZORDER complete. Files compacted and co-located.")

# Show final stats
print("\n" + "=" * 60)
print("  JOB COMPLETE")
print("=" * 60)
print(f"  Raw rows read    : {raw_count:,}")
print(f"  Clean rows       : {clean_count:,}")
print(f"  Delta rows       : {post_merge_count:,}")
print(f"  Total revenue    : ${total_revenue:,.2f}")
print(f"  Delta path       : {DELTA_PATH}")
print("=" * 60)
