# Pregunta 3. Análisis de evolución comercial por región

## Enunciado

Determine la evolución de las ventas y ganancias por región durante los años disponibles: ventas totales por región y año, ganancia total por región y año, margen de rentabilidad, variación porcentual respecto al año anterior e identificación de la región con mejor y peor desempeño comercial. Utilice CTE y funciones de ventana.

## Estrategia de solución

1. **CTE `region_anio`:** agrega ventas, ganancia y órdenes por `region` y `order_year`. Como la tabla está particionada por `order_year`, agrupar por la columna de partición no exige leer ni calcular la fecha.
2. **CTE `con_lag`:** `LAG() OVER (PARTITION BY region ORDER BY anio)` trae el valor del año anterior **de la misma región**, para calcular la variación porcentual.
3. **Margen:** `ganancia / ventas * 100`.
4. **Variación de la ganancia:** se divide por `ABS(ganancia_anterior)` para que el signo indique bien la dirección si alguna ganancia anterior fuera negativa.
5. **`RANK() OVER (PARTITION BY anio ...)`:** posición de cada región dentro de cada año.
6. **Desempeño acumulado:** criterio principal la **ganancia acumulada 2014–2017** (lo que la región realmente aporta). Se complementa con el margen, la participación (`SUM() OVER ()` como total general) y el crecimiento anual compuesto de ventas (CAGR) usando `FIRST_VALUE` / `LAST_VALUE`.

## Consulta HiveQL desarrollada

Script completo: [`sql/p03_evolucion_region.sql`](../sql/p03_evolucion_region.sql)

```sql
WITH region_anio AS (
    SELECT region, order_year AS anio,
           SUM(sales) AS ventas, SUM(profit) AS ganancia,
           COUNT(DISTINCT order_id) AS ordenes
    FROM superstore
    GROUP BY region, order_year
),
con_lag AS (
    SELECT region, anio, ventas, ganancia, ordenes,
           ganancia / ventas * 100                                AS margen,
           LAG(ventas)   OVER (PARTITION BY region ORDER BY anio) AS ventas_anio_ant,
           LAG(ganancia) OVER (PARTITION BY region ORDER BY anio) AS ganancia_anio_ant
    FROM region_anio
)
SELECT region, anio, ordenes,
       ROUND(ventas, 2) AS ventas, ROUND(ganancia, 2) AS ganancia,
       ROUND(margen, 2) AS margen_pct,
       ROUND((ventas - ventas_anio_ant) / ventas_anio_ant * 100, 2)            AS var_ventas_pct,
       ROUND((ganancia - ganancia_anio_ant) / ABS(ganancia_anio_ant) * 100, 2) AS var_ganancia_pct,
       RANK() OVER (PARTITION BY anio ORDER BY ventas DESC)   AS rank_ventas_anio,
       RANK() OVER (PARTITION BY anio ORDER BY ganancia DESC) AS rank_ganancia_anio
FROM con_lag
ORDER BY region, anio;
```

## Evidencia de ejecución

[`evidencias/p03_evolucion_region.txt`](../evidencias/p03_evolucion_region.txt)

## Resultado obtenido

### Evolución por región y año (USD)

| Región | Año | Ventas | Ganancia | Margen % | Var. ventas % | Var. ganancia % | Rank ventas | Rank ganancia |
|--------|-----|-------:|---------:|---------:|--------------:|----------------:|:-:|:-:|
| Central | 2014 | 103 838.16 | 539.55 | 0.52 | – | – | 4 | 4 |
| Central | 2015 | 102 874.22 | 11 716.80 | 11.39 | −0.93 | 2 071.57 | 3 | 3 |
| Central | 2016 | 147 429.38 | 19 899.16 | 13.50 | 43.31 | 69.83 | 3 | 3 |
| Central | 2017 | 147 098.13 | 7 550.84 | 5.13 | −0.22 | −62.05 | 3 | 4 |
| East | 2014 | 128 680.46 | 17 059.61 | 13.26 | – | – | 2 | 2 |
| East | 2015 | 156 332.06 | 21 091.01 | 13.49 | 21.49 | 23.63 | 1 | 1 |
| East | 2016 | 180 685.82 | 20 141.60 | 11.15 | 15.58 | −4.50 | 2 | 2 |
| East | 2017 | 213 082.90 | 33 230.56 | 15.60 | 17.93 | 64.98 | 2 | 2 |
| South | 2014 | 103 845.84 | 11 879.12 | 11.44 | – | – | 3 | 3 |
| South | 2015 | 71 359.98 | 8 318.59 | 11.66 | −31.28 | −29.97 | 4 | 4 |
| South | 2016 | 93 610.22 | 17 702.81 | 18.91 | 31.18 | 112.81 | 4 | 4 |
| South | 2017 | 122 905.86 | 8 848.91 | 7.20 | 31.30 | −50.01 | 4 | 3 |
| West | 2014 | 147 883.03 | 20 065.69 | 13.57 | – | – | 1 | 1 |
| West | 2015 | 139 966.25 | 20 492.19 | 14.64 | −5.35 | 2.13 | 2 | 2 |
| West | 2016 | 187 480.18 | 24 051.61 | 12.83 | 33.95 | 17.37 | 1 | 1 |
| West | 2017 | 250 128.37 | 43 808.96 | 17.51 | 33.42 | 82.15 | 1 | 1 |

### Mejor y peor región por año (según ganancia)

| Año | Mejor región | Ganancia | Peor región | Ganancia |
|-----|--------------|---------:|-------------|---------:|
| 2014 | West | 20 065.69 | Central | 539.55 |
| 2015 | East | 21 091.01 | South | 8 318.59 |
| 2016 | West | 24 051.61 | South | 17 702.81 |
| 2017 | West | 43 808.96 | Central | 7 550.84 |

### Desempeño acumulado 2014–2017

| Región | Ventas | Ganancia | Margen % | % de ventas | % de ganancia | CAGR ventas % | Clasificación |
|--------|-------:|---------:|---------:|------------:|--------------:|--------------:|---------------|
| West | 725 457.82 | 108 418.45 | 14.94 | 31.58 | 37.86 | 19.15 | **Mejor desempeño** |
| East | 678 781.24 | 91 522.78 | 13.48 | 29.55 | 31.96 | 18.31 | – |
| South | 391 721.91 | 46 749.43 | 11.93 | 17.05 | 16.32 | 5.78 | – |
| Central | 501 239.89 | 39 706.36 | 7.92 | 21.82 | 13.86 | 12.31 | **Peor desempeño** |

### Total de la empresa

| Año | Ventas | Ganancia | Margen % | Var. ventas % | Var. ganancia % |
|-----|-------:|---------:|---------:|--------------:|----------------:|
| 2014 | 484 247.50 | 49 543.97 | 10.23 | – | – |
| 2015 | 470 532.51 | 61 618.60 | 13.10 | −2.83 | 24.37 |
| 2016 | 609 205.60 | 81 795.17 | 13.43 | 29.47 | 32.74 |
| 2017 | 733 215.26 | 93 439.27 | 12.74 | 20.36 | 14.24 |

## Interpretación técnica

- **West es la región con mejor desempeño** en todas las dimensiones: mayores ventas acumuladas, mayor ganancia (37.9 % del total con el 31.6 % de las ventas), mejor margen (14.9 %) y mayor crecimiento (19.2 % anual). En 2017 creció 33 % en ventas y 82 % en ganancia.
- **East** sigue de cerca a West y tiene un comportamiento estable: crece en ventas todos los años y mantiene márgenes de 11 % a 16 %.
- **Central es la de peor desempeño, aunque no es la que menos vende:** vende 28 % más que South, pero gana 15 % menos, porque su margen es el más bajo (7.9 %). Su ganancia es muy irregular: 0.5 % de margen en 2014, 13.5 % en 2016 y vuelve a caer a 5.1 % en 2017 con ventas prácticamente iguales al año anterior. Que la venta sea estable y la ganancia caiga indica un problema de rentabilidad (precios o descuentos) y no de volumen. Esto se analiza en la Pregunta 6.
- **South** es la región más pequeña y la más volátil: cae 31 % en 2015, se recupera con su mejor margen (18.9 %) en 2016 y en 2017 vuelve a perder margen aunque las ventas suben 31 %.
- **A nivel empresa** las ventas crecen 51 % entre 2014 y 2017, pero el margen se estanca en torno al 13 %. Las variaciones extremas, como +2 071 % en Central 2015, se explican por una base muy pequeña (539 USD en 2014), así que deben leerse junto al valor absoluto.

## Conclusión

West es la región líder y la que más contribuye a la ganancia. Central es la de peor desempeño: tiene un volumen de ventas aceptable, pero la rentabilidad más baja y la más inestable. La empresa crece en ventas sin mejorar su margen, lo que sugiere revisar la política comercial de Central y South antes de seguir aumentando el volumen.
