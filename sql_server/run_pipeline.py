#!/usr/bin/env python3
"""Executa o pipeline SQL do Northwind DW de ponta a ponta.

Roda os scripts de construção em sequência (fonte OLTP, schemas/tabelas,
procedures) e a sequência de execução (EXEC das procedures, na mesma ordem
de run_pipeline.sql), parando no primeiro erro. Ao final, imprime a
contagem de linhas por tabela do modelo gold.

Uso:
    python sql_server/run_pipeline.py             # conecta e executa
    python sql_server/run_pipeline.py --dry-run   # só divide os arquivos e mostra o plano
    python sql_server/run_pipeline.py --help      # todas as flags

Conexão (precedência: argumento > variável de ambiente > default):
    --server / SQL_SERVER   (default: localhost)
    --port   / SQL_PORT     (default: 1434)
    --user   / SQL_USER     (default: sa)
    --password / SQL_PASSWORD (default: YourPassword123)
"""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path

SQL_DIR = Path(__file__).resolve().parent

# Arquivos executados diretamente (contêm CREATE TABLE/PROCEDURE, sem EXEC de outra procedure)
BUILD_FILES = [
    "00_create_northwind_source.sql",
    "01_setup.sql",
    "02_bronze_ingest.sql",
    "03_gold_dims.sql",
    "04_gold_scd2.sql",
    "05_gold_fact_sales.sql",
    "06_gold_fact_fulfillment.sql",
    "07_gold_fact_stock.sql",
    "10_bridge_table.sql",
    "12_scd3.sql",
    "13_factless_fact.sql",
]

# Sequência de execução: nome de procedure a chamar via EXEC, ou arquivo a rodar por inteiro
EXEC_SEQUENCE = [
    "bronze.sp_ingest_bronze",
    "gold.sp_process_dims",
    "gold.sp_process_customers_scd2",
    "gold.sp_process_products_scd2",
    "gold.sp_process_fact_sales",
    "gold.sp_process_fact_fulfillment",
    "gold.sp_process_fact_stock",
    "gold.sp_process_bridge_employee_territory",
    "11_junk_dimension.sql",
    "gold.sp_load_customer_scd3_initial",
    "gold.sp_process_customer_scd3",
    "gold.sp_process_factless_activity",
]

ROW_COUNT_QUERY = """
SELECT 'DimCustomer'                  AS Tabela, COUNT(*) AS Linhas FROM gold.DimCustomer
UNION ALL
SELECT 'DimProduct',                             COUNT(*) FROM gold.DimProduct
UNION ALL
SELECT 'DimEmployee',                            COUNT(*) FROM gold.DimEmployee
UNION ALL
SELECT 'DimCategory',                            COUNT(*) FROM gold.DimCategory
UNION ALL
SELECT 'DimSupplier',                            COUNT(*) FROM gold.DimSupplier
UNION ALL
SELECT 'DimShipper',                             COUNT(*) FROM gold.DimShipper
UNION ALL
SELECT 'DimTerritory',                           COUNT(*) FROM gold.DimTerritory
UNION ALL
SELECT 'DimDate',                                COUNT(*) FROM gold.DimDate
UNION ALL
SELECT 'FactSales',                              COUNT(*) FROM gold.FactSales
UNION ALL
SELECT 'FactOrderFulfillment',                   COUNT(*) FROM gold.FactOrderFulfillment
UNION ALL
SELECT 'FactProductStock',                       COUNT(*) FROM gold.FactProductStock
UNION ALL
SELECT 'BridgeEmployeeTerritory',                COUNT(*) FROM gold.BridgeEmployeeTerritory
UNION ALL
SELECT 'DimOrderFlags',                          COUNT(*) FROM gold.DimOrderFlags
UNION ALL
SELECT 'DimCustomerSCD3',                        COUNT(*) FROM gold.DimCustomerSCD3
UNION ALL
SELECT 'FactEmployeeTerritoryActivity',          COUNT(*) FROM gold.FactEmployeeTerritoryActivity
ORDER BY Tabela;
"""


def split_batches(sql: str) -> list[str]:
    """Divide SQL em lotes separados por GO sozinho na linha."""
    batches = []
    current: list[str] = []
    for line in sql.split("\n"):
        if re.match(r"^\s*GO\s*$", line, re.IGNORECASE):
            if current:
                batches.append("\n".join(current))
                current = []
        else:
            current.append(line)
    if current:
        batches.append("\n".join(current))
    return batches


def batch_uses_database(batch: str) -> str | None:
    """Retorna o nome do banco se o lote é um `USE <db>`, senão None."""
    match = re.match(r"\s*USE\s+\[?(\w+)\]?\s*;?\s*$", batch.strip(), re.IGNORECASE)
    return match.group(1) if match else None


def plan_file(path: Path) -> tuple[list[str], list[str]]:
    """Lê e divide um arquivo, retornando (lotes, bancos citados em USE)."""
    sql = path.read_text(encoding="utf-8")
    batches = split_batches(sql)
    used_dbs = [db for b in batches if (db := batch_uses_database(b))]
    return batches, used_dbs


def dry_run() -> int:
    print("Plano de execução (--dry-run, sem conexão):\n")
    for name in BUILD_FILES:
        path = SQL_DIR / name
        batches, used_dbs = plan_file(path)
        use_info = f", USE: {', '.join(used_dbs)}" if used_dbs else ""
        print(f"  {name}: {len(batches)} lote(s){use_info}")

    print("\nSequência de EXEC (após construção):")
    for step in EXEC_SEQUENCE:
        print(f"  {step}")

    print("\nContagem de linhas por tabela ao final (query reaproveitada de run_pipeline.sql).")
    return 0


class PipelineError(Exception):
    pass


class Runner:
    def __init__(self, server: str, port: int, user: str, password: str):
        self.server = server
        self.port = port
        self.user = user
        self.password = password
        self._conn = None
        self._current_db = "master"

    def connect(self, database: str):
        import pymssql

        if self._conn is not None:
            self._conn.close()
        self._conn = pymssql.connect(
            server=self.server,
            port=self.port,
            user=self.user,
            password=self.password,
            database=database,
            autocommit=True,
        )
        self._current_db = database

    def close(self) -> None:
        if self._conn is not None:
            self._conn.close()
            self._conn = None

    def run_file(self, name: str) -> None:
        import pymssql

        path = SQL_DIR / name
        batches, _ = plan_file(path)
        if self._conn is None:
            self.connect(self._current_db)
        cursor = self._conn.cursor()

        for i, batch in enumerate(batches, 1):
            if not batch.strip():
                continue
            db = batch_uses_database(batch)
            if db is not None:
                if db.upper() != self._current_db.upper():
                    cursor.close()
                    self.connect(db)
                    cursor = self._conn.cursor()
                continue
            try:
                cursor.execute(batch)
                while cursor.nextset():
                    pass
            except pymssql.Error as e:
                cursor.close()
                raise PipelineError(f"{name}: lote {i}: {e}") from e

        cursor.close()

    def exec_procedure(self, name: str) -> None:
        import pymssql

        if self._conn is None:
            self.connect("NorthwindDW")
        cursor = self._conn.cursor()
        try:
            cursor.execute(f"EXEC {name}")
            while cursor.nextset():
                pass
        except pymssql.Error as e:
            cursor.close()
            raise PipelineError(f"EXEC {name}: {e}") from e
        cursor.close()

    def row_counts(self) -> list[tuple[str, int]]:
        if self._conn is None:
            self.connect("NorthwindDW")
        cursor = self._conn.cursor()
        cursor.execute(ROW_COUNT_QUERY)
        rows = cursor.fetchall()
        cursor.close()
        return rows


def run(server: str, port: int, user: str, password: str) -> int:
    runner = Runner(server, port, user, password)
    try:
        print(f"Conectando em {server}:{port}...")
        for name in BUILD_FILES:
            print(f"Construindo: {name}...", end=" ", flush=True)
            runner.run_file(name)
            print("OK")

        for step in EXEC_SEQUENCE:
            print(f"Executando: {step}...", end=" ", flush=True)
            if step.endswith(".sql"):
                runner.run_file(step)
            else:
                runner.exec_procedure(step)
            print("OK")

        print("\nContagem de linhas por tabela:")
        for table, count in runner.row_counts():
            print(f"  {table}: {count}")

    except PipelineError as e:
        print(f"\nERRO: {e}")
        return 1
    finally:
        runner.close()

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Executa o pipeline SQL do Northwind DW (construção + EXEC + contagem final)."
    )
    parser.add_argument("--server", default=None, help="Host do SQL Server (default: SQL_SERVER ou localhost)")
    parser.add_argument("--port", type=int, default=None, help="Porta (default: SQL_PORT ou 1434)")
    parser.add_argument("--user", default=None, help="Usuário (default: SQL_USER ou sa)")
    parser.add_argument("--password", default=None, help="Senha (default: SQL_PASSWORD ou YourPassword123)")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Lê e divide os arquivos, imprime o plano de execução, sem abrir conexão",
    )
    args = parser.parse_args()

    server = args.server or os.getenv("SQL_SERVER", "localhost")
    port = args.port or int(os.getenv("SQL_PORT", "1434"))
    user = args.user or os.getenv("SQL_USER", "sa")
    password = args.password or os.getenv("SQL_PASSWORD", "YourPassword123")

    if args.dry_run:
        print(f"Destino: {server}:{port}\n")
        return dry_run()

    return run(server, port, user, password)


if __name__ == "__main__":
    raise SystemExit(main())
