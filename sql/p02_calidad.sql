-- =====================================================================
-- PREGUNTA 2 - Auditoria de calidad e integridad de datos
-- Se audita la capa cruda (superstore_raw_v, tal como vino el CSV)
-- y la tabla analitica (superstore, despues de la carga).
-- =====================================================================

USE superstore_db;

-- ---------------------------------------------------------------------
-- 2.1 Volumen, duplicados y cardinalidades
-- ---------------------------------------------------------------------
SELECT COUNT(*)                               AS total_registros,
       COUNT(DISTINCT row_id)                 AS row_id_distintos,
       COUNT(*) - COUNT(DISTINCT row_id)      AS row_id_duplicados,
       COUNT(DISTINCT order_id)               AS ordenes_unicas,
       COUNT(DISTINCT customer_id)            AS clientes_unicos,
       COUNT(DISTINCT product_id)             AS productos_unicos
FROM superstore_raw_v;

-- Detalle de identificadores de fila repetidos (lista vacia = sin duplicados)
SELECT row_id, COUNT(*) AS veces
FROM superstore_raw_v
GROUP BY row_id
HAVING COUNT(*) > 1;

-- Filas identicas en todos los campos de negocio (sin contar row_id)
SELECT COUNT(*) AS grupos_duplicados, SUM(veces - 1) AS filas_sobrantes
FROM (
    SELECT order_id, order_date, ship_date, ship_mode, customer_id, product_id,
           sales, quantity, discount, profit, COUNT(*) AS veces
    FROM superstore_raw_v
    GROUP BY order_id, order_date, ship_date, ship_mode, customer_id, product_id,
             sales, quantity, discount, profit
    HAVING COUNT(*) > 1
) d;

-- Detalle de las filas identicas
SELECT r.row_id, r.order_id, r.order_date, r.customer_id, r.product_id,
       r.sales, r.quantity, r.discount, r.profit
FROM superstore_raw_v r
JOIN (SELECT order_id, product_id, sales, quantity
      FROM superstore_raw_v
      GROUP BY order_id, order_date, ship_date, ship_mode, customer_id, product_id,
               sales, quantity, discount, profit
      HAVING COUNT(*) > 1) d
  ON r.order_id = d.order_id AND r.product_id = d.product_id
 AND r.sales = d.sales AND r.quantity = d.quantity
ORDER BY r.row_id;

-- ---------------------------------------------------------------------
-- 2.2 Campos con NULL o vacios (por columna)
-- ---------------------------------------------------------------------
SELECT STACK(21,
    'row_id',        n01, 'order_id',     n02, 'order_date',   n03, 'ship_date',   n04,
    'ship_mode',     n05, 'customer_id',  n06, 'customer_name',n07, 'segment',     n08,
    'country',       n09, 'city',         n10, 'state',        n11, 'postal_code', n12,
    'region',        n13, 'product_id',   n14, 'category',     n15, 'sub_category',n16,
    'product_name',  n17, 'sales',        n18, 'quantity',     n19, 'discount',    n20,
    'profit',        n21) AS (campo, nulos_o_vacios)
FROM (
    SELECT
      SUM(IF(row_id        IS NULL OR TRIM(row_id)        = '', 1, 0)) AS n01,
      SUM(IF(order_id      IS NULL OR TRIM(order_id)      = '', 1, 0)) AS n02,
      SUM(IF(order_date    IS NULL OR TRIM(order_date)    = '', 1, 0)) AS n03,
      SUM(IF(ship_date     IS NULL OR TRIM(ship_date)     = '', 1, 0)) AS n04,
      SUM(IF(ship_mode     IS NULL OR TRIM(ship_mode)     = '', 1, 0)) AS n05,
      SUM(IF(customer_id   IS NULL OR TRIM(customer_id)   = '', 1, 0)) AS n06,
      SUM(IF(customer_name IS NULL OR TRIM(customer_name) = '', 1, 0)) AS n07,
      SUM(IF(segment       IS NULL OR TRIM(segment)       = '', 1, 0)) AS n08,
      SUM(IF(country       IS NULL OR TRIM(country)       = '', 1, 0)) AS n09,
      SUM(IF(city          IS NULL OR TRIM(city)          = '', 1, 0)) AS n10,
      SUM(IF(state         IS NULL OR TRIM(state)         = '', 1, 0)) AS n11,
      SUM(IF(postal_code   IS NULL OR TRIM(postal_code)   = '', 1, 0)) AS n12,
      SUM(IF(region        IS NULL OR TRIM(region)        = '', 1, 0)) AS n13,
      SUM(IF(product_id    IS NULL OR TRIM(product_id)    = '', 1, 0)) AS n14,
      SUM(IF(category      IS NULL OR TRIM(category)      = '', 1, 0)) AS n15,
      SUM(IF(sub_category  IS NULL OR TRIM(sub_category)  = '', 1, 0)) AS n16,
      SUM(IF(product_name  IS NULL OR TRIM(product_name)  = '', 1, 0)) AS n17,
      SUM(IF(sales         IS NULL OR TRIM(sales)         = '', 1, 0)) AS n18,
      SUM(IF(quantity      IS NULL OR TRIM(quantity)      = '', 1, 0)) AS n19,
      SUM(IF(discount      IS NULL OR TRIM(discount)      = '', 1, 0)) AS n20,
      SUM(IF(profit        IS NULL OR TRIM(profit)        = '', 1, 0)) AS n21
    FROM superstore_raw_v
) t;

-- ---------------------------------------------------------------------
-- 2.3 Fechas invalidas o inconsistentes
--   - no convertibles con el formato M/d/yyyy
--   - fechas "corregidas" por el parser (ej. 2/30 -> 3/1): se detectan
--     volviendo a formatear y comparando con el texto original
--   - anio de la fecha distinto al anio incluido en order_id
-- ---------------------------------------------------------------------
WITH f AS (
    SELECT row_id, order_id, order_date, ship_date,
           UNIX_TIMESTAMP(order_date, 'M/d/yyyy') AS ts_order,
           UNIX_TIMESTAMP(ship_date,  'M/d/yyyy') AS ts_ship
    FROM superstore_raw_v
)
SELECT
    SUM(IF(ts_order IS NULL, 1, 0)) AS order_date_no_convertible,
    SUM(IF(ts_ship  IS NULL, 1, 0)) AS ship_date_no_convertible,
    SUM(IF(ts_order IS NOT NULL AND FROM_UNIXTIME(ts_order, 'M/d/yyyy') <> order_date, 1, 0)) AS order_date_inexistente,
    SUM(IF(ts_ship  IS NOT NULL AND FROM_UNIXTIME(ts_ship,  'M/d/yyyy') <> ship_date,  1, 0)) AS ship_date_inexistente,
    SUM(IF(YEAR(FROM_UNIXTIME(ts_order)) NOT BETWEEN 2014 AND 2017, 1, 0))                 AS order_date_fuera_rango,
    SUM(IF(CAST(SPLIT(order_id, '-')[1] AS INT) <> YEAR(FROM_UNIXTIME(ts_order)), 1, 0))  AS anio_order_id_distinto,
    SUM(IF(ts_ship < ts_order, 1, 0))                                                      AS envio_antes_de_pedido,
    SUM(IF(DATEDIFF(FROM_UNIXTIME(ts_ship), FROM_UNIXTIME(ts_order)) > 30, 1, 0))          AS envio_mas_de_30_dias
FROM f;

-- Detalle: ordenes cuyo anio en el codigo no coincide con la fecha
SELECT DISTINCT order_id, order_date, ship_date
FROM superstore_raw_v
WHERE CAST(SPLIT(order_id, '-')[1] AS INT) <> YEAR(FROM_UNIXTIME(UNIX_TIMESTAMP(order_date, 'M/d/yyyy')))
ORDER BY order_id;

-- Distribucion de dias de entrega por modalidad (consistencia del envio)
SELECT ship_mode,
       COUNT(*)                                  AS registros,
       MIN(DATEDIFF(ship_date, order_date))      AS dias_min,
       ROUND(AVG(DATEDIFF(ship_date, order_date)), 2) AS dias_prom,
       MAX(DATEDIFF(ship_date, order_date))      AS dias_max
FROM superstore
GROUP BY ship_mode
ORDER BY dias_prom;

-- ---------------------------------------------------------------------
-- 2.4 Ventas, descuentos y ganancias
--   En la capa cruda el descuento sin punto decimal produce valores
--   de hasta 45 (= 4500 %): es la evidencia del problema de formato.
-- ---------------------------------------------------------------------
SELECT 'capa cruda (CSV)' AS capa,
       SUM(IF(CAST(sales AS DECIMAL(18,4)) <= 0, 1, 0))                          AS ventas_cero_o_negativas,
       SUM(IF(CAST(discount AS DECIMAL(18,4)) < 0
           OR CAST(discount AS DECIMAL(18,4)) > 1, 1, 0))                        AS descuento_fuera_0_1,
       MIN(CAST(discount AS DECIMAL(18,4)))                                      AS descuento_min,
       MAX(CAST(discount AS DECIMAL(18,4)))                                      AS descuento_max,
       SUM(IF(CAST(quantity AS INT) <= 0, 1, 0))                                 AS cantidad_no_positiva,
       SUM(IF(CAST(sales AS DECIMAL(18,4)) IS NULL OR CAST(profit AS DECIMAL(18,4)) IS NULL, 1, 0)) AS montos_no_numericos
FROM superstore_raw_v
UNION ALL
SELECT 'tabla analitica' AS capa,
       SUM(IF(sales <= 0, 1, 0)),
       SUM(IF(discount < 0 OR discount > 1, 1, 0)),
       MIN(discount),
       MAX(discount),
       SUM(IF(quantity <= 0, 1, 0)),
       SUM(IF(sales IS NULL OR profit IS NULL, 1, 0))
FROM superstore;

-- Descuentos validos pero altos (>= 50 %) y ganancia mayor que la venta
SELECT SUM(IF(discount >= 0.5, 1, 0))     AS descuento_mayor_igual_50,
       SUM(IF(discount >= 0.7, 1, 0))     AS descuento_mayor_igual_70,
       SUM(IF(profit > sales, 1, 0))      AS ganancia_mayor_a_venta,
       SUM(IF(profit < 0, 1, 0))          AS registros_con_perdida
FROM superstore;

-- ---------------------------------------------------------------------
-- 2.5 Integridad de claves y catalogos
-- ---------------------------------------------------------------------
-- Un product_id deberia tener un solo nombre y una sola categoria
SELECT COUNT(*) AS product_id_con_varios_nombres
FROM (SELECT product_id FROM superstore GROUP BY product_id
      HAVING COUNT(DISTINCT product_name) > 1) x;

SELECT product_id, COLLECT_SET(product_name) AS nombres
FROM superstore
GROUP BY product_id
HAVING COUNT(DISTINCT product_name) > 1
ORDER BY product_id
LIMIT 5;

-- Un customer_id deberia tener un solo nombre y un solo segmento
SELECT SUM(IF(n_nombres  > 1, 1, 0)) AS clientes_con_varios_nombres,
       SUM(IF(n_segmentos > 1, 1, 0)) AS clientes_con_varios_segmentos
FROM (SELECT customer_id,
             COUNT(DISTINCT customer_name) AS n_nombres,
             COUNT(DISTINCT segment)       AS n_segmentos
      FROM superstore GROUP BY customer_id) c;

-- Una orden deberia tener una sola fecha, cliente y modalidad de envio
SELECT COUNT(*) AS ordenes_inconsistentes
FROM (SELECT order_id FROM superstore GROUP BY order_id
      HAVING COUNT(DISTINCT order_date) > 1
          OR COUNT(DISTINCT customer_id) > 1
          OR COUNT(DISTINCT ship_mode) > 1) o;

-- Codigos postales que perdieron el cero inicial
SELECT COUNT(*) AS postal_code_menos_de_5_digitos,
       COLLECT_SET(state) AS estados
FROM superstore_raw_v
WHERE LENGTH(postal_code) < 5;

-- ---------------------------------------------------------------------
-- 2.6 RESUMEN DE CALIDAD (una fila por control)
-- ---------------------------------------------------------------------
WITH raw AS (
    SELECT row_id, order_id, customer_id, product_id, postal_code,
           UNIX_TIMESTAMP(order_date, 'M/d/yyyy') AS ts_order,
           UNIX_TIMESTAMP(ship_date,  'M/d/yyyy') AS ts_ship,
           order_date, ship_date, sales, discount, profit, product_name
    FROM superstore_raw_v
),
total AS (SELECT COUNT(*) AS n FROM raw),
controles AS (
    SELECT '01 Total de registros'                      AS control, COUNT(*) AS valor, 'informativo' AS tipo FROM raw
    UNION ALL
    SELECT '02 Row ID duplicados',          COUNT(*) - COUNT(DISTINCT row_id), 'error' FROM raw
    UNION ALL
    SELECT '03 Ordenes unicas',             COUNT(DISTINCT order_id), 'informativo' FROM raw
    UNION ALL
    SELECT '04 Clientes unicos',            COUNT(DISTINCT customer_id), 'informativo' FROM raw
    UNION ALL
    SELECT '05 Registros con algun campo NULL o vacio',
           SUM(IF(row_id IS NULL OR order_id IS NULL OR product_id IS NULL OR customer_id IS NULL
               OR TRIM(sales) = '' OR TRIM(profit) = '' OR TRIM(discount) = ''
               OR TRIM(order_date) = '' OR TRIM(ship_date) = '' OR TRIM(postal_code) = '', 1, 0)), 'error' FROM raw
    UNION ALL
    SELECT '06 Fechas invalidas o no convertibles',
           SUM(IF(ts_order IS NULL OR ts_ship IS NULL
               OR FROM_UNIXTIME(ts_order, 'M/d/yyyy') <> order_date
               OR FROM_UNIXTIME(ts_ship,  'M/d/yyyy') <> ship_date, 1, 0)), 'error' FROM raw
    UNION ALL
    SELECT '07 Envio anterior al pedido',   SUM(IF(ts_ship < ts_order, 1, 0)), 'error' FROM raw
    UNION ALL
    SELECT '07b Anio de order_id distinto al de order_date',
           SUM(IF(CAST(SPLIT(order_id, '-')[1] AS INT) <> YEAR(FROM_UNIXTIME(ts_order)), 1, 0)), 'advertencia' FROM raw
    UNION ALL
    SELECT '08 Ventas <= 0',                SUM(IF(CAST(sales AS DECIMAL(18,4)) <= 0, 1, 0)), 'error' FROM raw
    UNION ALL
    SELECT '09 Descuento fuera de [0,1] en CSV original',
           SUM(IF(CAST(discount AS DECIMAL(18,4)) NOT BETWEEN 0 AND 1, 1, 0)), 'error de formato' FROM raw
    UNION ALL
    SELECT '10 Montos sin punto decimal (sales distinto de referencia)',
           SUM(IF(CAST(r.sales AS DECIMAL(18,4)) <> CAST(f.sales AS DECIMAL(18,4)), 1, 0)), 'error de formato'
    FROM raw r JOIN superstore_ref_v f ON CAST(r.row_id AS INT) = CAST(f.row_id AS INT)
    UNION ALL
    SELECT '11 Codigo postal con menos de 5 digitos', SUM(IF(LENGTH(postal_code) < 5, 1, 0)), 'error de formato' FROM raw
    UNION ALL
    SELECT '12 Nombre de producto con separador ;', SUM(IF(INSTR(product_name, ';') > 0, 1, 0)), 'advertencia' FROM raw
    UNION ALL
    SELECT '13 Descuento fuera de [0,1] en tabla analitica',
           SUM(IF(discount < 0 OR discount > 1, 1, 0)), 'error' FROM superstore
    UNION ALL
    SELECT '14 Registros con perdida (profit < 0)', SUM(IF(profit < 0, 1, 0)), 'informativo' FROM superstore
)
SELECT c.control,
       c.valor,
       ROUND(c.valor * 100.0 / t.n, 2) AS pct_sobre_total,
       c.tipo
FROM controles c CROSS JOIN total t
ORDER BY c.control;
