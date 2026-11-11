# Pregunta 1. Diseño e implementación del modelo de datos

## Enunciado

Construya el modelo de almacenamiento en Apache Hive para el dataset proporcionado: identificar todos los campos, elaborar un diccionario de datos (nombre, tipo Hive, descripción y restricciones), crear una tabla analítica con tipos apropiados y documentar el procedimiento de carga.

**Entregables:** diccionario de datos, DDL, instrucciones de carga y evidencia de registros importados.

## Estrategia de solución

1. **Inspección del archivo** antes de la ingesta: separador, codificación, fin de línea, cabecera, formatos de fecha y números.
2. **Modelo en capas** dentro de la base `superstore_db`:

| Tabla | Formato | Propósito |
|-------|---------|-----------|
| `superstore_raw` | TEXTFILE + OpenCSVSerde (`;`) | Copia exacta del CSV, todo `STRING`. Nada se pierde y sirve para la auditoría (P2). |
| `superstore_ref` | TEXTFILE + OpenCSVSerde (`,`) | Copia pública del mismo dataset, solo para recuperar la posición del punto decimal. |
| `superstore` | **ORC + SNAPPY**, particionada por `order_year` | Tabla analítica tipada y corregida que usan todas las preguntas. |

3. **Transformación** `superstore_raw → superstore` con `INSERT OVERWRITE ... PARTITION (order_year)` (partición dinámica), conversión de tipos y correcciones.
4. **Validación** de la carga con conteos, nulos y controles cruzados.

### Hallazgo principal: el CSV perdió el separador decimal

Al inspeccionar el archivo se ve que `Sales`, `Discount` y `Profit` no tienen punto decimal:

| row_id | sales_csv | valor real | discount_csv | valor real | profit_csv | valor real |
|---|---|---|---|---|---|---|
| 1 | 26196 | 261.96 | 0 | 0 | 419136 | 41.9136 |
| 4 | 9575775 | 957.5775 | 45 | 0.45 | -383031 | -383.031 |
| 5 | 22368 | 22.368 | 2 | 0.2 | 25164 | 2.5164 |

Si se cargaran tal cual, las ventas totales serían cientos de veces mayores y los descuentos superarían el 100 %.

- **Discount** se puede reconstruir sin ayuda externa: todos los descuentos son menores a 1, entonces el valor real es `0.` + dígitos (`2 → 0.2`, `45 → 0.45`).
- **Sales y Profit** no se pueden reconstruir solo con el CSV, porque la posición del punto es variable (de 0 a 4 decimales). Se usó una copia pública del mismo dataset (`csv/referencia/superstore_referencia.csv`, publicada en GitHub por `leonism/sample-superstore`) **solo para saber dónde va el punto**. El valor se acepta únicamente si sus dígitos, sin punto ni ceros a la izquierda, son **idénticos** a los del CSV del examen; si no, quedaría `NULL`. Se cruza por `row_id` y `product_id`.
- Las demás columnas (fechas, IDs, nombres, regiones, etc.) **se toman siempre del CSV del examen**. La copia de referencia es una versión posterior con los años desplazados (+1) y 10 800 filas, por eso no se usa para nada más.

## Consultas HiveQL desarrolladas

- DDL: [`sql/p01_ddl.sql`](../sql/p01_ddl.sql)
- Carga y validación: [`sql/p01_carga.sql`](../sql/p01_carga.sql)

Fragmento central de la carga:

```sql
INSERT OVERWRITE TABLE superstore PARTITION (order_year)
SELECT ..., YEAR(order_date) AS order_year
FROM (
    SELECT
        CAST(r.row_id AS INT)                                            AS row_id,
        TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(r.order_date, 'M/d/yyyy'))) AS order_date,
        LPAD(TRIM(r.postal_code), 5, '0')                                AS postal_code,
        CASE WHEN REGEXP_REPLACE(REGEXP_REPLACE(f.sales, '[.]', ''), '^(-?)0+(?=[0-9])', '$1') = r.sales
             THEN CAST(f.sales AS DECIMAL(12,4)) END                      AS sales,
        CAST(CASE WHEN r.discount = '0' THEN '0'
                  ELSE CONCAT('0.', r.discount) END AS DECIMAL(4,2))      AS discount,
        ...
    FROM superstore_raw_v r
    LEFT JOIN superstore_ref_v f
           ON CAST(r.row_id AS INT) = CAST(f.row_id AS INT)
          AND TRIM(r.product_id) = TRIM(f.product_id)
) t;
```

## Procedimiento de carga

Desde la raíz del repositorio:

```bash
# 1. Preparar archivos: Windows-1252 -> UTF-8 y CRLF -> LF (no cambia valores)
bash scripts/preparar_datos.sh

# 2. Crear base, tablas y vistas
beeline -u jdbc:hive2://localhost:10000 -f sql/p01_ddl.sql

# 3. Cargar y transformar
beeline -u jdbc:hive2://localhost:10000 -f sql/p01_carga.sql
```

`LOAD DATA LOCAL INPATH` usa rutas relativas (`csv/preparado/...`), por eso se ejecuta desde la raíz. Si HiveServer2 corre en otra máquina o contenedor, primero se copian los archivos a HDFS (`hdfs dfs -put csv/preparado /user/hive/superstore/`) y se usa `LOAD DATA INPATH` sin `LOCAL`.

Las evidencias de este repositorio se generaron con `python scripts/ejecutar_hiveql.py <script.sql>`, que ejecuta el mismo HiveQL sobre Spark SQL con soporte Hive (metastore local).

## Evidencia de ejecución

- [`evidencias/p01_ddl.txt`](../evidencias/p01_ddl.txt): creación de tablas y `DESCRIBE superstore`.
- [`evidencias/p01_carga.txt`](../evidencias/p01_carga.txt): carga, particiones y validaciones.

## Resultado obtenido

| Control | Resultado |
|---------|-----------|
| Registros en `superstore_raw_v` | 9 994 |
| Registros en `superstore` | 9 994 |
| Particiones | 2014 (1 993), 2015 (2 102), 2016 (2 587), 2017 (3 312) |
| `sales` / `profit` no recuperados (NULL) | 0 / 0 |
| Descuentos distintos a la referencia | 0 |
| Fechas nulas tras la conversión | 0 |
| Ventas totales | 2 297 200.86 USD |
| Ganancia total | 286 397.02 USD |
| Unidades vendidas | 37 873 |

Registros de muestra ya corregidos (incluye un nombre con `;` y un código postal con cero inicial):

| row_id | order_date | postal_code | product_name | sales | discount | profit |
|---|---|---|---|---|---|---|
| 1 | 2016-11-08 | 42420 | Bush Somerset Collection Bookcase | 261.96 | 0.00 | 41.9136 |
| 4 | 2015-10-11 | 33311 | Bretford CR4500 Series Slim Rectangular Table | 957.5775 | 0.45 | −383.031 |
| 182 | 2014-12-05 | 62521 | Imation Secure+ Hardware Encrypted USB 2.0 Flash Drive; 16GB | 408.744 | 0.20 | 76.6395 |
| 2235 | 2017-12-05 | 05408 | Logitech ClearChat Comfort/USB Headset H390 | 205.03 | 0.00 | 67.6599 |

## Interpretación técnica

Revisar el archivo antes de cargarlo fue clave: el CSV parecía correcto (21 columnas, sin vacíos), pero los montos estaban multiplicados por potencias de 10 distintas en cada fila. Con un `CAST` directo a número Hive no habría dado error, y todos los análisis posteriores habrían salido mal sin que nadie lo notara.

Separar una capa cruda de una analítica permite auditar el dato original (P2) sin perderlo y aplicar las correcciones en un solo lugar. La regla de recuperación de decimales es conservadora: solo acepta el valor si los dígitos coinciden exactamente, y la validación confirmó que coinciden en las 9 994 filas. Además, los totales obtenidos (2.297 M en ventas y 286 mil en ganancia) son los conocidos de este dataset.

ORC con SNAPPY y la partición por año dejan la tabla lista para consultas analíticas: se leen solo las columnas usadas y, cuando se filtra por año, solo la partición necesaria.

## Conclusión

El modelo queda implementado en `superstore_db.superstore` con 9 994 registros, tipos adecuados (DATE, DECIMAL, INT, STRING) y las inconsistencias de formato corregidas y verificadas. Esta tabla es la base para todas las preguntas siguientes.
