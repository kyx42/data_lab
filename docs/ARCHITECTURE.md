# Architecture Overview

Describe the end-to-end topology of the lakehouse stack, including ingestion sources, storage layers, processing engines, orchestration, observability, and user-facing analytics.

For le plan d’implémentation infra on-prem, voir `docs/INFRA_ROADMAP.md`.

```mermaid
flowchart LR
    subgraph Source
        A[Operational DBs]
        B[APIs / SaaS]
        C[Files]
    end

    subgraph Ingestion
        D[Airbyte / Custom Ingest]
    end

    subgraph Lakehouse
        E[Raw Zone]
        F[Intermediate Zone]
        G[Feature Store / Processed Zone]
    end

    subgraph Orchestration
        H[Airflow]
    end

    subgraph Training
        I[ML Pipelines]
        J[LLM Fine Tuning]
    end

    subgraph Observability
        K[Prometheus]
        L[Grafana]
        M[Datadog]
        N[Superset]
    end

    subgraph Serving
        O[MLflow Registry]
        P[MCP Agents]
        Q[Dashboards / APIs]
    end

    A & B & C --> D --> E --> F --> G
    G --> I --> O
    G --> J --> P
    H -. manages .- D
    H -. schedules .- I
    H -. schedules .- J
    I & J --> K --> L
    I & J --> M
    G --> N
    O & P --> Q
```

Adapt the diagram as the architecture evolves (cloud vs on-prem, additional services, etc.).
