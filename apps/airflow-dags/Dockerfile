FROM apache/airflow:3.0.2-python3.11

USER root

# Copie les DAGs/plug-ins et dépendances Python dans l'image
COPY dags/ /opt/airflow/dags
COPY plugins/ /opt/airflow/plugins
COPY requirements-dags.txt /opt/airflow/requirements-dags.txt

RUN pip install --no-cache-dir -r /opt/airflow/requirements-dags.txt || true

USER airflow
