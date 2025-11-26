"""Example Airflow DAG orchestrating ingestion and training."""

from __future__ import annotations

from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator


def ingest_task() -> None:
    """Placeholder ingestion task."""
    # TODO: Call real ingestion functions from src.ingest
    print("Ingesting data...")


def train_task() -> None:
    """Placeholder training task."""
    # TODO: Trigger ML training using src.training.trainer
    print("Training model...")


with DAG(
    dag_id="example_data_pipeline",
    description="Sample pipeline showcasing ingestion and training workflow.",
    start_date=datetime(2024, 1, 1),
    schedule_interval="@daily",
    catchup=False,
    tags=["example", "lakehouse"],
) as dag:
    ingest = PythonOperator(task_id="ingest_data", python_callable=ingest_task)
    train = PythonOperator(task_id="train_model", python_callable=train_task)

    ingest >> train
