"""Training utilities for classical ML workflows."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

import joblib
import mlflow
import pandas as pd
from sklearn.base import BaseEstimator
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split


@dataclass(slots=True)
class TrainingConfig:
    """Configuration for supervised training."""

    target_column: str
    test_size: float = 0.2
    random_state: int = 42


def train_classifier(
    frame: pd.DataFrame,
    estimator: BaseEstimator,
    config: TrainingConfig,
    mlflow_run_name: str,
    artifact_dir: Path,
    feature_columns: list[str] | None = None,
    extra_params: Mapping[str, Any] | None = None,
) -> float:
    """Train and evaluate a classifier, logging results to MLflow."""
    if feature_columns is None:
        feature_columns = [c for c in frame.columns if c != config.target_column]

    features = frame[feature_columns]
    target = frame[config.target_column]

    x_train, x_test, y_train, y_test = train_test_split(
        features,
        target,
        test_size=config.test_size,
        random_state=config.random_state,
        stratify=target,
    )

    with mlflow.start_run(run_name=mlflow_run_name) as run:
        if extra_params:
            estimator.set_params(**extra_params)
            mlflow.log_params(dict(extra_params))

        estimator.fit(x_train, y_train)
        predictions = estimator.predict(x_test)

        accuracy = accuracy_score(y_test, predictions)
        mlflow.log_metric("accuracy", accuracy)

        artifact_dir.mkdir(parents=True, exist_ok=True)
        artifact_path = artifact_dir / f"{run.info.run_id}_model.pkl"
        joblib.dump(estimator, artifact_path)
        mlflow.log_artifact(str(artifact_path), artifact_path="model")

    return accuracy
