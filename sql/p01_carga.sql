-- =====================================================================
-- PREGUNTA 1 - Procedimiento de carga (DML)
-- Requisito previo: bash scripts/preparar_datos.sh
-- Ejecutar desde la raiz del repositorio.
-- =====================================================================

USE superstore_db;

-- 1) Carga de archivos a las tablas de texto
LOAD DATA LOCAL INPATH 'csv/preparado/superstore_utf8.csv'
OVERWRITE INTO TABLE superstore_raw;

LOAD DATA LOCAL INPATH 'csv/preparado/referencia_utf8.csv'
OVERWRITE INTO TABLE superstore_ref;

SELECT 'superstore_raw_v' AS tabla, COUNT(*) AS registros FROM superstore_raw_v
UNION ALL
SELECT 'superstore_ref_v' AS tabla, COUNT(*) AS registros FROM superstore_ref_v;

-- 2) Muestra del problema: el CSV original perdio el punto decimal
SELECT r.row_id, r.sales AS sales_csv, f.sales AS sales_ref,
       r.discount AS discount_csv, f.discount AS discount_ref,
       r.profit AS profit_csv, f.profit AS profit_ref
FROM superstore_raw_v r
JOIN superstore_ref_v f ON CAST(r.row_id AS INT) = CAST(f.row_id AS INT)
WHERE CAST(r.row_id AS INT) <= 5
ORDER BY r.row_id;

-- 3) Carga de la tabla analitica con particionamiento dinamico
SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;

INSERT OVERWRITE TABLE superstore PARTITION (order_year)
SELECT
    row_id, order_id, order_date, ship_date, ship_mode,
    customer_id, customer_name, segment, country, city, state,
    postal_code, region, product_id, category, sub_category, product_name,
    sales, quantity, discount, profit,
    YEAR(order_date) AS order_year
FROM (
    SELECT
        CAST(r.row_id AS INT)                                              AS row_id,
        TRIM(r.order_id)                                                   AS order_id,
        TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(r.order_date, 'M/d/yyyy')))   AS order_date,
        TO_DATE(FROM_UNIXTIME(UNIX_TIMESTAMP(r.ship_date,  'M/d/yyyy')))   AS ship_date,
        TRIM(r.ship_mode)                                                  AS ship_mode,
        TRIM(r.customer_id)                                                AS customer_id,
        TRIM(r.customer_name)                                              AS customer_name,
        TRIM(r.segment)                                                    AS segment,
        TRIM(r.country)                                                    AS country,
        TRIM(r.city)                                                       AS city,
        TRIM(r.state)                                                      AS state,
        LPAD(TRIM(r.postal_code), 5, '0')                                  AS postal_code,
        TRIM(r.region)                                                     AS region,
        TRIM(r.product_id)                                                 AS product_id,
        TRIM(r.category)                                                   AS category,
        TRIM(r.sub_category)                                               AS sub_category,
        TRIM(r.product_name)                                               AS product_name,
        -- Se toma el valor con decimales de la referencia SOLO si sus
        -- digitos (sin punto ni ceros a la izquierda) son identicos al CSV.
        -- Si no coinciden el resultado es NULL y se detecta en la validacion.
        CASE WHEN REGEXP_REPLACE(REGEXP_REPLACE(f.sales, '[.]', ''), '^(-?)0+(?=[0-9])', '$1') = r.sales
             THEN CAST(f.sales AS DECIMAL(12,4)) END                        AS sales,
        CAST(r.quantity AS INT)                                            AS quantity,
        -- El descuento se reconstruye sin referencia: '2' -> 0.2, '45' -> 0.45
        CAST(CASE WHEN r.discount = '0' THEN '0'
                  ELSE CONCAT('0.', r.discount) END AS DECIMAL(4,2))        AS discount,
        CASE WHEN REGEXP_REPLACE(REGEXP_REPLACE(f.profit, '[.]', ''), '^(-?)0+(?=[0-9])', '$1') = r.profit
             THEN CAST(f.profit AS DECIMAL(12,4)) END                       AS profit
    FROM superstore_raw_v r
    LEFT JOIN superstore_ref_v f
           ON CAST(r.row_id AS INT) = CAST(f.row_id AS INT)
          AND TRIM(r.product_id) = TRIM(f.product_id)
) t;

-- 4) Evidencia de registros importados
SHOW PARTITIONS superstore;

SELECT order_year, COUNT(*) AS registros
FROM superstore
GROUP BY order_year
ORDER BY order_year;

SELECT COUNT(*)                                          AS total_registros,
       SUM(CASE WHEN sales    IS NULL THEN 1 ELSE 0 END) AS sales_no_recuperadas,
       SUM(CASE WHEN profit   IS NULL THEN 1 ELSE 0 END) AS profit_no_recuperados,
       SUM(CASE WHEN discount IS NULL THEN 1 ELSE 0 END) AS discount_nulos,
       SUM(CASE WHEN order_date IS NULL OR ship_date IS NULL THEN 1 ELSE 0 END) AS fechas_nulas
FROM superstore;

-- Control cruzado: el descuento reconstruido coincide con la referencia
SELECT COUNT(*) AS descuentos_distintos_a_referencia
FROM superstore s
JOIN superstore_ref_v f ON s.row_id = CAST(f.row_id AS INT)
WHERE s.discount <> CAST(f.discount AS DECIMAL(4,2));

SELECT ROUND(SUM(sales), 2)  AS ventas_totales,
       ROUND(SUM(profit), 2) AS ganancia_total,
       SUM(quantity)         AS unidades
FROM superstore;

SELECT row_id, order_id, order_date, ship_date, customer_name, postal_code,
       product_name, sales, quantity, discount, profit, order_year
FROM superstore
WHERE row_id IN (1, 4, 182, 2235)
ORDER BY row_id;
