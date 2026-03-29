# =============================================================================
# Dockerfile — pf_northwind
# =============================================================================
#
# Container para execução dos notebooks Spark + Delta Lake e DuckDB.
# SQL Server roda em container separado (ver docker-compose.yml).
#
# Build (execute a partir da pasta pf_northwind/):
#   docker build -t pf-northwind -f docker/Dockerfile .
#
# Ou via docker compose:
#   docker compose -f docker/docker-compose.yml up -d
#
# =============================================================================

FROM python:3.11-slim

LABEL description="pf_northwind — Spark + Delta Lake + DuckDB"
LABEL version="1.0"

# Versões
ARG SPARK_VERSION=3.5.0
ARG HADOOP_VERSION=3

# Variáveis de ambiente
ENV SPARK_HOME=/opt/spark \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    PATH=$PATH:/opt/spark/bin:/opt/mssql-tools18/bin \
    PYTHONPATH=/opt/spark/python:$PYTHONPATH \
    PYSPARK_PYTHON=python3 \
    ACCEPT_EULA=Y

# =============================================================================
# Dependências do sistema
# =============================================================================
RUN apt-get update && apt-get install -y \
    openjdk-21-jre-headless \
    wget \
    curl \
    procps \
    gnupg2 \
    apt-transport-https \
    unixodbc \
    unixodbc-dev \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Microsoft SQL Server Tools (sqlcmd + ODBC Driver 18)
# Necessário para a implementação sql_server/ e conectividade pyodbc/pymssql.
# =============================================================================
RUN curl -sSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] \
        https://packages.microsoft.com/debian/12/prod bookworm main" \
        > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y \
        msodbcsql18 \
        mssql-tools18 \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Apache Spark
# =============================================================================
RUN wget -q https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz \
        || wget -q https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz \
    && tar -xzf spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz \
    && mv spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION} ${SPARK_HOME} \
    && rm spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz

# =============================================================================
# Delta Lake JARs — copiados para $SPARK_HOME/jars/ para evitar ClassNotFoundException
# em tempo de execução. O pacote delta-spark (Python) não inclui os JARs no classpath
# do Spark automaticamente; pré-instalá-los aqui elimina a necessidade de
# spark.jars.packages ou configure_spark_with_delta_pip nos notebooks.
# =============================================================================
ARG DELTA_VERSION=3.0.0
RUN wget -q -P ${SPARK_HOME}/jars \
    https://repo1.maven.org/maven2/io/delta/delta-spark_2.12/${DELTA_VERSION}/delta-spark_2.12-${DELTA_VERSION}.jar \
    https://repo1.maven.org/maven2/io/delta/delta-storage/${DELTA_VERSION}/delta-storage-${DELTA_VERSION}.jar

# =============================================================================
# Dependências Python
# =============================================================================
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# =============================================================================
# Diretório de trabalho (espelha o path usado em utils.py)
# =============================================================================
WORKDIR /workspace/pf_northwind

# =============================================================================
# Portas
# =============================================================================
EXPOSE 4040 8888

# =============================================================================
# Healthcheck
# =============================================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD python -c "import pyspark; import duckdb; print('OK')" || exit 1

# =============================================================================
# Inicia Jupyter Lab automaticamente
# =============================================================================
CMD ["jupyter", "lab", \
     "--ip=0.0.0.0", "--port=8888", \
     "--no-browser", "--allow-root", \
     "--NotebookApp.token=''", "--NotebookApp.password=''"]
