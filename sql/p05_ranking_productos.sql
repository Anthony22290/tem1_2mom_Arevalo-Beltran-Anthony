-- =====================================================================
-- PREGUNTA 5 - Ranking de productos segun rentabilidad
-- Tecnicas: RANK(), DENSE_RANK(), ROW_NUMBER() y SUM() OVER acumulado
-- Producto = product_id + product_name (32 product_id tienen 2 nombres,
-- ver Pregunta 2; asi no se mezclan articulos distintos)
-- =====================================================================

USE superstore_db;

-- ---------------------------------------------------------------------
-- 5.1 Metricas por producto (se materializan para las consultas)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS producto_metricas;

CREATE TABLE producto_metricas STORED AS ORC AS
SELECT category,
       sub_category,
       product_id,
       product_name,
       COUNT(*)                         AS lineas,
       SUM(quantity)                    AS unidades,
       ROUND(SUM(sales), 2)             AS ventas,
       ROUND(SUM(profit), 2)            AS ganancia,
       ROUND(SUM(profit) / SUM(sales) * 100, 2) AS margen_pct,
       ROUND(AVG(discount) * 100, 2)    AS descuento_prom_pct
FROM superstore
GROUP BY category, sub_category, product_id, product_name;

SELECT COUNT(*)                         AS productos,
       SUM(IF(ganancia < 0, 1, 0))      AS productos_con_perdida,
       ROUND(SUM(IF(ganancia < 0, ganancia, 0)), 2) AS perdida_total
FROM producto_metricas;

-- ---------------------------------------------------------------------
-- 5.2 Top 5 productos con mayor ganancia acumulada POR CATEGORIA
--     + posicion en la categoria (RANK y DENSE_RANK)
--     + ganancia acumulada dentro de la categoria (SUM OVER)
-- ---------------------------------------------------------------------
WITH ranking AS (
    SELECT category, product_id, product_name, ventas, ganancia, margen_pct,
           RANK()       OVER (PARTITION BY category ORDER BY ganancia DESC) AS rank_cat,
           DENSE_RANK() OVER (PARTITION BY category ORDER BY ganancia DESC) AS dense_rank_cat,
           COUNT(*)     OVER (PARTITION BY category)                        AS productos_cat,
           SUM(ganancia) OVER (PARTITION BY category ORDER BY ganancia DESC
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ganancia_acumulada,
           SUM(ganancia) OVER (PARTITION BY category)                       AS ganancia_cat
    FROM producto_metricas
)
SELECT category, rank_cat, dense_rank_cat, productos_cat, product_id, product_name,
       ventas, ganancia, margen_pct,
       ROUND(ganancia_acumulada, 2)                         AS ganancia_acumulada,
       ROUND(ganancia_acumulada / ganancia_cat * 100, 2)    AS pct_acum_categoria
FROM ranking
WHERE rank_cat <= 5
ORDER BY category, rank_cat;

-- ---------------------------------------------------------------------
-- 5.3 Top 5 productos con mayor volumen de ventas (USD), con su
--     ranking por unidades para comparar
-- ---------------------------------------------------------------------
WITH ranking AS (
    SELECT category, product_id, product_name, unidades, ventas, ganancia, margen_pct,
           RANK()       OVER (ORDER BY ventas DESC)   AS rank_ventas,
           DENSE_RANK() OVER (ORDER BY unidades DESC) AS dense_rank_unidades,
           SUM(ventas)  OVER (ORDER BY ventas DESC
                              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ventas_acumuladas,
           SUM(ventas)  OVER ()                       AS ventas_totales
    FROM producto_metricas
)
SELECT rank_ventas, category, product_name, ventas, unidades, dense_rank_unidades,
       ganancia, margen_pct,
       ROUND(ventas_acumuladas / ventas_totales * 100, 2) AS pct_acum_ventas
FROM ranking
WHERE rank_ventas <= 5
ORDER BY rank_ventas;

-- Top 5 por unidades vendidas (DENSE_RANK por los empates)
WITH ranking AS (
    SELECT category, product_name, unidades, ventas, ganancia,
           DENSE_RANK() OVER (ORDER BY unidades DESC) AS dense_rank_unidades,
           RANK()       OVER (ORDER BY unidades DESC) AS rank_unidades
    FROM producto_metricas
)
SELECT dense_rank_unidades, rank_unidades, category, product_name, unidades, ventas, ganancia
FROM ranking
WHERE dense_rank_unidades <= 5
ORDER BY dense_rank_unidades, ventas DESC;

-- ---------------------------------------------------------------------
-- 5.4 Los 5 productos con menor rentabilidad (mayor perdida acumulada)
-- ---------------------------------------------------------------------
WITH ranking AS (
    SELECT category, sub_category, product_id, product_name, ventas, ganancia,
           margen_pct, descuento_prom_pct,
           RANK() OVER (ORDER BY ganancia ASC)                          AS rank_peor,
           RANK() OVER (PARTITION BY category ORDER BY ganancia DESC)   AS rank_cat,
           COUNT(*) OVER (PARTITION BY category)                        AS productos_cat
    FROM producto_metricas
)
SELECT rank_peor, category, sub_category, product_name, ventas, ganancia, margen_pct,
       descuento_prom_pct, CONCAT(rank_cat, ' de ', productos_cat) AS posicion_en_categoria
FROM ranking
WHERE rank_peor <= 5
ORDER BY rank_peor;

-- Los 5 con peor margen (%) entre productos con ventas relevantes (>= 1000 USD)
WITH ranking AS (
    SELECT category, product_name, ventas, ganancia, margen_pct, descuento_prom_pct,
           RANK() OVER (ORDER BY margen_pct ASC) AS rank_margen
    FROM producto_metricas
    WHERE ventas >= 1000
)
SELECT rank_margen, category, product_name, ventas, ganancia, margen_pct, descuento_prom_pct
FROM ranking
WHERE rank_margen <= 5
ORDER BY rank_margen;

-- ---------------------------------------------------------------------
-- 5.5 Margen y posicion de CADA producto dentro de su categoria
--     Se guarda el ranking completo (1 894 productos) en una tabla y se
--     muestran los 3 mejores y los 3 peores de cada categoria.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS producto_ranking;

CREATE TABLE producto_ranking STORED AS ORC AS
SELECT category, sub_category, product_id, product_name, unidades, ventas, ganancia, margen_pct,
       RANK()       OVER (PARTITION BY category ORDER BY ganancia DESC)   AS rank_ganancia,
       DENSE_RANK() OVER (PARTITION BY category ORDER BY margen_pct DESC) AS dense_rank_margen,
       COUNT(*)     OVER (PARTITION BY category)                          AS productos_cat,
       ROUND(PERCENT_RANK() OVER (PARTITION BY category ORDER BY ganancia DESC) * 100, 1) AS percentil,
       ROUND(SUM(ganancia) OVER (PARTITION BY category ORDER BY ganancia DESC
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS ganancia_acumulada
FROM producto_metricas;

SELECT COUNT(*) AS productos_rankeados FROM producto_ranking;

SELECT category, rank_ganancia, dense_rank_margen, productos_cat, percentil,
       product_name, ventas, ganancia, margen_pct, ganancia_acumulada
FROM producto_ranking
WHERE rank_ganancia <= 3 OR rank_ganancia > productos_cat - 3
ORDER BY category, rank_ganancia;

-- ---------------------------------------------------------------------
-- 5.6 Resumen por categoria
-- ---------------------------------------------------------------------
SELECT category,
       COUNT(*)                                          AS productos,
       ROUND(SUM(ventas), 2)                             AS ventas,
       ROUND(SUM(ganancia), 2)                           AS ganancia,
       ROUND(SUM(ganancia) / SUM(ventas) * 100, 2)       AS margen_pct,
       SUM(IF(ganancia < 0, 1, 0))                       AS productos_con_perdida,
       ROUND(SUM(IF(ganancia < 0, 1, 0)) * 100.0 / COUNT(*), 2) AS pct_con_perdida
FROM producto_metricas
GROUP BY category
ORDER BY ganancia DESC;
