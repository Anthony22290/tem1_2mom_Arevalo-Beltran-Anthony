# tem1_2mom_Arevalo_Anthony

Examen práctico individual – 2do momento (Universidad del Valle).
Procesamiento y análisis del dataset **Sample Superstore** con **Apache Hive (HiveQL)**.

## Descripción

Proyecto de ingeniería y análisis de datos sobre las ventas de una cadena minorista de EE. UU. (9 994 líneas de pedido, 2014–2017). Se diseña un modelo de almacenamiento en Hive, se audita y corrige la calidad del archivo fuente y se resuelven consultas analíticas con CTE y funciones de ventana para apoyar la toma de decisiones.

## Objetivos

- Modelar e ingerir el dataset en Hive con tipos de datos apropiados.
- Auditar la calidad e integridad del archivo y definir criterios de tratamiento.
- Resolver consultas analíticas avanzadas (CTE, `LAG`, `RANK`, `DENSE_RANK`, `SUM() OVER`, `CUME_DIST`).
- Interpretar los resultados y obtener conclusiones de negocio.

## Requisitos

| Componente | Versión usada | Uso |
|------------|---------------|-----|
| Apache Hive / HiveServer2 + Beeline | 3.x | Ejecución de los scripts `.sql` en un clúster |
| Java | 17 o superior | Requerido por Hive / Spark |
| Python + PySpark | 3.12 / 3.5.3 | Ejecución local con metastore Hive (`scripts/ejecutar_hiveql.py`), generó las evidencias |
| `iconv`, `sed` | – | Preparación del CSV (`scripts/preparar_datos.sh`) |

## Estructura del repositorio

```
csv/
  Sample - Superstore.csv          dataset original del examen (separador ;)
  referencia/                      copia pública del dataset (solo para recuperar decimales)
  preparado/                       archivos en UTF-8 listos para LOAD DATA
scripts/
  preparar_datos.sh                Windows-1252 -> UTF-8, CRLF -> LF
  ejecutar_hiveql.py               ejecuta un .sql y guarda la evidencia
sql/                               scripts HiveQL (DDL, DML y una consulta por pregunta)
docs/                              diccionario de datos y documentación de cada pregunta
evidencias/                        salida de la ejecución de cada script
```

## Procedimiento de ejecución

Desde la raíz del repositorio:

```bash
# 1. Preparar los archivos
bash scripts/preparar_datos.sh

# 2a. En un clúster Hive
beeline -u jdbc:hive2://localhost:10000 -f sql/p01_ddl.sql
beeline -u jdbc:hive2://localhost:10000 -f sql/p01_carga.sql
beeline -u jdbc:hive2://localhost:10000 -f sql/p02_calidad.sql
# ... resto de scripts en orden

# 2b. En local (genera la evidencia en evidencias/)
pip install pyspark==3.5.3
for f in sql/p0*.sql; do python scripts/ejecutar_hiveql.py "$f"; done
```

Los scripts deben ejecutarse en orden: `p01_ddl` → `p01_carga` → resto. Las preguntas 4 y 5 crean tablas auxiliares (`rfm_clientes`, `producto_metricas`, `producto_ranking`) y la 6 crea la vista `superstore_rango_desc`.

## Modelo de datos

Base `superstore_db`:

| Objeto | Tipo | Descripción |
|--------|------|-------------|
| `superstore_raw` | tabla TEXTFILE (OpenCSVSerde) | CSV original sin transformar, todo STRING |
| `superstore_ref` | tabla TEXTFILE (OpenCSVSerde) | Copia de referencia para restaurar decimales |
| `superstore` | tabla **ORC + SNAPPY**, particionada por `order_year` | Tabla analítica tipada y corregida |
| `superstore_raw_v`, `superstore_ref_v` | vistas | Capas de texto sin la fila de cabecera |

Diccionario completo: [`docs/diccionario_datos.md`](docs/diccionario_datos.md)

> **Hallazgo importante:** el CSV del examen perdió el separador decimal en `Sales`, `Discount` y `Profit` (ej. `261.96` → `26196`, `0.45` → `45`). Se corrigió en la carga y se validaron las 9 994 filas. Detalle en [`docs/p01_modelo_datos.md`](docs/p01_modelo_datos.md).

## Preguntas resueltas

| # | Tema | Script | Documentación | Evidencia |
|---|------|--------|---------------|-----------|
| 1 | Modelo de datos y carga | [`p01_ddl.sql`](sql/p01_ddl.sql), [`p01_carga.sql`](sql/p01_carga.sql) | [doc](docs/p01_modelo_datos.md) | [ddl](evidencias/p01_ddl.txt), [carga](evidencias/p01_carga.txt) |
| 2 | Auditoría de calidad | [`p02_calidad.sql`](sql/p02_calidad.sql) | [doc](docs/p02_calidad_datos.md) | [txt](evidencias/p02_calidad.txt) |
| 3 | Evolución por región | [`p03_evolucion_region.sql`](sql/p03_evolucion_region.sql) | [doc](docs/p03_evolucion_region.md) | [txt](evidencias/p03_evolucion_region.txt) |
| 4 | Segmentación RFM | [`p04_rfm.sql`](sql/p04_rfm.sql) | [doc](docs/p04_rfm.md) | [txt](evidencias/p04_rfm.txt) |
| 5 | Ranking de productos | [`p05_ranking_productos.sql`](sql/p05_ranking_productos.sql) | [doc](docs/p05_ranking_productos.md) | [txt](evidencias/p05_ranking_productos.txt), [csv](evidencias/p05_ranking_completo.csv) |
| 6 | Impacto de los descuentos | [`p06_impacto_descuentos.sql`](sql/p06_impacto_descuentos.sql) | [doc](docs/p06_impacto_descuentos.md) | [txt](evidencias/p06_impacto_descuentos.txt) |

## Resultados principales (preguntas 1 a 6)

- Ventas totales de **2 297 200.86 USD** y ganancia de **286 397.02 USD** (margen 12.5 %) en 5 009 órdenes de 793 clientes.
- **West** es la región de mejor desempeño (37.9 % de la ganancia); **Central** la peor (margen 7.9 %).
- Los clientes **en riesgo de abandono** (16 %) concentran el 24 % de las ventas y la mayor ganancia de todos los segmentos RFM.
- **Furniture** tiene un margen de solo 2.5 % y el 32 % de sus productos pierde dinero.
- Todas las líneas con **descuento mayor al 50 %** pierden dinero; el margen se vuelve negativo a partir del **30 %** de descuento.

## Uso de herramientas

Para el desarrollo se usó un asistente de IA (Claude) como apoyo, según la política del docente. El código y los análisis fueron revisados por el estudiante.
