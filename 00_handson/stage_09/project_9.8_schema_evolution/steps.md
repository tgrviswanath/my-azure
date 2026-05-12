# Steps — Project 9.8 Schema Evolution & Partitioning

## Phase 1 — Create Delta Table v1

```python
# In Databricks notebook
from pyspark.sql import SparkSession
from delta.tables import DeltaTable

spark = SparkSession.builder.getOrCreate()

# Create v1 schema: order_id, product, amount
data_v1 = [
    ("ORD-001", "Widget A", 29.99),
    ("ORD-002", "Widget B", 49.99),
    ("ORD-003", "Widget C", 19.99),
]
df_v1 = spark.createDataFrame(data_v1, ["order_id", "product", "amount"])
df_v1.write.format("delta").partitionBy("product").save("/mnt/datalake/orders_delta")
print("Delta table v1 created")
```

---

## Phase 2 — Add New Column (Backward Compatible)

```python
# Add customer_tier column — backward compatible (nullable)
data_v2 = [
    ("ORD-004", "Widget A", 39.99, "gold"),
    ("ORD-005", "Widget B", 59.99, "silver"),
]
df_v2 = spark.createDataFrame(data_v2, ["order_id", "product", "amount", "customer_tier"])

# mergeSchema=True allows adding new columns
df_v2.write.format("delta") \
    .option("mergeSchema", "true") \
    .mode("append") \
    .save("/mnt/datalake/orders_delta")

print("Schema evolved — customer_tier column added")
```

---

## Phase 3 — Test Schema Merge

```python
# Read back — old rows have null for customer_tier
df = spark.read.format("delta").load("/mnt/datalake/orders_delta")
df.show()
df.printSchema()
# customer_tier is nullable — old rows show null
```

---

## Phase 4 — Partition Pruning

```python
# Query with partition filter — only reads Widget A partition
df_filtered = spark.read.format("delta") \
    .load("/mnt/datalake/orders_delta") \
    .filter("product = 'Widget A'")

df_filtered.explain()  # Shows PartitionFilters in plan
df_filtered.show()
```

---

## Phase 5 — OPTIMIZE + ZORDER

```python
# Compact small files and co-locate related data
spark.sql("""
    OPTIMIZE delta.`/mnt/datalake/orders_delta`
    ZORDER BY (order_id)
""")

# Time travel — read previous version
df_v1_again = spark.read.format("delta") \
    .option("versionAsOf", 0) \
    .load("/mnt/datalake/orders_delta")
df_v1_again.show()
```

---

## Screenshots to Take
- [ ] Delta table v1 created with 3 rows
- [ ] Schema after evolution showing customer_tier column
- [ ] Old rows showing null for new column
- [ ] OPTIMIZE output showing files compacted
- [ ] Time travel reading version 0
