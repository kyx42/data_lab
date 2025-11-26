# Data Stack Lakehouse Sandbox

This repository hosts an opinionated playground to explore modern data and MLOps/GenAIOps practices while building a lightweight lakehouse stack. The goal is to iterate quickly on ingestion, transformation, model training, orchestration, observability, and LLM experimentation workflows.

## Repository layout

- `src/` – Python source code for data pipelines and ML/LLM jobs.
  - `src/ingest/` – Data ingestion scripts and connectors.
  - `src/transform/` – Data transformation and feature engineering logic.
  - `src/training/` – Classical ML training, evaluation, and deployment helpers.
  - `src/genai/` – LLM prompt tooling, experimentation notebooks, and agent logic.
- `apps/airflow-dags/` – dépôt applicatif contenant les DAGs/plug-ins Airflow et le `Dockerfile`.
- `apps/airflow-dags/dags/` – définitions des DAGs pour l’orchestration ETL/ML.
- `data/` – DVC-managed datasets split into `raw/`, `intermediate/`, and `processed/` zones.
- `models/` – Model artifacts tracked via MLflow (or Kubeflow).
- `monitoring/` – Dashboards and configuration for Prometheus, Grafana, Datadog, and Superset.
- `ci/` – CI/CD pipeline definitions (GitLab or alternative).
- `docs/` – Technical and functional documentation, diagrams, runbooks.
- `infra/` – Terraform, Helm charts, or other infrastructure-as-code assets.
- `prompts/` – Prompt templates and feedback artifacts for GenAIOps workflows.
- `tests/` – Pytest-based unit and integration tests.

## Getting started

1. Create and activate a Python 3.11 virtual environment.
2. Install project requirements with `pip install -r requirements.txt` (to be populated).
3. Initialize DVC: `dvc init` and configure a remote for dataset storage.
4. Set up MLflow tracking URI (e.g. local server or managed service).
5. Configure Airflow with the DAGs in `apps/airflow-dags/dags/` and connect to your data lake/warehouse.
6. Provision monitoring stack (Prometheus + Grafana, Datadog, Superset) using files in `monitoring/`.
7. Document every dataset change in `docs/DATASET.md` and experiments in MLflow.

This scaffold is intentionally minimal. Extend each module with concrete pipelines, workflows, and infrastructure as you iterate on the data stack.

## TODO (déploiements prioritaires)

- [ ] Déployer une forge GitLab pour centraliser le code et préparer l’intégration GitOps.
- [ ] Déployer Jenkins afin d’orchestrer la chaîne CI/CD (lint, tests, build d’images, déploiements).
- [ ] Explorer les ingress/API gateway comme Apache APISIX et Kong pour compléter/valider l’usage actuel de Traefik.
- [ ] Lancer une piste GenAI dédiée aux Tiny Recursive Models (TRM) : cadrer un workflow d’expérimentation/fine tuning pour comparer ces modèles légers aux approches LLM classiques.
- [ ] Évaluer l’utilisation de dbt (core ou Cloud) pour orchestrer les transformations SQL (Trino/DuckDB) et industrialiser le versioning/tests des modèles analytiques.
- [ ] Explorer DuckDB comme moteur analytique léger (OLAP local + serverless) pour comparer ses performances/coûts à Trino/Spark sur les datasets stockés dans MinIO et documenter le feedback.
- [ ] Industrialiser l’observabilité Spark : Spark Operator + History Server, event logs sur MinIO, export JMX via `jmx_prometheus_javaagent`, dashboards Grafana pour CPU/mémoire/shuffle afin de diagnostiquer les jobs.
- [ ] Mettre en place la télémétrie réseau/infra (Cilium + Hubble ou équivalent) pour tracer les flux des jobs Spark/Trino, identifier les bottlenecks réseau et corréler avec les ressources Kubernetes.
- [ ] Documenter un runbook de debug Spark (config tuning, dynamic allocation, quotas K8s) dans `docs/RUNBOOKS/` et intégrer les métriques/logs Loki/Prometheus nécessaires.
- [ ] Prototyper l’intégration Spark Operator avec Airflow/Dagster : soumettre des `SparkApplication` depuis les DAGs/assets, monitorer l’état via l’API K8s et déployer les jobs PySpark comme workloads éphémères.
- [ ] Étudier le déploiement d’Artifactory comme registry privé (packages Docker/Helm) pour le cluster et GitLab.

> ℹ **Argo CD & Helm hooks**  
> Les charts comme Apache Airflow (>=1.18.0) créent leurs jobs (`run-airflow-migrations`, `create-user`, etc.) via des hooks Helm (`helm.sh/hook=post-install`). Argo CD Ignore ces hooks par design : il applique seulement les manifests déclarés. Pense donc à surcharger les valeurs (`migrateDatabaseJob.useHelmHooks=false`, `createUserJob.useHelmHooks=false`, etc.) pour que les Jobs apparaissent dans l’état désiré et soient lancés par Argo CD. À ce jour, même les versions récentes du chart Airflow conservent ce comportement par défaut.

## TODO (exploration Kubernetes)

- [ ] Écrire un runbook « NetworkPolicy 101 » et valider la mise en quarantaine des namespaces data/LLM (deny-all + ouvertures ciblées).
- [ ] Cartographier les usages des Helm hooks dans nos charts (Airflow, cert-manager, etc.) pour documenter comment les GitOps (Argo CD/Fleet) gèrent — ou ignorent — ces hooks, et proposer des stratégies de contournement.
