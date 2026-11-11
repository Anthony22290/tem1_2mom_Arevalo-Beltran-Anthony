# Pregunta 2. Auditoría de calidad e integridad de datos

## Enunciado

Realice un análisis de calidad sobre el dataset. Determine: cantidad total de registros, identificadores de fila duplicados, órdenes y clientes únicos, campos con NULL, fechas inválidas o inconsistentes, ventas iguales o inferiores a cero, descuentos fuera del intervalo esperado y registros con fecha de envío anterior a la fecha de pedido. Construya una consulta que entregue un resumen de calidad y proponga criterios de tratamiento.

## Estrategia de solución

La mayoría de las revisiones las hice sobre la **tabla cruda** (`superstore_raw_v`), porque ahí están los datos tal como vinieron en el CSV. Algunas las repetí en la **tabla final** (`superstore`) para comprobar que la carga corrigió los problemas.

Lo que revisé y cómo:

- **Duplicados:** comparé el total de filas con la cantidad de `row_id` distintos (`COUNT(*) - COUNT(DISTINCT row_id)`). También busqué filas que fueran iguales en todo menos en el `row_id`.
- **Valores vacíos:** como en la tabla cruda todo es texto, un dato faltante puede aparecer como `NULL` o como texto vacío `''`. Conté los dos casos en cada columna. Para mostrar el resultado como una lista usé `STACK()`, que convierte columnas en filas.
- **Fechas:** convertí el texto a fecha. Si no se puede convertir, es inválida. También volví a pasar la fecha a texto y la comparé con la original, porque Hive acepta fechas que no existen (como `2/30/2016`) y las cambia solo, sin avisar.
- **Rangos:** ventas en cero o negativas, descuentos fuera de 0 a 1 y envíos con fecha anterior al pedido.
- **Coherencia:** que cada producto tenga un solo nombre, que cada cliente tenga un solo nombre y segmento, y que cada orden tenga una sola fecha y un solo cliente.
- **Resumen:** junté todas las revisiones en una sola consulta con `WITH` y `UNION ALL`, donde cada fila es una revisión con su resultado.

## Consulta HiveQL desarrollada

Script completo: [`sql/p02_calidad.sql`](../sql/p02_calidad.sql). Esta es la consulta del resumen (resumida):

```sql
WITH raw AS (
    SELECT row_id, order_id, customer_id, product_id, postal_code,
           UNIX_TIMESTAMP(order_date, 'M/d/yyyy') AS ts_order,
           UNIX_TIMESTAMP(ship_date,  'M/d/yyyy') AS ts_ship,
           order_date, ship_date, sales, discount, profit, product_name
    FROM superstore_raw_v
),
total AS (SELECT COUNT(*) AS n FROM raw),
controles AS (
    SELECT '01 Total de registros' AS control, COUNT(*) AS valor, 'informativo' AS tipo FROM raw
    UNION ALL
    SELECT '02 Row ID duplicados', COUNT(*) - COUNT(DISTINCT row_id), 'error' FROM raw
    UNION ALL
    SELECT '06 Fechas invalidas o no convertibles',
           SUM(IF(ts_order IS NULL OR ts_ship IS NULL
               OR FROM_UNIXTIME(ts_order, 'M/d/yyyy') <> order_date
               OR FROM_UNIXTIME(ts_ship,  'M/d/yyyy') <> ship_date, 1, 0)), 'error' FROM raw
    UNION ALL
    SELECT '07 Envio anterior al pedido', SUM(IF(ts_ship < ts_order, 1, 0)), 'error' FROM raw
    UNION ALL
    SELECT '09 Descuento fuera de [0,1] en CSV original',
           SUM(IF(CAST(discount AS DECIMAL(18,4)) NOT BETWEEN 0 AND 1, 1, 0)), 'error de formato' FROM raw
    -- ... (14 revisiones en total)
)
SELECT c.control, c.valor, ROUND(c.valor * 100.0 / t.n, 2) AS pct_sobre_total, c.tipo
FROM controles c CROSS JOIN total t
ORDER BY c.control;
```

## Evidencia de ejecución

[`evidencias/p02_calidad.txt`](../evidencias/p02_calidad.txt)

## Resultado obtenido

### Resumen de calidad

| Revisión | Valor | % del total | Tipo |
|----------|------:|------------:|------|
| 01 Total de registros | 9 994 | 100.00 | informativo |
| 02 Row ID duplicados | 0 | 0.00 | error |
| 03 Órdenes únicas | 5 009 | – | informativo |
| 04 Clientes únicos | 793 | – | informativo |
| 05 Registros con algún campo vacío | 0 | 0.00 | error |
| 06 Fechas inválidas | 0 | 0.00 | error |
| 07 Envío antes del pedido | 0 | 0.00 | error |
| 07b Año del `order_id` distinto al de la fecha | 7 | 0.07 | advertencia |
| 08 Ventas ≤ 0 | 0 | 0.00 | error |
| 09 Descuento fuera de 0–1 en el CSV original | 5 102 | 51.05 | error de formato |
| 10 Montos sin punto decimal | 9 866 | 98.72 | error de formato |
| 11 Código postal con menos de 5 dígitos | 449 | 4.49 | error de formato |
| 12 Nombre de producto con `;` | 6 | 0.06 | advertencia |
| 13 Descuento fuera de 0–1 en la tabla final | 0 | 0.00 | error |
| 14 Registros con pérdida (`profit < 0`) | 1 871 | 18.72 | informativo |

### Otros detalles que encontré

- Ninguna de las 21 columnas tiene valores vacíos.
- Hay **un par de filas idénticas** (3406 y 3407): misma orden, mismo producto, misma cantidad y misma venta. Solo cambia el `row_id`.
- Hay **7 líneas** (de 5 órdenes) con fecha `12/31/2016` cuyo código dice `2017`. Parece que el código se generó con la fecha de envío, que ya era 2017.
- Los días de entrega tienen sentido según el tipo de envío: Same Day de 0 a 1 días, First Class de 1 a 4, Second Class de 1 a 5 y Standard Class de 3 a 7.
- En el CSV original el descuento más alto era **45**, cuando el máximo real es 0.80. Esto confirma el problema de los decimales.
- **32 productos** tienen el mismo código pero dos nombres diferentes. Por ejemplo, `FUR-BO-10002213` aparece como “Sauder Forest Hills Library…” y también como “DMI Eclipse Executive Suite Bookcases”.
- Los 449 códigos postales cortos son de estados del noreste de EE. UU. (New Jersey, Maine, Massachusetts, etc.), donde los códigos empiezan con 0.
- Hay 922 registros con descuento de 50 % o más. No es un error, pero son muchos.

## Criterios de tratamiento propuestos

| Problema | Qué hice o qué propongo | Dónde |
|----------|-------------------------|-------|
| Ventas y ganancias sin punto decimal | Recuperar el punto con la copia de referencia solo si los números coinciden exactamente | `sql/p01_carga.sql` |
| Descuento sin punto decimal | Agregar `0.` adelante y comparar con la referencia | `sql/p01_carga.sql` |
| Código postal sin el 0 inicial | Completar con ceros a la izquierda (`LPAD`) | `sql/p01_carga.sql` |
| `;` dentro del nombre del producto | Leer el CSV con `OpenCSVSerde`, que respeta las comillas | `sql/p01_ddl.sql` |
| Acentos y saltos de línea de Windows | Convertir el archivo a UTF-8 antes de cargarlo | `scripts/preparar_datos.sh` |
| Filas 3406 y 3407 iguales | **Las dejé.** Tienen distinto `row_id` y podrían ser dos ventas reales; borrarlas sin confirmarlo cambiaría los totales. Las marco para revisar. | – |
| Productos con dos nombres | En el ranking de productos agrupo por código **y** nombre para no mezclar productos distintos | Pregunta 5 |
| Año del `order_id` diferente | Para analizar por año uso siempre `order_date` y no el código | Preguntas 3 y 7 |
| Fechas inválidas, ventas ≤ 0 o descuentos fuera de rango (si aparecen en el futuro) | Separarlos en otra tabla para revisarlos y no cargarlos en la tabla final | Regla para próximas cargas |
| Ganancias negativas | No es un error: son ventas con pérdida y las analizo en la Pregunta 6 | – |

## Interpretación técnica

En general los datos están ordenados: no hay vacíos, ni duplicados de `row_id`, ni fechas raras, ni envíos antes del pedido, ni ventas en cero. También se cumplen las reglas básicas, como que cada orden tenga un solo cliente.

El problema real estaba en el **formato de los números**: el 98.7 % de las ventas y la mitad de los descuentos estaban mal. Me sirvió de lección, porque si solo hubiera revisado vacíos y duplicados no lo habría notado. Lo encontré gracias a la revisión de rangos: un descuento de 45 (4 500 %) no tiene sentido. La revisión 13 muestra que, ya en la tabla final, todos los descuentos están entre 0 y 1.

Los otros problemas (productos con dos nombres, el par de filas iguales y los 7 códigos con otro año) son pequeños, pero los tengo en cuenta en las siguientes preguntas.

## Conclusión

Con las correcciones de la Pregunta 1, la tabla `superstore` pasa todas las revisiones y está lista para analizarse. La regla que seguí fue: corregir lo que se puede recuperar, dejar y marcar lo dudoso, y separar los errores que aparezcan en cargas futuras.
