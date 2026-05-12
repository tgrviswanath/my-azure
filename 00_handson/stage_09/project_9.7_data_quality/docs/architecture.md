# Architecture — Project 9.7: Data Quality with Great Expectations on Azure

## ASCII Diagram

```
                    DATA QUALITY ARCHITECTURE
                    ==========================

  PIPELINE                    VALIDATION                    REPORTING
  ┌──────────────┐            ┌──────────────────────────┐  ┌──────────────┐
  │ ADF ETL      │            │ Great Expectations       │  │ Data Docs    │
  │ completes    │──trigger──▶│                          │  │ (HTML)       │
  └──────────────┘            │ Expectation Suite:       │  │              │
                              │ orders_suite             │  │ ✅ Passed: 5 │
  ┌──────────────┐            │                          │  │ ❌ Failed: 1 │
  │ New blob in  │──Event ───▶│ Expectations:            │  │              │
  │ ADLS         │  Grid      │ • row_count > 0          │  │ Failure      │
  └──────────────┘            │ • order_id not null      │  │ details:     │
                              │ • order_id unique        │  │ Row 42:      │
  ┌──────────────┐            │ • amount > 0             │  │ product=NULL │
  │ Azure        │            │ • product in set (99%)   │  └──────────────┘
  │ Function     │            │ • order_date valid       │
  │ (trigger)    │            └──────────┬───────────────┘
  └──────────────┘                       │
                                         ├── PASS → next pipeline stage
                                         │
                                         └── FAIL → Azure Monitor Alert
                                                     → Email/Teams
                                                     → Block pipeline

  EXPECTATION TYPES
  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │  Table-level:                                                │
  │  • expect_table_row_count_to_be_between(min=1, max=1000000) │
  │  • expect_table_columns_to_match_ordered_list(...)          │
  │                                                              │
  │  Column-level:                                               │
  │  • expect_column_values_to_not_be_null(column='order_id')   │
  │  • expect_column_values_to_be_unique(column='order_id')     │
  │  • expect_column_values_to_be_between(column='amount',      │
  │      min_value=0, max_value=10000)                          │
  │  • expect_column_values_to_be_in_set(column='product',      │
  │      value_set=['Widget A', 'Widget B', ...], mostly=0.99)  │
  │  • expect_column_values_to_match_regex(column='order_date', │
  │      regex=r'^\d{4}-\d{2}-\d{2}$')                         │
  │  • expect_column_mean_to_be_between(column='amount',        │
  │      min_value=10, max_value=500)                           │
  └──────────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Description | Example |
|---|---|---|
| **Expectation** | A verifiable assertion about data | `expect_column_values_to_not_be_null` |
| **Expectation Suite** | Named collection of expectations | `orders_suite` |
| **Batch** | A chunk of data to validate | One Parquet file |
| **Checkpoint** | Bundles suite + batch + actions | Run validation + save results |
| **Validation Result** | Pass/fail result for each expectation | `{"success": false, "result": {...}}` |
| **Data Docs** | HTML report of validation results | Hosted on Azure Blob Storage |
| **mostly** | Allow a percentage of failures | `mostly=0.99` = 99% must pass |
| **Action** | What to do after validation | Save results, send alert, update Data Docs |
