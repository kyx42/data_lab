# Documentation Hub

Use this directory to centralize functional and technical documentation for the lakehouse stack. Suggested sections:

- `ARCHITECTURE.md` – high level overview with diagrams of data flows, toolchain choices, and environments.
- `RUNBOOKS/` – standard operating procedures (e.g. restart Airflow, recover DVC remote). Inclut `RUNBOOKS/LAB_BOOTSTRAP.md` pour le flux GitLab + PostgreSQL + Vault.
- `DATASET.md` – detailed lineage, schema versions, and quality checks for each dataset.
- `EXPERIMENTS.md` – mapping between MLflow runs, experiment goals, and outcomes.
- `AGENTS.md` – instructions dedicated to LLM agents and MCP workflows.

Include Mermaid or PlantUML diagrams wherever possible to make the orchestration and dependencies easier to grasp.
