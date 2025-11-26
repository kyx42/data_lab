# Monitoring Stack

This directory stores configuration for observability tooling:

- `prometheus/` – scrape configs, alert rules, and recording rules.
- `grafana/` – dashboards JSON and provisioning files.
- `datadog/` – monitor definitions, synthetics scripts, notebooks.
- `superset/` – charts, dashboards, and data source definitions.

Keep secrets (API keys, passwords) in a secure secret manager. Only commit sanitized examples or templates.
