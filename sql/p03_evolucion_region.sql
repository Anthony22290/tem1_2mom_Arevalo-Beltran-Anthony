-- =====================================================================
-- PREGUNTA 3 - Analisis de evolucion comercial por region
-- Tecnicas: CTE (WITH) + funciones de ventana (LAG, RANK, SUM OVER)
-- =====================================================================

USE superstore_db;

-- ---------------------------------------------------------------------
-- 3.1 Ventas, ganancia, margen y variacion interanual por region y anio
-- ---------------------------------------------------------------------
WITH region_anio AS (
    SELECT region,
           order_year                 AS anio,
           SUM(sales)                 AS ventas,
           SUM(profit)                AS ganancia,
           COUNT(DISTINCT order_id)   AS ordenes
    FROM superstore
    GROUP BY region, order_year
),
con_lag AS (
    SELECT region, anio, ventas, ganancia, ordenes,
           ganancia / ventas * 100                                     AS margen,
           LAG(ventas)   OVER (PARTITION BY region ORDER BY anio)      AS ventas_anio_ant,
           LAG(ganancia) OVER (PARTITION BY region ORDER BY anio)      AS ganancia_anio_ant
    FROM region_anio
)
SELECT region,
       anio,
       ordenes,
       ROUND(ventas, 2)                                                AS ventas,
       ROUND(ganancia, 2)                                              AS ganancia,
       ROUND(margen, 2)                                                AS margen_pct,
       ROUND((ventas - ventas_anio_ant) / ventas_anio_ant * 100, 2)    AS var_ventas_pct,
       ROUND((ganancia - ganancia_anio_ant) / ABS(ganancia_anio_ant) * 100, 2) AS var_ganancia_pct,
       RANK() OVER (PARTITION BY anio ORDER BY ventas DESC)            AS rank_ventas_anio,
       RANK() OVER (PARTITION BY anio ORDER BY ganancia DESC)          AS rank_ganancia_anio
FROM con_lag
ORDER BY region, anio;

-- ---------------------------------------------------------------------
-- 3.2 Ranking de regiones por anio (quien lidera cada anio)
-- ---------------------------------------------------------------------
WITH region_anio AS (
    SELECT region, order_year AS anio, SUM(sales) AS ventas, SUM(profit) AS ganancia
    FROM superstore
    GROUP BY region, order_year
),
ranking AS (
    SELECT anio, region, ventas, ganancia,
           RANK() OVER (PARTITION BY anio ORDER BY ganancia DESC) AS pos_desc,
           RANK() OVER (PARTITION BY anio ORDER BY ganancia ASC)  AS pos_asc
    FROM region_anio
)
SELECT anio,
       MAX(IF(pos_desc = 1, region, NULL))                AS mejor_region,
       ROUND(MAX(IF(pos_desc = 1, ganancia, NULL)), 2)    AS ganancia_mejor,
       MAX(IF(pos_asc = 1, region, NULL))                 AS peor_region,
       ROUND(MAX(IF(pos_asc = 1, ganancia, NULL)), 2)     AS ganancia_peor
FROM ranking
GROUP BY anio
ORDER BY anio;

-- ---------------------------------------------------------------------
-- 3.3 Desempeno acumulado 2014-2017 y crecimiento del periodo
--   Criterio de desempeno: se ordena por ganancia acumulada (lo que el
--   negocio realmente gana) y se informa tambien ventas, margen,
--   participacion y crecimiento 2014->2017 (CAGR de ventas).
-- ---------------------------------------------------------------------
WITH region_anio AS (
    SELECT region, order_year AS anio, SUM(sales) AS ventas, SUM(profit) AS ganancia
    FROM superstore
    GROUP BY region, order_year
),
extremos AS (
    SELECT region, anio, ventas, ganancia,
           FIRST_VALUE(ventas) OVER (PARTITION BY region ORDER BY anio
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS ventas_inicio,
           LAST_VALUE(ventas)  OVER (PARTITION BY region ORDER BY anio
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS ventas_fin,
           COUNT(*)            OVER (PARTITION BY region)                                      AS n_anios
    FROM region_anio
),
acumulado AS (
    SELECT region,
           SUM(ventas)        AS ventas_total,
           SUM(ganancia)      AS ganancia_total,
           MAX(ventas_inicio) AS ventas_2014,
           MAX(ventas_fin)    AS ventas_2017,
           MAX(n_anios)       AS n_anios
    FROM extremos
    GROUP BY region
)
SELECT region,
       ROUND(ventas_total, 2)                                                  AS ventas_total,
       ROUND(ganancia_total, 2)                                                AS ganancia_total,
       ROUND(ganancia_total / ventas_total * 100, 2)                           AS margen_pct,
       ROUND(ventas_total   / SUM(ventas_total)   OVER () * 100, 2)            AS part_ventas_pct,
       ROUND(ganancia_total / SUM(ganancia_total) OVER () * 100, 2)            AS part_ganancia_pct,
       ROUND((POWER(ventas_2017 / ventas_2014, 1.0 / (n_anios - 1)) - 1) * 100, 2) AS cagr_ventas_pct,
       RANK() OVER (ORDER BY ganancia_total DESC)                              AS rank_ganancia,
       RANK() OVER (ORDER BY ganancia_total / ventas_total DESC)               AS rank_margen,
       CASE WHEN RANK() OVER (ORDER BY ganancia_total DESC) = 1 THEN 'MEJOR DESEMPENO'
            WHEN RANK() OVER (ORDER BY ganancia_total ASC)  = 1 THEN 'PEOR DESEMPENO'
            ELSE '-' END                                                       AS clasificacion
FROM acumulado
ORDER BY rank_ganancia;

-- ---------------------------------------------------------------------
-- 3.4 Total de la empresa por anio (contexto)
-- ---------------------------------------------------------------------
WITH anual AS (
    SELECT order_year AS anio, SUM(sales) AS ventas, SUM(profit) AS ganancia
    FROM superstore
    GROUP BY order_year
)
SELECT anio,
       ROUND(ventas, 2)                                                     AS ventas,
       ROUND(ganancia, 2)                                                   AS ganancia,
       ROUND(ganancia / ventas * 100, 2)                                    AS margen_pct,
       ROUND((ventas / LAG(ventas) OVER (ORDER BY anio) - 1) * 100, 2)      AS var_ventas_pct,
       ROUND((ganancia / LAG(ganancia) OVER (ORDER BY anio) - 1) * 100, 2)  AS var_ganancia_pct
FROM anual
ORDER BY anio;
