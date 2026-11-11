# tem1_2mom_Arevalo-Beltran-Anthony

Examen práctico individual – 2do momento (Universidad del Valle).
Procesamiento y análisis del dataset **Sample Superstore** con **Apache Hive (HiveQL)**.

## Descripción

En este proyecto trabajo con los datos de ventas de una tienda de EE. UU. (9 994 ventas entre 2014 y 2017). Primero cargo los datos en Hive, después reviso su calidad y corrijo los errores que encontré, y al final respondo preguntas de negocio con consultas HiveQL.

## Objetivos

- Crear las tablas en Hive con los tipos de datos correctos y cargar el dataset.
- Revisar la calidad de los datos y decidir qué hacer con los errores.
- Resolver las preguntas usando CTE y funciones de ventana (`LAG`, `RANK`, `DENSE_RANK`, `SUM() OVER`, `CUME_DIST`).
- Explicar qué significan los resultados para el negocio.

## Requisitos

| Componente | Versión usada | Uso |
|------------|---------------|-----|
| Docker Desktop | – | Levantar Hive 4.0.1 sin instalar nada más (opción recomendada) |
| Apache Hive / HiveServer2 + Beeline | 4.0.1 | Ejecución de los scripts `.sql` |
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
  ejecutar_hiveql.py               ejecuta un .sql con Spark y guarda la evidencia
  ejecutar_todo_docker.sh          ejecuta todos los .sql en Hive (Docker)
docker-compose.yml                 contenedor de Apache Hive 4.0.1
sql/                               scripts HiveQL (DDL, DML y una consulta por pregunta)
docs/                              diccionario de datos y documentación de cada pregunta
evidencias/                        salida de la ejecución de cada script
```

## Cómo ejecutarlo con Docker (recomendado)

Solo se necesita tener instalado [Docker Desktop](https://www.docker.com/products/docker-desktop/). No hace falta instalar Hive ni Java.

```bash
# 1. Descargar el repositorio
git clone https://github.com/Anthony22290/tem1_2mom_Arevalo-Beltran-Anthony.git
cd tem1_2mom_Arevalo-Beltran-Anthony

# 2. Levantar Hive (la primera vez descarga la imagen, tarda unos minutos)
docker compose up -d

# 3. Ejecutar todas las preguntas en orden
docker compose exec hive bash scripts/ejecutar_todo_docker.sh

# 4. Apagar Hive al terminar
docker compose down
```

El paso 3 espera a que Hive termine de arrancar, ejecuta los scripts de `sql/` uno por uno y guarda la salida de cada uno en `evidencias/hive/`.

También se pueden hacer consultas a mano entrando a Beeline:

```bash
docker compose exec hive beeline -u jdbc:hive2://localhost:10000/
# luego, por ejemplo:
# USE superstore_db;
# SELECT region, SUM(sales) FROM superstore GROUP BY region;
```

Los archivos de `csv/preparado/` ya están en el repositorio, así que no es necesario correr `scripts/preparar_datos.sh`.

## Procedimiento de ejecución (sin Docker)

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

Los scripts se ejecutan en orden: primero `p01_ddl`, después `p01_carga` y luego los demás. Las preguntas 4 y 5 crean tablas de apoyo (`rfm_clientes`, `producto_metricas`, `producto_ranking`) y la 6 crea la vista `superstore_rango_desc`.

## Modelo de datos

Base `superstore_db`:

| Objeto | Tipo | Descripción |
|--------|------|-------------|
| `superstore_raw` | tabla TEXTFILE (OpenCSVSerde) | CSV original sin transformar, todo STRING |
| `superstore_ref` | tabla TEXTFILE (OpenCSVSerde) | Copia de referencia para restaurar decimales |
| `superstore` | tabla **ORC + SNAPPY**, particionada por `order_year` | Tabla analítica tipada y corregida |
| `superstore_raw_v`, `superstore_ref_v` | vistas | Capas de texto sin la fila de cabecera |

Diccionario completo: [`docs/diccionario_datos.md`](docs/diccionario_datos.md)

> **Algo importante:** el CSV del examen venía sin el punto decimal en `Sales`, `Discount` y `Profit` (por ejemplo, `261.96` aparecía como `26196` y `0.45` como `45`). Lo corregí al cargar los datos y comprobé las 9 994 filas. Lo explico en [`docs/p01_modelo_datos.md`](docs/p01_modelo_datos.md).

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

- En total se vendieron **2 297 200.86 USD** y se ganaron **286 397.02 USD** (12.5 % de margen), en 5 009 órdenes de 793 clientes.
- **West** es la mejor región (genera casi el 38 % de la ganancia) y **Central** la peor (solo 7.9 % de margen).
- Los clientes **en riesgo de abandono** son el 16 % del total, pero hacen el 24 % de las ventas y son el grupo que más ganancia dejó.
- **Furniture** gana muy poco (2.5 % de margen) y 1 de cada 3 de sus productos pierde dinero.
- Todas las ventas con **más del 50 % de descuento** pierden dinero, y desde el **30 %** de descuento el margen ya es negativo.

## Uso de herramientas

Para el desarrollo se usó un asistente de IA (Claude) como apoyo, según la política del docente. El código y los análisis fueron revisados por el estudiante.

