# Architecture — Project 9.5: Apache Airflow on Azure AKS

## ASCII Diagram

```
                    AIRFLOW ON AKS ARCHITECTURE
                    ============================

  KUBERNETES CLUSTER (AKS)
  ┌─────────────────────────────────────────────────────────────────┐
  │  Namespace: airflow                                             │
  │                                                                 │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
  │  │ Webserver    │  │ Scheduler    │  │ PostgreSQL           │  │
  │  │ Pod          │  │ Pod          │  │ (metadata DB)        │  │
  │  │              │  │              │  │                      │  │
  │  │ :8080        │  │ Parses DAGs  │  │ dag_run, task_instance│  │
  │  │ UI + REST API│  │ Schedules    │  │ xcom, log, etc.      │  │
  │  └──────┬───────┘  └──────┬───────┘  └──────────────────────┘  │
  │         │                 │                                     │
  │         └────────┬────────┘                                     │
  │                  │ KubernetesExecutor                           │
  │                  ▼                                              │
  │  ┌──────────────────────────────────────────────────────────┐  │
  │  │ Worker Pods (created on-demand per task)                 │  │
  │  │                                                          │  │
  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │  │
  │  │  │ Task: adf_   │  │ Task: dbr_   │  │ Task: dbt_   │   │  │
  │  │  │ copy_orders  │  │ transform    │  │ run_models   │   │  │
  │  │  │              │  │              │  │              │   │  │
  │  │  │ AzureADF     │  │ Databricks   │  │ BashOperator │   │  │
  │  │  │ Operator     │  │ RunNow       │  │ dbt run      │   │  │
  │  │  └──────────────┘  └──────────────┘  └──────────────┘   │  │
  │  └──────────────────────────────────────────────────────────┘  │
  │                                                                 │
  │  ┌──────────────────────────────────────────────────────────┐  │
  │  │ DAG Storage (PVC or GitSync)                             │  │
  │  │ /opt/airflow/dags/orders_dag.py                          │  │
  │  └──────────────────────────────────────────────────────────┘  │
  └─────────────────────────────────────────────────────────────────┘

  EXTERNAL SERVICES
  ┌──────────────────────────────────────────────────────────────────┐
  │                                                                  │
  │  Azure Data Factory ◀── AzureDataFactoryRunPipelineOperator     │
  │  Azure Databricks   ◀── DatabricksRunNowOperator                │
  │  dbt (in container) ◀── BashOperator                            │
  │  Email (SMTP)       ◀── EmailOperator (on_failure_callback)     │
  │                                                                  │
  └──────────────────────────────────────────────────────────────────┘

  DAG DEPENDENCY GRAPH
  ┌──────────────────────────────────────────────────────────────────┐
  │                                                                  │
  │  start ──▶ adf_copy_raw_orders                                  │
  │                    │                                            │
  │                    ▼                                            │
  │            databricks_transform                                 │
  │                    │                                            │
  │                    ▼                                            │
  │            dbt_run_models                                       │
  │                    │                                            │
  │                    ▼                                            │
  │            dbt_test ──▶ end                                     │
  │                                                                  │
  │  Any failure ──▶ on_failure_callback ──▶ EmailOperator          │
  │                                                                  │
  └──────────────────────────────────────────────────────────────────┘
```

## Key Concepts

| Concept | Description | Configuration |
|---|---|---|
| **DAG** | Directed Acyclic Graph of tasks | Python file in `/opt/airflow/dags/` |
| **Operator** | Template for a task (BashOperator, PythonOperator, etc.) | `task = BashOperator(task_id='...', bash_command='...')` |
| **Executor** | How tasks are run (Local, Celery, Kubernetes) | `AIRFLOW__CORE__EXECUTOR=KubernetesExecutor` |
| **Connection** | Stored credentials for external systems | `airflow connections add ...` |
| **XCom** | Cross-task communication (pass values between tasks) | `ti.xcom_push(key='run_id', value=run_id)` |
| **SLA** | Service Level Agreement — alert if task takes too long | `sla=timedelta(hours=2)` |
| **Sensor** | Task that waits for a condition | `AzureDataFactoryPipelineRunStatusSensor` |
| **TaskGroup** | Visual grouping of related tasks | `with TaskGroup('dbt_tasks') as dbt_group:` |
| **Backfill** | Run DAG for historical dates | `airflow dags backfill --start-date 2024-01-01` |
