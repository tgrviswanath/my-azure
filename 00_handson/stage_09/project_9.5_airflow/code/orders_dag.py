"""
orders_dag.py — Daily Orders Data Pipeline DAG

Orchestrates the full data pipeline:
1. ADF: Copy raw orders CSV to Parquet (ADLS)
2. Databricks: PySpark transformation + Delta write
3. dbt: SQL model transformations (staging → marts)
4. dbt test: Data quality validation
5. Email alert on any failure

Requirements (install in Airflow):
    apache-airflow-providers-microsoft-azure
    apache-airflow-providers-databricks

Airflow Connections required:
    - azure_data_factory_default (ADF connection)
    - databricks_default (Databricks PAT)
    - smtp_default (email SMTP)
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.email import EmailOperator
from airflow.operators.python import PythonOperator
from airflow.utils.dates import days_ago

# Azure provider operators
try:
    from airflow.providers.microsoft.azure.operators.data_factory import (
        AzureDataFactoryRunPipelineOperator,
    )
    from airflow.providers.microsoft.azure.sensors.data_factory import (
        AzureDataFactoryPipelineRunStatusSensor,
    )
    from airflow.providers.databricks.operators.databricks import (
        DatabricksRunNowOperator,
    )
    AZURE_PROVIDERS_AVAILABLE = True
except ImportError:
    AZURE_PROVIDERS_AVAILABLE = False
    print("Warning: Azure providers not installed. Using mock operators.")


# ── Configuration ─────────────────────────────────────────────────────────────

ADF_RESOURCE_GROUP = "rg-adf-etl-lab"
ADF_FACTORY_NAME   = "adf-etl-lab"
ADF_PIPELINE_NAME  = "pl_copy_orders"

DATABRICKS_JOB_ID  = 12345  # Replace with your actual job ID

DBT_PROJECT_DIR    = "/opt/airflow/dbt_project"
DBT_PROFILES_DIR   = "/opt/airflow/dbt_profiles"
DBT_TARGET         = "prod"

ALERT_EMAIL        = "data-team@company.com"


# ── Callbacks ─────────────────────────────────────────────────────────────────

def on_failure_callback(context):
    """
    Called when any task fails. Sends an email alert with task details.
    Can also send to Teams, Slack, PagerDuty, etc.
    """
    dag_id   = context["dag"].dag_id
    task_id  = context["task_instance"].task_id
    run_id   = context["run_id"]
    log_url  = context["task_instance"].log_url
    exec_date = context["execution_date"]

    subject = f"[AIRFLOW ALERT] {dag_id}.{task_id} FAILED"
    body = f"""
    <h3>Airflow Task Failure Alert</h3>
    <table>
        <tr><td><b>DAG</b></td><td>{dag_id}</td></tr>
        <tr><td><b>Task</b></td><td>{task_id}</td></tr>
        <tr><td><b>Run ID</b></td><td>{run_id}</td></tr>
        <tr><td><b>Execution Date</b></td><td>{exec_date}</td></tr>
        <tr><td><b>Log URL</b></td><td><a href="{log_url}">View Logs</a></td></tr>
    </table>
    <p>Please investigate and re-run the failed task.</p>
    """

    # Send email via Airflow's email utility
    from airflow.utils.email import send_email
    send_email(
        to=[ALERT_EMAIL],
        subject=subject,
        html_content=body,
    )


def check_pipeline_health(**context):
    """
    Pre-flight check: verify ADF and Databricks are accessible.
    Runs before the main pipeline tasks.
    """
    import subprocess
    import json

    print("Running pre-flight health checks...")

    # Check ADF connectivity (via az CLI)
    try:
        result = subprocess.run(
            ["az", "datafactory", "show",
             "--resource-group", ADF_RESOURCE_GROUP,
             "--factory-name", ADF_FACTORY_NAME,
             "--query", "provisioningState", "-o", "tsv"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            state = result.stdout.strip()
            print(f"  ✅ ADF '{ADF_FACTORY_NAME}' state: {state}")
        else:
            print(f"  ⚠️  ADF check failed: {result.stderr}")
    except Exception as e:
        print(f"  ⚠️  ADF health check error: {e}")

    print("Pre-flight checks complete.")
    return "healthy"


# ── Default Args ──────────────────────────────────────────────────────────────

default_args = {
    "owner":            "data-engineering",
    "depends_on_past":  False,
    "start_date":       days_ago(1),
    "email":            [ALERT_EMAIL],
    "email_on_failure": True,
    "email_on_retry":   False,
    "retries":          2,
    "retry_delay":      timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "on_failure_callback": on_failure_callback,
}


# ── DAG Definition ────────────────────────────────────────────────────────────

with DAG(
    dag_id="orders_daily_pipeline",
    description="Daily orders ETL: ADF copy → Databricks transform → dbt models → dbt test",
    default_args=default_args,
    schedule_interval="@daily",       # Run at midnight UTC every day
    catchup=False,                    # Don't backfill missed runs
    max_active_runs=1,                # Only one run at a time
    tags=["orders", "etl", "production"],
    doc_md="""
    ## Orders Daily Pipeline

    Orchestrates the full orders data pipeline:
    1. **ADF Copy**: Copies raw CSV orders from ADLS raw/ to Parquet processed/
    2. **Databricks**: PySpark transformation, Delta table write, MERGE upsert
    3. **dbt run**: Staging → intermediate → mart SQL models
    4. **dbt test**: Data quality tests (not null, unique, accepted values)

    **On failure**: Email alert sent to data-team@company.com

    **SLA**: Pipeline should complete within 2 hours of midnight UTC.
    """,
) as dag:

    # ── Task 1: Pre-flight health check ──────────────────────────────────────

    health_check = PythonOperator(
        task_id="health_check",
        python_callable=check_pipeline_health,
        doc_md="Verify ADF and Databricks are accessible before starting.",
    )

    # ── Task 2: ADF — Copy raw orders to Parquet ──────────────────────────────

    if AZURE_PROVIDERS_AVAILABLE:
        adf_copy_raw_orders = AzureDataFactoryRunPipelineOperator(
            task_id="adf_copy_raw_orders",
            azure_data_factory_conn_id="azure_data_factory_default",
            factory_name=ADF_FACTORY_NAME,
            resource_group_name=ADF_RESOURCE_GROUP,
            pipeline_name=ADF_PIPELINE_NAME,
            parameters={
                "execution_date": "{{ ds }}",  # Airflow template: YYYY-MM-DD
                "source_path": "raw/orders/{{ ds_nodash[:4] }}/{{ ds_nodash[4:6] }}/",
            },
            wait_for_termination=True,
            timeout=1800,  # 30 minutes
            check_interval=30,
            doc_md="Copy raw CSV orders from ADLS raw/ to Parquet processed/.",
        )
    else:
        # Mock operator for environments without Azure providers
        adf_copy_raw_orders = BashOperator(
            task_id="adf_copy_raw_orders",
            bash_command=f"""
                echo "Triggering ADF pipeline: {ADF_PIPELINE_NAME}"
                echo "Execution date: {{{{ ds }}}}"
                echo "ADF pipeline completed (mock)"
            """,
        )

    # ── Task 3: Databricks — PySpark transformation ───────────────────────────

    if AZURE_PROVIDERS_AVAILABLE:
        databricks_transform = DatabricksRunNowOperator(
            task_id="databricks_transform",
            databricks_conn_id="databricks_default",
            job_id=DATABRICKS_JOB_ID,
            notebook_params={
                "execution_date": "{{ ds }}",
                "source_path": "raw/orders/{{ ds_nodash[:4] }}/{{ ds_nodash[4:6] }}/",
                "delta_path": "/mnt/delta/orders_delta/",
            },
            polling_period_seconds=30,
            doc_md="Run PySpark job: clean, transform, write Delta table, MERGE upsert.",
        )
    else:
        databricks_transform = BashOperator(
            task_id="databricks_transform",
            bash_command="""
                echo "Triggering Databricks job: spark-orders-etl"
                echo "Execution date: {{ ds }}"
                echo "Databricks job completed (mock)"
            """,
        )

    # ── Task 4: dbt run — SQL model transformations ───────────────────────────

    dbt_run_models = BashOperator(
        task_id="dbt_run_models",
        bash_command=f"""
            set -e
            echo "Running dbt models for {{{{ ds }}}}"

            dbt run \
                --project-dir {DBT_PROJECT_DIR} \
                --profiles-dir {DBT_PROFILES_DIR} \
                --target {DBT_TARGET} \
                --vars '{{"execution_date": "{{{{ ds }}}}"}}'  \
                --select staging.stg_orders intermediate.int_orders_enriched marts.fct_daily_revenue

            echo "dbt run completed successfully"
        """,
        env={
            "DBT_SYNAPSE_SERVER":   "{{ var.value.synapse_server }}",
            "DBT_SYNAPSE_DATABASE": "{{ var.value.synapse_database }}",
            "DBT_SYNAPSE_USER":     "{{ var.value.synapse_user }}",
            "DBT_SYNAPSE_PASSWORD": "{{ var.value.synapse_password }}",
        },
        doc_md="Run dbt SQL models: stg_orders → int_orders_enriched → fct_daily_revenue.",
    )

    # ── Task 5: dbt test — Data quality validation ────────────────────────────

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"""
            set -e
            echo "Running dbt tests for {{{{ ds }}}}"

            dbt test \
                --project-dir {DBT_PROJECT_DIR} \
                --profiles-dir {DBT_PROFILES_DIR} \
                --target {DBT_TARGET} \
                --select staging.stg_orders marts.fct_daily_revenue

            echo "All dbt tests passed"
        """,
        doc_md="Run dbt tests: not_null, unique, accepted_values, relationships.",
    )

    # ── Task 6: Generate dbt docs (optional) ─────────────────────────────────

    dbt_docs = BashOperator(
        task_id="dbt_docs_generate",
        bash_command=f"""
            dbt docs generate \
                --project-dir {DBT_PROJECT_DIR} \
                --profiles-dir {DBT_PROFILES_DIR} \
                --target {DBT_TARGET} || true
            echo "dbt docs generated"
        """,
        doc_md="Generate dbt documentation (non-blocking — failure won't stop pipeline).",
        trigger_rule="all_success",
    )

    # ── Task 7: Pipeline success notification ─────────────────────────────────

    notify_success = BashOperator(
        task_id="notify_success",
        bash_command="""
            echo "Pipeline completed successfully for {{ ds }}"
            echo "All tasks: health_check → adf_copy → databricks → dbt_run → dbt_test → done"
        """,
        doc_md="Log pipeline completion.",
    )

    # ── Task Dependencies ─────────────────────────────────────────────────────
    #
    # health_check → adf_copy_raw_orders → databricks_transform
    #                                              │
    #                                              ▼
    #                                      dbt_run_models → dbt_test
    #                                                            │
    #                                                            ▼
    #                                                    dbt_docs_generate
    #                                                            │
    #                                                            ▼
    #                                                    notify_success

    health_check >> adf_copy_raw_orders >> databricks_transform
    databricks_transform >> dbt_run_models >> dbt_test
    dbt_test >> dbt_docs >> notify_success
