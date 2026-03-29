import duckdb
import pandas as _pd

DB_PATH = "/workspace/pf_northwind/duckdb/northwind_dw.duckdb"
DATA_DIR = "/workspace/pf_northwind/duckdb/data"


class _SafeProxy:
    """Wraps DuckDB connection to fix fetchdf() segfault in v0.10 (pandas/arrow incompatibility)."""

    def __init__(self, c):
        object.__setattr__(self, "_c", c)

    def execute(self, *a, **k):
        self._c.execute(*a, **k)
        return self

    def fetchdf(self):
        rows = self._c.fetchall()
        cols = [d[0] for d in self._c.description]
        return _pd.DataFrame(rows, columns=cols)

    def __getattr__(self, name):
        return getattr(object.__getattribute__(self, "_c"), name)


def get_conn(db_path=DB_PATH):
    """Return a DuckDB connection wrapped with _SafeProxy."""
    return _SafeProxy(duckdb.connect(db_path))
