# Pregunta 2. Auditoría de calidad e integridad de datos

## Enunciado

Realice un análisis de calidad sobre el dataset. Determine: cantidad total de registros, identificadores de fila duplicados, órdenes y clientes únicos, campos con NULL, fechas inválidas o inconsistentes, ventas iguales o inferiores a cero, descuentos fuera del intervalo esperado y registros con fecha de envío anterior a la fecha de pedido. Construya una consulta que entregue un resumen de calidad y proponga criterios de tratamiento.

## Estrategia de solución

- La auditoría se hace sobre la **capa cruda** (`superstore_raw_v`), porque ahí está el dato tal como vino. Algunos controles se repiten sobre la **tabla analítica** (`superstore`) para comprobar que la carga corrigió los problemas.
- **Duplicados:** `COUNT(*) - COUNT(DISTINCT row_id)` y, como control extra, filas idénticas en todos los campos de negocio sin contar `row_id`.
- **NULL / vacíos:** como OpenCSVSerde lee todo como `STRING`, un campo faltante puede llegar como `NULL` o como `''`. Se cuentan ambos casos por columna y se pasa de columnas a filas con `STACK()`.
- **Fechas:** se convierten con `UNIX_TIMESTAMP(fecha, 'M/d/yyyy')`. Se considera inválida si no se puede convertir (`NULL`) o si al volver a formatearla no da el mismo texto. Esto detecta fechas inexistentes como `2/30/2016`, que el parser “corrige” en silencio a `3/1/2016`. También se compara el año del `order_id` con el de `order_date`.
- **Rangos:** ventas ≤ 0, descuento fuera de [0, 1] y envío antes del pedido.
- **Integridad de catálogos:** un `product_id` con un solo nombre, un cliente con un solo nombre y segmento, y una orden con una sola fecha, cliente y modalidad de envío.
- **Resumen:** una sola consulta con `WITH` + `UNION ALL` que devuelve una fila por control, con el porcentaje sobre el total y el tipo de hallazgo.

## Consulta HiveQL desarrollada

Script completo: [`sql/p02_calidad.sql`](../sql/p02_calidad.sql). Consulta de resumen (fragmento):

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
    -- ... (14 controles en total)
)
SELECT c.control, c.valor, ROUND(c.valor * 100.0 / t.n, 2) AS pct_sobre_total, c.tipo
FROM controles c CROSS JOIN total t
ORDER BY c.control;
```

## Evidencia de ejecución

[`evidencias/p02_calidad.txt`](../evidencias/p02_calidad.txt)

## Resultado obtenido

### Resumen de calidad

| Control | Valor | % del total | Tipo |
|---------|------:|------------:|------|
| 01 Total de registros | 9 994 | 100.00 | informativo |
| 02 Row ID duplicados | 0 | 0.00 | error |
| 03 Órdenes únicas | 5 009 | – | informativo |
| 04 Clientes únicos | 793 | – | informativo |
| 05 Registros con algún campo NULL o vacío | 0 | 0.00 | error |
| 06 Fechas inválidas o no convertibles | 0 | 0.00 | error |
| 07 Envío anterior al pedido | 0 | 0.00 | error |
| 07b Año de `order_id` distinto al de `order_date` | 7 | 0.07 | advertencia |
| 08 Ventas ≤ 0 | 0 | 0.00 | error |
| 09 Descuento fuera de [0,1] en el CSV original | 5 102 | 51.05 | error de formato |
| 10 Montos sin punto decimal (`sales` ≠ referencia) | 9 866 | 98.72 | error de formato |
| 11 Código postal con menos de 5 dígitos | 449 | 4.49 | error de formato |
| 12 Nombre de producto con separador `;` | 6 | 0.06 | advertencia |
| 13 Descuento fuera de [0,1] en la tabla analítica | 0 | 0.00 | error |
| 14 Registros con pérdida (`profit < 0`) | 1 871 | 18.72 | informativo |

### Detalles

- **NULL por campo:** los 21 campos tienen 0 valores NULL o vacíos.
- **Filas idénticas sin contar `row_id`:** 1 par (filas 3406 y 3407, orden `US-2014-150119`, mismo producto, cantidad, venta y ganancia).
- **Año del `order_id`:** 7 líneas de 5 órdenes con fecha `12/31/2016` tienen código `XX-2017-...`. Coincide con el año de envío; no es un error de fecha.
- **Días de entrega por modalidad:** Same Day 0–1 días, First Class 1–4, Second Class 1–5, Standard Class 3–7. Son coherentes con cada modalidad.
- **Descuento en el CSV original:** mínimo 0, máximo 45 (debería ser 0.45). En la tabla analítica el rango es 0.00–0.80.
- **Catálogo de productos:** 32 `product_id` tienen dos nombres distintos (ej. `FUR-BO-10002213`: “Sauder Forest Hills Library…” y “DMI Eclipse Executive Suite Bookcases”).
- **Clientes y órdenes:** 0 clientes con más de un nombre o segmento y 0 órdenes con más de una fecha, cliente o modalidad.
- **Códigos postales:** los 449 códigos de 4 dígitos son de New Jersey, Maine, Connecticut, Massachusetts, Vermont, Rhode Island y New Hampshire, estados cuyos ZIP empiezan con 0.
- **Valores extremos válidos:** 922 registros con descuento ≥ 50 % y 718 con ≥ 70 %. Ningún registro tiene una ganancia mayor que la venta.

## Criterios de tratamiento propuestos

| Hallazgo | Criterio | Aplicado en |
|----------|----------|-------------|
| Separador decimal eliminado (`sales`, `profit`) | Restaurar el punto con la copia de referencia, solo si los dígitos coinciden exactamente; si no, dejar NULL y excluir el registro de los cálculos monetarios | `sql/p01_carga.sql` (0 NULL) |
| Descuento sin punto decimal | Reconstruir como `0.` + dígitos y validar contra la referencia | `sql/p01_carga.sql` (0 diferencias) |
| Código postal sin cero inicial | `LPAD(postal_code, 5, '0')` y tipo STRING | `sql/p01_carga.sql` |
| `;` dentro de `product_name` | Leer con `OpenCSVSerde` respetando comillas | `sql/p01_ddl.sql` |
| Codificación Windows-1252 / CRLF | Convertir a UTF-8 y LF antes de cargar | `scripts/preparar_datos.sh` |
| Filas 3406 / 3407 idénticas | **Conservar.** Tienen `row_id` distinto y pueden ser dos líneas reales de la misma orden; borrarlas sin confirmación del negocio alteraría ventas y ganancias. Se marca para revisión. | – |
| `product_id` con 2 nombres | En los rankings de productos se agrupa por `product_id` **y** `product_name` para no mezclar artículos distintos | Pregunta 5 |
| Año del `order_id` ≠ año del pedido | Usar siempre `order_date` para el análisis temporal; el `order_id` es solo un identificador | Preguntas 3 y 7 |
| Fechas inválidas, envío antes del pedido, ventas ≤ 0, descuento fuera de [0,1] (si aparecieran en una carga futura) | Rechazar a una tabla de cuarentena con el motivo, no cargarlas en la tabla analítica | Regla para próximas cargas |
| Ganancias negativas | **No es un error:** son ventas con pérdida y se analizan en la Pregunta 6 | – |

## Interpretación técnica

En estructura el dataset está limpio: no tiene NULL, ni `row_id` repetidos, ni fechas inválidas, ni envíos anteriores al pedido, ni ventas en cero o negativas. Las reglas de negocio también se cumplen: cada orden tiene un único cliente, fecha y modalidad de envío, y los días de entrega son coherentes con la modalidad.

El problema serio es de **formato**: el 98.7 % de las ventas y el 51 % de los descuentos estaban mal escalados por la pérdida del punto decimal. Una auditoría que solo revisara NULL y duplicados lo habría pasado por alto. Por eso conviene validar rangos (descuento entre 0 y 1) y comparar con valores conocidos. El control 13 muestra que, después de la carga, ningún descuento queda fuera de rango.

Los hallazgos menores (32 productos con dos nombres, un par de filas idénticas y 7 líneas con año distinto en el `order_id`) no impiden el análisis, pero sí influyen en cómo agrupar y filtrar en las preguntas siguientes.

## Conclusión

Después de la corrección de formato hecha en la Pregunta 1, la tabla `superstore` pasa todos los controles de integridad y queda apta para el análisis. Los criterios de tratamiento quedan definidos: corregir lo recuperable, conservar y marcar lo dudoso, y mandar a cuarentena los errores que aparezcan en cargas futuras.
