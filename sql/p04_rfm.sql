-- =====================================================================
-- PREGUNTA 4 - Segmentacion de clientes mediante RFM
-- Recency  : dias desde la ultima compra hasta la fecha maxima del dataset
-- Frequency: cantidad de ordenes unicas
-- Monetary : ventas acumuladas
-- Puntuacion 1-5 por quintiles con CUME_DIST (empates = mismo puntaje)
-- =====================================================================

USE superstore_db;

-- ---------------------------------------------------------------------
-- 4.1 Tabla RFM por cliente (se materializa para reutilizarla)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS rfm_clientes;

CREATE TABLE rfm_clientes STORED AS ORC AS
WITH fecha_ref AS (
    SELECT MAX(order_date) AS fecha_max FROM superstore
),
base AS (
    SELECT s.customer_id,
           MAX(s.customer_name)                       AS customer_name,
           MAX(s.segment)                             AS segment,
           DATEDIFF(MAX(f.fecha_max), MAX(s.order_date)) AS recency,
           COUNT(DISTINCT s.order_id)                 AS frequency,
           ROUND(SUM(s.sales), 2)                     AS monetary,
           ROUND(SUM(s.profit), 2)                    AS ganancia,
           MIN(s.order_date)                          AS primera_compra,
           MAX(s.order_date)                          AS ultima_compra
    FROM superstore s
    CROSS JOIN fecha_ref f
    GROUP BY s.customer_id
),
puntaje AS (
    SELECT b.*,
           -- menos dias = mejor; se ordena DESC para que el mas reciente tenga 5
           CAST(CEIL(CUME_DIST() OVER (ORDER BY recency DESC) * 5) AS INT) AS r_score,
           CAST(CEIL(CUME_DIST() OVER (ORDER BY frequency)    * 5) AS INT) AS f_score,
           CAST(CEIL(CUME_DIST() OVER (ORDER BY monetary)     * 5) AS INT) AS m_score
    FROM base b
)
SELECT p.*,
       CONCAT(r_score, f_score, m_score)  AS rfm_codigo,
       r_score + f_score + m_score        AS rfm_total,
       CASE
           WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN '1 Campeones (alto valor)'
           WHEN r_score >= 3 AND f_score >= 4                  THEN '2 Leales / recurrentes'
           WHEN r_score <= 2 AND (f_score >= 4 OR m_score >= 4) THEN '3 En riesgo de abandono'
           WHEN r_score >= 4 AND f_score <= 2                  THEN '4 Nuevos / prometedores'
           WHEN r_score >= 3 AND m_score >= 3                  THEN '5 Potenciales'
           WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN '7 Perdidos / hibernando'
           ELSE '6 Necesitan atencion'
       END AS segmento_rfm
FROM puntaje p;

SELECT COUNT(*) AS clientes, MAX(ultima_compra) AS fecha_referencia FROM rfm_clientes;

-- ---------------------------------------------------------------------
-- 4.2 Umbrales resultantes de cada puntaje (justificacion de cortes)
-- ---------------------------------------------------------------------
SELECT 'R' AS dimension, r_score AS score, COUNT(*) AS clientes,
       MIN(recency) AS valor_min, MAX(recency) AS valor_max
FROM rfm_clientes GROUP BY r_score
UNION ALL
SELECT 'F', f_score, COUNT(*), MIN(frequency), MAX(frequency)
FROM rfm_clientes GROUP BY f_score
UNION ALL
SELECT 'M', m_score, COUNT(*), MIN(monetary), MAX(monetary)
FROM rfm_clientes GROUP BY m_score
ORDER BY dimension, score;

-- ---------------------------------------------------------------------
-- 4.3 Perfil de cada segmento
-- ---------------------------------------------------------------------
SELECT segmento_rfm,
       COUNT(*)                                                       AS clientes,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)             AS pct_clientes,
       ROUND(AVG(recency), 1)                                         AS recency_prom,
       ROUND(AVG(frequency), 2)                                       AS frequency_prom,
       ROUND(AVG(monetary), 2)                                        AS monetary_prom,
       ROUND(SUM(monetary), 2)                                        AS ventas_segmento,
       ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER (), 2)   AS pct_ventas,
       ROUND(SUM(ganancia), 2)                                        AS ganancia_segmento
FROM rfm_clientes
GROUP BY segmento_rfm
ORDER BY segmento_rfm;

-- ---------------------------------------------------------------------
-- 4.4 Top 10 clientes de alto valor
-- ---------------------------------------------------------------------
SELECT customer_id, customer_name, segment, recency, frequency, monetary, ganancia, rfm_codigo
FROM rfm_clientes
WHERE segmento_rfm = '1 Campeones (alto valor)'
ORDER BY monetary DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- 4.5 Top 10 clientes recurrentes (mayor frecuencia)
-- ---------------------------------------------------------------------
SELECT customer_id, customer_name, recency, frequency, monetary, rfm_codigo, segmento_rfm
FROM rfm_clientes
ORDER BY frequency DESC, monetary DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- 4.6 Top 10 clientes en riesgo de abandono (mas valor en juego)
-- ---------------------------------------------------------------------
SELECT customer_id, customer_name, recency, frequency, monetary, ultima_compra, rfm_codigo
FROM rfm_clientes
WHERE segmento_rfm = '3 En riesgo de abandono'
ORDER BY monetary DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- 4.7 Segmento RFM vs segmento comercial
-- ---------------------------------------------------------------------
SELECT segment,
       COUNT(*)                                                     AS clientes,
       SUM(IF(segmento_rfm = '1 Campeones (alto valor)', 1, 0))     AS campeones,
       SUM(IF(segmento_rfm = '2 Leales / recurrentes', 1, 0))       AS leales,
       SUM(IF(segmento_rfm = '3 En riesgo de abandono', 1, 0))      AS en_riesgo,
       ROUND(AVG(rfm_total), 2)                                     AS rfm_total_prom
FROM rfm_clientes
GROUP BY segment
ORDER BY segment;
