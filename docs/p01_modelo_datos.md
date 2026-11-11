# Pregunta 1. Diseño e implementación del modelo de datos

## Enunciado

Construya el modelo de almacenamiento en Apache Hive para el dataset proporcionado: identificar todos los campos, elaborar un diccionario de datos (nombre, tipo Hive, descripción y restricciones), crear una tabla analítica con tipos apropiados y documentar el procedimiento de carga.

**Entregables:** diccionario de datos, DDL, instrucciones de carga y evidencia de registros importados.

## Estrategia de solución

Antes de crear las tablas abrí el CSV para ver cómo venía. Encontré varias cosas a tener en cuenta:

- Las columnas están separadas por `;` y no por coma.
- Tiene 21 columnas y 9 994 registros, más la fila de títulos.
- Las fechas vienen como texto en formato mes/día/año (`11/8/2016`).
- Algunos nombres tienen acentos que no se leen bien porque el archivo no está en UTF-8.
- **Los números no tienen punto decimal.** Este fue el problema más grande y lo explico abajo.

Con eso decidí trabajar con tres tablas dentro de la base de datos `superstore_db`:

| Tabla | Para qué la uso |
|-------|-----------------|
| `superstore_raw` | Guarda el CSV tal cual, con todas las columnas como texto (`STRING`). Así no pierdo nada y puedo revisar el dato original en la Pregunta 2. |
| `superstore_ref` | Una copia pública del mismo dataset que sí tiene los decimales. Solo la uso para saber dónde va el punto. |
| `superstore` | La tabla final, con los tipos correctos (fechas, números, texto). Es la que uso en todas las demás preguntas. |

La tabla final la guardé en formato **ORC**, que comprime los datos y es más rápido para consultas. También la dividí en **particiones por año** (`order_year`), para que cuando filtre por año Hive solo lea esa parte de los datos.

### El problema de los decimales

Al revisar el archivo me di cuenta de que los montos estaban raros. Por ejemplo, en la primera fila la venta decía `26196`, pero el valor real es `261.96`. Pasaba lo mismo con el descuento y la ganancia:

| row_id | sales en el CSV | valor real | discount en el CSV | valor real | profit en el CSV | valor real |
|---|---|---|---|---|---|---|
| 1 | 26196 | 261.96 | 0 | 0 | 419136 | 41.9136 |
| 4 | 9575775 | 957.5775 | 45 | 0.45 | -383031 | -383.031 |
| 5 | 22368 | 22.368 | 2 | 0.2 | 25164 | 2.5164 |

Si cargaba los datos así, todos los totales iban a salir mal, y Hive no iba a dar ningún error que me avisara. Lo resolví así:

- **Descuento:** como todos los descuentos son menores a 1, basta con poner `0.` adelante (`45` → `0.45`, `2` → `0.2`).
- **Ventas y ganancia:** aquí no se puede adivinar dónde va el punto, porque algunos valores tienen 2 decimales y otros 3 o 4. Busqué una copia pública del mismo dataset (`csv/referencia/superstore_referencia.csv`) y la usé solo para ver la posición del punto. Para estar seguro, solo acepto el valor si los números son **exactamente los mismos** que en mi CSV; si no coinciden, queda vacío (`NULL`).
- Todas las demás columnas (fechas, clientes, productos, regiones…) las saco siempre de mi CSV original.

También corregí los códigos postales que perdieron el 0 inicial (`5408` → `05408`).

## Consultas HiveQL desarrolladas

- Creación de tablas: [`sql/p01_ddl.sql`](../sql/p01_ddl.sql)
- Carga y validación: [`sql/p01_carga.sql`](../sql/p01_carga.sql)

La parte más importante es el `INSERT` que pasa los datos de la tabla cruda a la tabla final, convirtiendo cada columna a su tipo:

```sql
INSERT OVERWRITE TABLE superstore PARTITION (order_year)
SELECT ..., YEAR(order_date) AS order_year
FROM (
    SELECT
        CAST(r.row_id AS INT)                                            AS row_id,
        -- convierto el texto '11/8/2016' a fecha
        TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(r.order_date, 'M/d/yyyy'))) AS order_date,
        -- relleno con ceros a la izquierda hasta 5 digitos
        LPAD(TRIM(r.postal_code), 5, '0')                                AS postal_code,
        -- tomo la venta de la referencia solo si los digitos son iguales
        CASE WHEN REGEXP_REPLACE(REGEXP_REPLACE(f.sales, '[.]', ''), '^(-?)0+(?=[0-9])', '$1') = r.sales
             THEN CAST(f.sales AS DECIMAL(12,4)) END                      AS sales,
        -- al descuento le agrego '0.' adelante
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

Todo se ejecuta desde la carpeta principal del repositorio:

```bash
# 1. Paso el CSV a UTF-8 y quito los saltos de línea de Windows
bash scripts/preparar_datos.sh

# 2. Creo la base de datos y las tablas
beeline -u jdbc:hive2://localhost:10000 -f sql/p01_ddl.sql

# 3. Cargo los datos y los paso a la tabla final
beeline -u jdbc:hive2://localhost:10000 -f sql/p01_carga.sql
```

El paso 1 es necesario porque el archivo venía con codificación de Windows (por eso se veían mal los acentos) y con un salto de línea que dejaba un carácter extraño al final de la columna `Profit`. No cambia ningún valor.

Si Hive está en otra máquina, primero hay que subir los archivos a HDFS (`hdfs dfs -put csv/preparado /user/hive/superstore/`) y usar `LOAD DATA INPATH` sin la palabra `LOCAL`.

Para generar las evidencias usé `python scripts/ejecutar_hiveql.py <archivo.sql>`, que ejecuta el mismo código HiveQL con Spark SQL en modo compatible con Hive.

## Evidencia de ejecución

- [`evidencias/p01_ddl.txt`](../evidencias/p01_ddl.txt): creación de las tablas y estructura de `superstore`.
- [`evidencias/p01_carga.txt`](../evidencias/p01_carga.txt): carga de los datos y revisiones.

## Resultado obtenido

Después de cargar hice varias revisiones para comprobar que todo quedó bien:

| Revisión | Resultado |
|----------|-----------|
| Registros en el CSV | 9 994 |
| Registros en la tabla final | 9 994 |
| Registros por año | 2014: 1 993 · 2015: 2 102 · 2016: 2 587 · 2017: 3 312 |
| Ventas o ganancias que no se pudieron recuperar | 0 |
| Descuentos diferentes a la referencia | 0 |
| Fechas que no se pudieron convertir | 0 |
| Ventas totales | 2 297 200.86 USD |
| Ganancia total | 286 397.02 USD |
| Unidades vendidas | 37 873 |

Algunos registros ya corregidos:

| row_id | order_date | postal_code | product_name | sales | discount | profit |
|---|---|---|---|---|---|---|
| 1 | 2016-11-08 | 42420 | Bush Somerset Collection Bookcase | 261.96 | 0.00 | 41.9136 |
| 4 | 2015-10-11 | 33311 | Bretford CR4500 Series Slim Rectangular Table | 957.5775 | 0.45 | −383.031 |
| 182 | 2014-12-05 | 62521 | Imation Secure+ Hardware Encrypted USB 2.0 Flash Drive; 16GB | 408.744 | 0.20 | 76.6395 |
| 2235 | 2017-12-05 | 05408 | Logitech ClearChat Comfort/USB Headset H390 | 205.03 | 0.00 | 67.6599 |

## Interpretación técnica

Lo que más aprendí en esta pregunta es que hay que revisar el archivo antes de cargarlo. A simple vista el CSV parecía estar bien (tenía todas las columnas y ningún vacío), pero los montos estaban mal. Si no me hubiera dado cuenta, todos los resultados de las demás preguntas habrían salido mal.

Tener una tabla cruda y otra final me ayudó a separar el dato original del dato corregido. Así puedo revisar el original sin modificarlo y hacer todas las correcciones en un solo lugar. Las revisiones muestran que las 9 994 filas se recuperaron bien, y los totales coinciden con los que se conocen de este dataset.

Usé `DECIMAL` para los montos en vez de `DOUBLE` porque `DOUBLE` puede dar pequeños errores de redondeo al sumar muchos valores. El código postal lo dejé como texto porque es un código, no un número para hacer cálculos.

## Conclusión

La tabla `superstore_db.superstore` quedó con los 9 994 registros, los tipos de datos correctos y los errores del archivo corregidos y revisados. Esta es la tabla que uso en el resto del examen.
