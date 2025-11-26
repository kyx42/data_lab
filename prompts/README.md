# Prompt Templates

Store reusable LLM prompts as JSON (`templates.json`) or YAML. Pair prompts with evaluation metadata (success rate, user feedback) to iterate quickly.

Suggested structure:

```json
[
  {
    "name": "sales_summary",
    "text": "Summarize the sales KPIs for {{ date }}.",
    "tags": ["reporting"],
    "metadata": {"owner": "data-team"}
  }
]
```

Link prompt versions to MLflow runs or a dedicated experiment tracker for GenAIOps workflows.
