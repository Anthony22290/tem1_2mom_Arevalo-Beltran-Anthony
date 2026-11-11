# Pregunta 4. Segmentación avanzada de clientes mediante RFM

## Enunciado

Construya un análisis RFM (Recency, Frequency, Monetary) para identificar los perfiles de clientes: recency (días desde la última compra respecto a la fecha máxima del dataset), frequency (órdenes únicas), monetary (ventas acumuladas), clasificación mediante puntuaciones RFM e identificación de clientes de alto valor, recurrentes y en riesgo de abandono. Defina y justifique los criterios de segmentación.

## Estrategia de solución

1. **Fecha de referencia:** `MAX(order_date)` del dataset = **2017-12-30**. Se calcula en un CTE y se cruza con `CROSS JOIN` para no escribirla a mano.
2. **Métricas por cliente** (`GROUP BY customer_id`):
   - `recency = DATEDIFF(fecha_max, MAX(order_date))`
   - `frequency = COUNT(DISTINCT order_id)`: se cuentan **órdenes**, no líneas, porque una orden tiene varias líneas.
   - `monetary = SUM(sales)`
3. **Puntaje de 1 a 5 por quintiles** con `CEIL(CUME_DIST() OVER (ORDER BY x) * 5)`:
   - Se usa `CUME_DIST` y no `NTILE`, porque `NTILE` reparte los empates entre grupos distintos (dos clientes con 4 órdenes podrían quedar uno con F=2 y otro con F=3). Con `CUME_DIST` los clientes con el mismo valor reciben el mismo puntaje. Esto importa en *frequency*, que solo toma 17 valores distintos.
   - En **recency** se ordena `DESC` para que **menos días = puntaje 5**.
4. **Reglas de segmentación** (se evalúan en orden con `CASE`):

| Segmento | Regla | Justificación |
|----------|-------|---------------|
| 1 Campeones (alto valor) | R ≥ 4, F ≥ 4, M ≥ 4 | Compraron hace poco, compran seguido y gastan mucho: están en el 40 % superior de las tres dimensiones |
| 2 Leales / recurrentes | R ≥ 3, F ≥ 4 | Compran con mucha frecuencia y siguen activos, aunque no gasten tanto |
| 3 En riesgo de abandono | R ≤ 2, (F ≥ 4 o M ≥ 4) | **Fueron clientes valiosos** (frecuentes o de alto gasto), pero hace más de 103 días que no compran |
| 4 Nuevos / prometedores | R ≥ 4, F ≤ 2 | Compra reciente pero con pocas órdenes |
| 5 Potenciales | R ≥ 3, M ≥ 3 | Activos y con gasto medio o alto que se puede aumentar |
| 7 Perdidos / hibernando | R ≤ 2, F ≤ 2, M ≤ 2 | Bajo en todo y sin compras recientes |
| 6 Necesitan atención | resto | Perfil intermedio |

5. El resultado se materializa en la tabla `rfm_clientes` (ORC) para poder reutilizarlo.

## Consulta HiveQL desarrollada

Script completo: [`sql/p04_rfm.sql`](../sql/p04_rfm.sql)

```sql
CREATE TABLE rfm_clientes STORED AS ORC AS
WITH fecha_ref AS (
    SELECT MAX(order_date) AS fecha_max FROM superstore
),
base AS (
    SELECT s.customer_id,
           DATEDIFF(MAX(f.fecha_max), MAX(s.order_date)) AS recency,
           COUNT(DISTINCT s.order_id)                    AS frequency,
           ROUND(SUM(s.sales), 2)                        AS monetary, ...
    FROM superstore s CROSS JOIN fecha_ref f
    GROUP BY s.customer_id
),
puntaje AS (
    SELECT b.*,
           CAST(CEIL(CUME_DIST() OVER (ORDER BY recency DESC) * 5) AS INT) AS r_score,
           CAST(CEIL(CUME_DIST() OVER (ORDER BY frequency)    * 5) AS INT) AS f_score,
           CAST(CEIL(CUME_DIST() OVER (ORDER BY monetary)     * 5) AS INT) AS m_score
    FROM base b
)
SELECT p.*, CONCAT(r_score, f_score, m_score) AS rfm_codigo,
       CASE WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN '1 Campeones (alto valor)'
            WHEN r_score >= 3 AND f_score >= 4                  THEN '2 Leales / recurrentes'
            WHEN r_score <= 2 AND (f_score >= 4 OR m_score >= 4) THEN '3 En riesgo de abandono'
            ... END AS segmento_rfm
FROM puntaje p;
```

## Evidencia de ejecución

[`evidencias/p04_rfm.txt`](../evidencias/p04_rfm.txt)

## Resultado obtenido

**793 clientes** evaluados con fecha de referencia 2017-12-30.

### Umbrales de cada puntaje

| Score | Recency (días) | Frequency (órdenes) | Monetary (USD) |
|:-----:|----------------|---------------------|----------------|
| 5 | 0 – 26 | 9 – 17 | 4 282.94 – 25 043.05 |
| 4 | 27 – 53 | 7 – 8 | 2 749.88 – 4 282.18 |
| 3 | 54 – 103 | 5 – 6 | 1 739.69 – 2 744.74 |
| 2 | 104 – 225 | 4 | 959.48 – 1 738.41 |
| 1 | 226 – 1 165 | 1 – 3 | 4.83 – 955.12 |

### Perfil de los segmentos

| Segmento | Clientes | % clientes | Recency prom. | Frequency prom. | Monetary prom. | % de ventas | Ganancia |
|----------|---------:|-----------:|--------------:|----------------:|---------------:|------------:|---------:|
| 1 Campeones (alto valor) | 111 | 14.00 | 24.7 | 9.21 | 5 221.45 | 25.23 | 68 556.46 |
| 2 Leales / recurrentes | 157 | 19.80 | 52.5 | 8.24 | 2 745.02 | 18.76 | 44 353.76 |
| 3 En riesgo de abandono | 126 | 15.89 | 240.3 | 7.49 | 4 419.12 | 24.24 | 90 354.31 |
| 4 Nuevos / prometedores | 47 | 5.93 | 26.0 | 3.40 | 1 453.17 | 2.97 | 13 551.13 |
| 5 Potenciales | 87 | 10.97 | 45.6 | 5.34 | 4 198.12 | 15.90 | 42 520.80 |
| 6 Necesitan atención | 175 | 22.07 | 183.9 | 4.94 | 1 313.17 | 10.00 | 25 168.96 |
| 7 Perdidos / hibernando | 90 | 11.35 | 419.7 | 2.90 | 738.94 | 2.90 | 1 891.76 |

### Clientes de alto valor (top 5 por monto)

| Cliente | Recency | Frequency | Monetary | RFM |
|---------|--------:|----------:|---------:|:---:|
| Adrian Barton (AB-10105) | 41 | 10 | 14 473.57 | 455 |
| Ken Lonsdale (KL-16645) | 47 | 12 | 14 175.23 | 455 |
| Sanjit Engle (SE-20110) | 9 | 11 | 12 209.44 | 555 |
| Greg Tran (GT-14710) | 36 | 11 | 11 820.12 | 455 |
| Maria Etezadi (ME-17320) | 42 | 10 | 10 663.73 | 455 |

### Clientes más recurrentes

Emily Phan (EP-13915) es la clienta con más órdenes: **17**, la última hace 12 días (RFM 555). Le siguen siete clientes con 13 órdenes; dos de ellos (Noel Staavos y Erin Ashbrook) ya están en riesgo, con más de 150 días sin comprar.

### Clientes en riesgo de abandono (top 5 por monto en juego)

| Cliente | Recency | Frequency | Monetary | Última compra | RFM |
|---------|--------:|----------:|---------:|---------------|:---:|
| Tamara Chand (TC-20980) | 399 | 5 | 19 052.22 | 2016-11-26 | 135 |
| Sanjit Chand (SC-20095) | 349 | 9 | 14 142.33 | 2017-01-15 | 155 |
| Becky Martin (BM-11140) | 307 | 4 | 11 789.63 | 2017-02-26 | 125 |
| Caroline Jumper (CJ-12010) | 189 | 8 | 11 164.97 | 2017-06-24 | 245 |
| Clay Ludtke (CL-12565) | 284 | 12 | 10 880.55 | 2017-03-21 | 155 |

### Por segmento comercial

| Segmento | Clientes | Campeones | Leales | En riesgo | RFM total prom. |
|----------|---------:|----------:|-------:|----------:|----------------:|
| Consumer | 409 | 55 | 80 | 63 | 9.27 |
| Corporate | 236 | 38 | 44 | 40 | 9.43 |
| Home Office | 148 | 18 | 33 | 23 | 9.13 |

## Interpretación técnica

- **El valor está concentrado:** los Campeones son el 14 % de los clientes y generan el 25 % de las ventas. Junto con los Leales, un tercio de los clientes aporta el 44 % de la facturación.
- **El hallazgo más importante es el segmento en riesgo:** 126 clientes (16 %) que en promedio llevan 240 días sin comprar concentran el **24 % de las ventas** y la **mayor ganancia de todos los segmentos (90 354 USD)**, más que los propios Campeones. Son clientes que compraban seguido (7.5 órdenes en promedio) y con ticket alto. Perderlos tendría más impacto que cualquier otro segmento. Tamara Chand, por ejemplo, gastó más de 19 mil USD y no compra desde noviembre de 2016.
- **Frequency discrimina poco en los extremos:** el puntaje 2 corresponde a un solo valor (4 órdenes) y el 1 junta de 1 a 3 órdenes. Con `NTILE` estos empates se habrían repartido de forma arbitraria; con `CUME_DIST` cada valor tiene un único puntaje.
- **Los tres segmentos comerciales tienen perfiles RFM casi iguales** (promedio de 9.1 a 9.4 sobre 15), así que la segmentación RFM aporta información que la columna `segment` no da.

## Conclusión

El RFM separa a los clientes en 7 perfiles con reglas explícitas y reproducibles. La acción prioritaria es **retener al segmento en riesgo**: es la cuarta parte de las ventas y la mayor fuente de ganancia, y hoy está inactivo. Después vienen fidelizar a los Campeones y Leales, y convertir a los Potenciales y Nuevos en clientes recurrentes.
