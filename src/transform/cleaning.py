"""Data cleaning helpers applied after ingestion."""

from __future__ import annotations

import pandas as pd


def drop_empty_columns(frame: pd.DataFrame, threshold: float = 0.9) -> pd.DataFrame:
    """Drop columns with ratio of missing values above `threshold`.

    Args:
        frame: Input dataframe.
        threshold: Maximum allowed ratio of missing values (0-1 range).

    Returns:
        A new dataframe with sparse columns removed.
    """
    if not 0 <= threshold <= 1:
        msg = "threshold should be between 0 and 1"
        raise ValueError(msg)

    missing_ratio = frame.isna().mean()
    keep_columns = missing_ratio[missing_ratio <= threshold].index
    return frame.loc[:, keep_columns].copy()
