# Pregunta 4. Segmentación avanzada de clientes mediante RFM

## Enunciado

Construya un análisis RFM (Recency, Frequency, Monetary) para identificar los perfiles de clientes: recency (días desde la última compra respecto a la fecha máxima del dataset), frequency (órdenes únicas), monetary (ventas acumuladas), clasificación mediante puntuaciones RFM e identificación de clientes de alto valor, recurrentes y en riesgo de abandono. Defina y justifique los criterios de segmentación.

## Estrategia de solución

El análisis RFM clasifica a los clientes según tres preguntas:

- **R (Recency):** ¿hace cuánto compró por última vez?
- **F (Frequency):** ¿cuántas veces compró?
- **M (Monetary):** ¿cuánto dinero gastó en total?

Pasos que seguí:

1. **Fecha de referencia:** usé la última fecha del dataset, **2017-12-30**, y la calculé con `MAX(order_date)` para no escribirla a mano.
2. **Cálculo por cliente:**
   - Recency = días entre la fecha de referencia y su última compra (`DATEDIFF`).
   - Frequency = cantidad de **órdenes** distintas (`COUNT(DISTINCT order_id)`). Cuento órdenes y no filas, porque una orden puede tener varios productos.
   - Monetary = suma de sus ventas.
3. **Puntaje del 1 al 5:** ordené a los clientes y los dividí en 5 grupos iguales (quintiles). El 5 es lo mejor y el 1 lo peor. En Recency es al revés: **menos días = 5**, porque es mejor que haya comprado hace poco.
   - Usé `CUME_DIST()` en lugar de `NTILE()`. Probé `NTILE` primero, pero al dividir en grupos iguales puede poner a dos clientes con la misma cantidad de órdenes en grupos distintos, lo que no es justo. Con `CUME_DIST`, si dos clientes tienen el mismo valor, reciben el mismo puntaje.
4. **Segmentos:** con los tres puntajes armé reglas para agrupar a los clientes:

| Segmento | Regla | Por qué |
|----------|-------|---------|
| 1 Campeones (alto valor) | R ≥ 4, F ≥ 4, M ≥ 4 | Compraron hace poco, compran seguido y gastan mucho |
| 2 Leales / recurrentes | R ≥ 3, F ≥ 4 | Compran muy seguido y siguen activos |
| 3 En riesgo de abandono | R ≤ 2 y (F ≥ 4 o M ≥ 4) | Eran buenos clientes, pero hace más de 100 días que no compran |
| 4 Nuevos / prometedores | R ≥ 4, F ≤ 2 | Compraron hace poco, pero todavía pocas veces |
| 5 Potenciales | R ≥ 3, M ≥ 3 | Están activos y gastan bastante; se les puede vender más |
| 7 Perdidos / hibernando | R ≤ 2, F ≤ 2, M ≤ 2 | Hace mucho que no compran y compraban poco |
| 6 Necesitan atención | El resto | Perfil intermedio |

El orden de las reglas importa: si un cliente cumple la regla 1, ya no se evalúan las demás.

5. Guardé el resultado en la tabla `rfm_clientes` para poder usarlo después.

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

Se analizaron **793 clientes**.

### Qué valores corresponden a cada puntaje

| Puntaje | Recency (días) | Frequency (órdenes) | Monetary (USD) |
|:-------:|----------------|---------------------|----------------|
| 5 | 0 – 26 | 9 – 17 | 4 282.94 – 25 043.05 |
| 4 | 27 – 53 | 7 – 8 | 2 749.88 – 4 282.18 |
| 3 | 54 – 103 | 5 – 6 | 1 739.69 – 2 744.74 |
| 2 | 104 – 225 | 4 | 959.48 – 1 738.41 |
| 1 | 226 – 1 165 | 1 – 3 | 4.83 – 955.12 |

### Resumen de cada segmento

| Segmento | Clientes | % clientes | Días sin comprar (prom.) | Órdenes (prom.) | Gasto (prom.) | % de las ventas | Ganancia |
|----------|---------:|-----------:|-------------------------:|----------------:|--------------:|----------------:|---------:|
| 1 Campeones (alto valor) | 111 | 14.00 | 24.7 | 9.21 | 5 221.45 | 25.23 | 68 556.46 |
| 2 Leales / recurrentes | 157 | 19.80 | 52.5 | 8.24 | 2 745.02 | 18.76 | 44 353.76 |
| 3 En riesgo de abandono | 126 | 15.89 | 240.3 | 7.49 | 4 419.12 | 24.24 | 90 354.31 |
| 4 Nuevos / prometedores | 47 | 5.93 | 26.0 | 3.40 | 1 453.17 | 2.97 | 13 551.13 |
| 5 Potenciales | 87 | 10.97 | 45.6 | 5.34 | 4 198.12 | 15.90 | 42 520.80 |
| 6 Necesitan atención | 175 | 22.07 | 183.9 | 4.94 | 1 313.17 | 10.00 | 25 168.96 |
| 7 Perdidos / hibernando | 90 | 11.35 | 419.7 | 2.90 | 738.94 | 2.90 | 1 891.76 |

### Clientes de alto valor (los 5 que más gastaron)

| Cliente | Días sin comprar | Órdenes | Gasto | RFM |
|---------|-----------------:|--------:|------:|:---:|
| Adrian Barton (AB-10105) | 41 | 10 | 14 473.57 | 455 |
| Ken Lonsdale (KL-16645) | 47 | 12 | 14 175.23 | 455 |
| Sanjit Engle (SE-20110) | 9 | 11 | 12 209.44 | 555 |
| Greg Tran (GT-14710) | 36 | 11 | 11 820.12 | 455 |
| Maria Etezadi (ME-17320) | 42 | 10 | 10 663.73 | 455 |

### Clientes más recurrentes

La clienta que más veces compró es **Emily Phan** (EP-13915), con **17 órdenes**; su última compra fue hace 12 días (RFM 555). Después hay siete clientes con 13 órdenes, pero dos de ellos (Noel Staavos y Erin Ashbrook) ya llevan más de 150 días sin comprar.

### Clientes en riesgo de abandono (los 5 que más gastaban)

| Cliente | Días sin comprar | Órdenes | Gasto | Última compra | RFM |
|---------|-----------------:|--------:|------:|---------------|:---:|
| Tamara Chand (TC-20980) | 399 | 5 | 19 052.22 | 2016-11-26 | 135 |
| Sanjit Chand (SC-20095) | 349 | 9 | 14 142.33 | 2017-01-15 | 155 |
| Becky Martin (BM-11140) | 307 | 4 | 11 789.63 | 2017-02-26 | 125 |
| Caroline Jumper (CJ-12010) | 189 | 8 | 11 164.97 | 2017-06-24 | 245 |
| Clay Ludtke (CL-12565) | 284 | 12 | 10 880.55 | 2017-03-21 | 155 |

### Comparación con el segmento comercial

| Segmento | Clientes | Campeones | Leales | En riesgo | Puntaje RFM promedio |
|----------|---------:|----------:|-------:|----------:|---------------------:|
| Consumer | 409 | 55 | 80 | 63 | 9.27 |
| Corporate | 236 | 38 | 44 | 40 | 9.43 |
| Home Office | 148 | 18 | 33 | 23 | 9.13 |

## Interpretación técnica

- **Pocos clientes generan mucho:** los Campeones son solo el 14 % de los clientes, pero hacen el 25 % de las ventas. Sumando a los Leales, un tercio de los clientes genera casi la mitad de las ventas.
- **Lo que más me llamó la atención fue el grupo en riesgo:** son 126 clientes que en promedio llevan 240 días sin comprar, pero antes compraban seguido y gastaban mucho. Juntos representan el 24 % de las ventas y **son el grupo que más ganancia dejó (90 354 USD), incluso más que los Campeones**. Si la empresa los pierde, es lo que más le dolería. Por ejemplo, Tamara Chand gastó más de 19 000 USD y no compra desde noviembre de 2016.
- En Frequency se nota por qué usé `CUME_DIST`: el puntaje 2 corresponde solo a los clientes con exactamente 4 órdenes. Con `NTILE`, algunos de esos clientes habrían quedado con 2 y otros con 3 sin ninguna razón.
- Los tres segmentos comerciales (Consumer, Corporate y Home Office) tienen puntajes RFM casi iguales. Eso quiere decir que el RFM muestra diferencias entre clientes que la columna `segment` no muestra.

## Conclusión

Con el RFM pude separar a los clientes en 7 grupos con reglas claras. Lo más urgente es **recuperar a los clientes en riesgo**, porque representan una cuarta parte de las ventas y son los que más ganancia dejaban. Después habría que cuidar a los Campeones y Leales, y tratar de que los Nuevos y Potenciales compren más seguido.
