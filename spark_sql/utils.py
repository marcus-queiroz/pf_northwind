"""
spark/utils.py — Utilitários compartilhados para os notebooks NorthwindDW.

Centraliza a criação do SparkSession e o registro do catálogo Delta,
eliminando a duplicação presente nos notebooks 02–09.
"""
import logging
import os
from pyspark.sql import SparkSession

BASE_DIR      = "/workspace/pf_northwind/spark_sql"
WAREHOUSE_DIR = f"{BASE_DIR}/warehouse"
METASTORE_DIR = f"{BASE_DIR}/metastore_db"
DATA_DIR      = f"{BASE_DIR}/data"


def get_spark(app_name: str = "NorthwindDW") -> SparkSession:
    """SparkSession configurada com Delta Lake e metastore Derby persistente."""
    spark = (
        SparkSession.builder
        .appName(app_name)
        .master("local[*]")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config("spark.sql.catalog.spark_catalog",
                "org.apache.spark.sql.delta.catalog.DeltaCatalog")
        .config("spark.sql.warehouse.dir", WAREHOUSE_DIR)
        # Metastore Derby persistente — compartilhado entre todos os notebooks
        .config("spark.hadoop.javax.jdo.option.ConnectionURL",
                f"jdbc:derby:;databaseName={METASTORE_DIR};create=true")
        .config("spark.hadoop.javax.jdo.option.ConnectionDriverName",
                "org.apache.derby.jdbc.EmbeddedDriver")
        .config("spark.sql.shuffle.partitions", "4")
        .config("spark.ui.showConsoleProgress", "false")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("ERROR")
    logging.getLogger("py4j").setLevel(logging.ERROR)
    return spark


def register_catalog(spark: SparkSession) -> None:
    """Re-registra tabelas Delta no catálogo in-memory do Derby.

    Derby é in-memory: o catálogo some a cada reinício de sessão, mesmo que
    os arquivos Delta existam no disco. Sem essa chamada, spark.table("bronze.customers")
    falha com 'table not found'.
    """
    for db in ["bronze", "silver", "gold"]:
        spark.sql(f"CREATE DATABASE IF NOT EXISTS {db}")
        db_path = f"{WAREHOUSE_DIR}/{db}.db"
        if not os.path.exists(db_path):
            continue
        for tbl in sorted(os.listdir(db_path)):
            tbl_path = f"{db_path}/{tbl}"
            if os.path.isdir(tbl_path) and os.path.exists(f"{tbl_path}/_delta_log"):
                spark.sql(f"""
                    CREATE TABLE IF NOT EXISTS {db}.{tbl}
                    USING DELTA LOCATION '{tbl_path}'
                """)
    print("Catálogo registrado:", {db: len(spark.catalog.listTables(db))
          for db in ["bronze", "silver", "gold"]})
