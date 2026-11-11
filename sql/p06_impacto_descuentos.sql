-- =====================================================================
-- PREGUNTA 6 - Analisis del impacto de los descuentos
-- Rangos: Sin descuento (0) | Bajo (0, 20%] | Medio (20%, 50%] | Alto (> 50%)
-- Registro con perdida  : profit < 0
-- Registro no rentable  : profit <= 0 (no genera ganancia)
-- =====================================================================

USE superstore_db;

-- Vista con el rango asignado a cada linea (se reutiliza en todo el script)
CREATE OR REPLACE VIEW superstore_rango_desc AS
SELECT s.*,
       CASE WHEN discount = 0    THEN '1 Sin descuento'
            WHEN discount <= 0.20 THEN '2 Bajo (0-20%]'
            WHEN discount <= 0.50 THEN '3 Medio (20-50%]'
            ELSE                      '4 Alto (>50%)'
       END AS rango_descuento
FROM superstore s;

-- ---------------------------------------------------------------------
-- 6.1 Indicadores por rango de descuento
-- ---------------------------------------------------------------------
SELECT rango_descuento,
       COUNT(*)                                                    AS registros,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)          AS pct_registros,
       ROUND(SUM(sales), 2)                                        AS ventas,
       ROUND(SUM(profit), 2)                                       AS ganancia,
       ROUND(SUM(profit) / SUM(sales) * 100, 2)                    AS margen_pct,
       SUM(IF(profit < 0, 1, 0))                                   AS registros_con_perdida,
       SUM(IF(profit <= 0, 1, 0))                                  AS registros_no_rentables,
       ROUND(SUM(IF(profit <= 0, 1, 0)) * 100.0 / COUNT(*), 2)     AS pct_no_rentables,
       ROUND(AVG(discount) * 100, 2)                               AS descuento_prom_pct,
       ROUND(SUM(IF(profit < 0, profit, 0)), 2)                    AS monto_perdidas
FROM superstore_rango_desc
GROUP BY rango_descuento
ORDER BY rango_descuento;

-- ---------------------------------------------------------------------
-- 6.2 Detalle por cada nivel de descuento (curva descuento vs perdida)
-- ---------------------------------------------------------------------
SELECT discount,
       rango_descuento,
       COUNT(*)                                                AS registros,
       ROUND(SUM(sales), 2)                                    AS ventas,
       ROUND(SUM(profit), 2)                                   AS ganancia,
       ROUND(SUM(profit) / SUM(sales) * 100, 2)                AS margen_pct,
       ROUND(SUM(IF(profit <= 0, 1, 0)) * 100.0 / COUNT(*), 2) AS pct_no_rentables
FROM superstore_rango_desc
GROUP BY discount, rango_descuento
ORDER BY discount;

-- ---------------------------------------------------------------------
-- 6.3 Categorias mas afectadas: perdidas y % no rentable por rango
-- ---------------------------------------------------------------------
SELECT category,
       rango_descuento,
       COUNT(*)                                                AS registros,
       ROUND(SUM(sales), 2)                                    AS ventas,
       ROUND(SUM(profit), 2)                                   AS ganancia,
       ROUND(SUM(profit) / SUM(sales) * 100, 2)                AS margen_pct,
       ROUND(SUM(IF(profit <= 0, 1, 0)) * 100.0 / COUNT(*), 2) AS pct_no_rentables
FROM superstore_rango_desc
GROUP BY category, rango_descuento
ORDER BY category, rango_descuento;

-- Resumen por categoria: cuanto pierde en lineas con descuento
WITH cat AS (
    SELECT category,
           SUM(IF(discount > 0, 1, 0))                         AS lineas_con_desc,
           ROUND(AVG(IF(discount > 0, discount, NULL)) * 100, 2) AS desc_prom_pct,
           ROUND(SUM(IF(discount > 0 AND profit < 0, profit, 0)), 2) AS perdidas_con_desc,
           ROUND(SUM(IF(discount = 0, profit, 0)) / SUM(IF(discount = 0, sales, 0)) * 100, 2) AS margen_sin_desc,
           ROUND(SUM(IF(discount > 0, profit, 0)) / SUM(IF(discount > 0, sales, 0)) * 100, 2) AS margen_con_desc,
           ROUND(SUM(IF(discount > 0 AND profit <= 0, 1, 0)) * 100.0 / SUM(IF(discount > 0, 1, 0)), 2) AS pct_no_rent_con_desc
    FROM superstore
    GROUP BY category
)
SELECT cat.*,
       RANK() OVER (ORDER BY perdidas_con_desc ASC) AS rank_afectacion
FROM cat
ORDER BY rank_afectacion;

-- ---------------------------------------------------------------------
-- 6.4 Subcategorias mas afectadas (ranking por perdidas en lineas con
--     descuento) - top 10
-- ---------------------------------------------------------------------
WITH sub AS (
    SELECT category,
           sub_category,
           COUNT(*)                                                       AS registros,
           ROUND(AVG(discount) * 100, 2)                                  AS desc_prom_pct,
           ROUND(SUM(IF(discount > 0.20, 1, 0)) * 100.0 / COUNT(*), 2)    AS pct_lineas_desc_medio_alto,
           ROUND(SUM(sales), 2)                                           AS ventas,
           ROUND(SUM(profit), 2)                                          AS ganancia,
           ROUND(SUM(profit) / SUM(sales) * 100, 2)                       AS margen_pct,
           ROUND(SUM(IF(discount > 0 AND profit < 0, profit, 0)), 2)      AS perdidas_con_desc,
           ROUND(SUM(IF(profit <= 0, 1, 0)) * 100.0 / COUNT(*), 2)        AS pct_no_rentables
    FROM superstore
    GROUP BY category, sub_category
)
SELECT RANK() OVER (ORDER BY perdidas_con_desc ASC) AS rank_afectacion,
       sub.*
FROM sub
ORDER BY rank_afectacion
LIMIT 10;

-- Subcategorias con ganancia total negativa
SELECT category, sub_category, ROUND(SUM(profit), 2) AS ganancia,
       ROUND(AVG(discount) * 100, 2) AS desc_prom_pct
FROM superstore
GROUP BY category, sub_category
HAVING SUM(profit) < 0
ORDER BY ganancia;

-- ---------------------------------------------------------------------
-- 6.5 Asociacion entre descuento y rentabilidad
--   - Correlacion de Pearson entre descuento y ganancia / margen por linea
--   - Comparacion directa del % no rentable: alto vs sin descuento
-- ---------------------------------------------------------------------
SELECT ROUND(CORR(CAST(discount AS DOUBLE), CAST(profit AS DOUBLE)), 4)                AS corr_descuento_ganancia,
       ROUND(CORR(CAST(discount AS DOUBLE), CAST(profit / sales AS DOUBLE)), 4)        AS corr_descuento_margen_linea,
       ROUND(SUM(IF(discount > 0.5  AND profit <= 0, 1, 0)) * 100.0 / SUM(IF(discount > 0.5, 1, 0)), 2) AS pct_no_rent_alto,
       ROUND(SUM(IF(discount = 0    AND profit <= 0, 1, 0)) * 100.0 / SUM(IF(discount = 0, 1, 0)), 2)   AS pct_no_rent_sin_desc,
       ROUND(SUM(IF(discount > 0.2  AND profit <= 0, 1, 0)) * 100.0 / SUM(IF(discount > 0.2, 1, 0)), 2) AS pct_no_rent_mayor_20,
       ROUND(SUM(IF(discount <= 0.2 AND profit <= 0, 1, 0)) * 100.0 / SUM(IF(discount <= 0.2, 1, 0)), 2) AS pct_no_rent_hasta_20
FROM superstore;

-- Umbral de quiebre: primer nivel de descuento con margen negativo
WITH niveles AS (
    SELECT discount, SUM(profit) / SUM(sales) * 100 AS margen_pct
    FROM superstore
    GROUP BY discount
)
SELECT MIN(discount) AS primer_descuento_con_margen_negativo
FROM niveles
WHERE margen_pct < 0;
