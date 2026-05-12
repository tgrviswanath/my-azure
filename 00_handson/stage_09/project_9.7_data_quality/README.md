# Project 9.7 — Data Quality Validation with Great Expectations on Azure

## What This Does

Implements automated data quality validation using Great Expectations (GX) at every stage of the pipeline. Validates Parquet files in ADLS Gen2 after ADF ETL completes. An Azure Function triggers the validation, and results (pass/fail) are stored as Data Docs in Azure Blob Storage. Failed validations trigger alerts via Azure Monitor.

## Services Used

| Service | Purpose | SKU |
|---|---|---|
| Great Expectations | Data quality framework | Open source (free) |
| Azure Function | Trigger validation after ADF pipeline | Consumption plan |
| ADLS Gen2 | Data source for validation | Standard LRS |
| Azure Blob Storage | Data Docs hosting | Standard LRS |
| Azure Monitor | Alert on validation failure | Free tier |

## Architecture

```
ADF ETL completes
      │
      ▼
Azure Function (HTTP trigger or Event Grid)
      │
      ▼
Great Expectations Validation
  ┌──────────────────────────────────────────────────────┐
  │ Expectation Suite: orders_suite                      │
  │                                                      │
  │ ✅ row_count > 0                                     │
  │ ✅ order_id: not null, unique                        │
  │ ✅ amount: > 0, < 10000                              │
  │ ✅ product: in known list (99% match)                │
  │ ✅ order_date: valid format, not future              │
  │ ✅ status: in [pending, processing, completed, ...]  │
  └──────────────────────────────────────────────────────┘
      │
      ├── PASS → Continue pipeline
      │
      └── FAIL → Azure Monitor Alert → Email/Teams
                 Data Docs updated with failure details
```

## How to Run

### Prerequisites
```bash
pip install great-expectations azure-storage-blob azure-identity
```

### Run Validation
```bash
export AZURE_STORAGE_ACCOUNT="your-storage-account"
export AZURE_STORAGE_CONTAINER="processed"
export AZURE_BLOB_PATH="orders/2024/01/orders.parquet"
python code/validate_orders.py
```

### Expected Output
```
Great Expectations — Orders Data Quality Report
================================================
Suite: orders_suite
Data: processed/orders/2024/01/orders.parquet
Rows: 1,000

Results:
  ✅ PASS  expect_table_row_count_to_be_between (min=1)
  ✅ PASS  expect_column_values_to_not_be_null (order_id)
  ✅ PASS  expect_column_values_to_be_unique (order_id)
  ✅ PASS  expect_column_values_to_be_between (amount: 0-10000)
  ❌ FAIL  expect_column_values_to_be_in_set (product: 97.3% match, expected 99%)
  ✅ PASS  expect_column_values_to_match_regex (order_date)

Overall: FAILED (1/6 expectations failed)
```

## Lessons Learned

- **Expectations are SQL assertions**: Under the hood, GX generates SQL or Pandas operations. Think of them as `assert` statements for your data.
- **Data Docs are invaluable**: The HTML report shows exactly which rows failed which expectations. Share with data producers to fix upstream issues.
- **Start with critical expectations**: Don't add 50 expectations on day 1. Start with: row count > 0, primary key not null + unique, critical columns not null.
- **Threshold expectations**: Use `mostly=0.99` for expectations that allow a small percentage of failures (e.g., 1% of products may be new/unknown).
- **Azure Function trigger**: Trigger validation via Event Grid when a new blob arrives in ADLS, not on a schedule.

## Code

See `code/validate_orders.py` — complete GX validation suite with 6 expectations, runs against Parquet from ADLS, prints pass/fail report.
