"""
Ejecuta un script HiveQL sentencia por sentencia y guarda la evidencia.

Uso:
    python scripts/ejecutar_hiveql.py sql/p01_ddl.sql [evidencias/p01_ddl.txt]

Usa Spark SQL con soporte Hive (metastore Derby local + warehouse en ./warehouse),
que acepta la misma sintaxis HiveQL (DDL Hive, SerDes, LOAD DATA, INSERT OVERWRITE,
funciones de ventana). En un cluster con Hive real los mismos .sql se ejecutan con:
    beeline -u jdbc:hive2://localhost:10000 -f sql/p01_ddl.sql
"""
import os
import sys
import time

from pyspark.sql import SparkSession

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def dividir_sentencias(texto):
    """Separa por ';' respetando comillas y comentarios '--'."""
    sentencias, actual, comilla = [], [], None
    i = 0
    while i < len(texto):
        c = texto[i]
        if comilla is None and texto.startswith("--", i):
            fin = texto.find("\n", i)
            fin = len(texto) if fin == -1 else fin
            actual.append(texto[i:fin])
            i = fin
            continue
        if c in ("'", '"', "`"):
            if comilla is None:
                comilla = c
            elif comilla == c and texto[i - 1] != "\\":
                comilla = None
        if c == ";" and comilla is None:
            sentencias.append("".join(actual))
            actual = []
        else:
            actual.append(c)
        i += 1
    sentencias.append("".join(actual))
    limpias = []
    for s in sentencias:
        sin_coment = "\n".join(l for l in s.splitlines() if not l.strip().startswith("--")).strip()
        if sin_coment:
            limpias.append(s.strip())
    return limpias


def main():
    script = sys.argv[1]
    salida = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        RAIZ, "evidencias", os.path.splitext(os.path.basename(script))[0] + ".txt")

    os.chdir(RAIZ)
    spark = (SparkSession.builder
             .appName("examen_superstore")
             .master("local[4]")
             .config("spark.sql.warehouse.dir", os.path.join(RAIZ, "warehouse"))
             .config("javax.jdo.option.ConnectionURL",
                     "jdbc:derby:;databaseName=" + os.path.join(RAIZ, "metastore_db") + ";create=true")
             .config("spark.sql.session.timeZone", "UTC")
             .config("spark.sql.legacy.timeParserPolicy", "LEGACY")
             .config("hive.exec.dynamic.partition", "true")
             .config("hive.exec.dynamic.partition.mode", "nonstrict")
             .enableHiveSupport()
             .getOrCreate())
    spark.sparkContext.setLogLevel("ERROR")

    with open(script, encoding="utf-8") as f:
        sentencias = dividir_sentencias(f.read())

    lineas = [
        "EVIDENCIA DE EJECUCION",
        "Script : " + os.path.relpath(script, RAIZ).replace("\\", "/"),
        "Motor  : Spark SQL %s con soporte Hive (HiveQL)" % spark.version,
        "Fecha  : " + time.strftime("%Y-%m-%d %H:%M:%S"),
        "=" * 100,
    ]
    for n, sql in enumerate(sentencias, 1):
        lineas.append("")
        lineas.append("-- [%d] %s" % (n, sql if len(sql) < 4000 else sql[:4000] + " ..."))
        inicio = time.time()
        df = spark.sql(sql)
        filas = df.collect()
        seg = time.time() - inicio
        if df.columns and filas:
            ancho = [len(c) for c in df.columns]
            datos = [["NULL" if v is None else str(v) for v in fila] for fila in filas]
            for fila in datos:
                ancho = [max(a, len(v)) for a, v in zip(ancho, fila)]
            sep = "+" + "+".join("-" * (a + 2) for a in ancho) + "+"
            lineas.append(sep)
            lineas.append("| " + " | ".join(c.ljust(a) for c, a in zip(df.columns, ancho)) + " |")
            lineas.append(sep)
            for fila in datos:
                lineas.append("| " + " | ".join(v.ljust(a) for v, a in zip(fila, ancho)) + " |")
            lineas.append(sep)
        lineas.append("OK - %d fila(s) - %.2f s" % (len(filas), seg))

    os.makedirs(os.path.dirname(salida), exist_ok=True)
    with open(salida, "w", encoding="utf-8") as f:
        f.write("\n".join(lineas) + "\n")
    print("\n".join(lineas))
    spark.stop()


if __name__ == "__main__":
    main()
