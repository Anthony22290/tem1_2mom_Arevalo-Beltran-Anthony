# Pregunta 3. Análisis de evolución comercial por región

## Enunciado

Determine la evolución de las ventas y ganancias por región durante los años disponibles: ventas totales por región y año, ganancia total por región y año, margen de rentabilidad, variación porcentual respecto al año anterior e identificación de la región con mejor y peor desempeño comercial. Utilice CTE y funciones de ventana.

## Estrategia de solución

Dividí la consulta en pasos usando CTE (bloques `WITH`), que funcionan como tablas temporales dentro de la misma consulta:

1. **`region_anio`:** sumo las ventas, la ganancia y las órdenes de cada región en cada año.
2. **`con_lag`:** con `LAG()` traigo las ventas y la ganancia del año anterior **de la misma región**. `PARTITION BY region` hace que el cálculo se haga por separado en cada región.
3. Calculo el **margen** como `ganancia / ventas × 100`, es decir, cuánto se gana por cada 100 dólares vendidos.
4. Calculo la **variación** como `(año actual − año anterior) / año anterior × 100`.
5. Con `RANK()` veo qué posición ocupa cada región en cada año.

Para decidir cuál región tiene el **mejor y el peor desempeño** usé la **ganancia acumulada de 2014 a 2017**, porque es lo que realmente le queda a la empresa. También muestro el margen, el porcentaje que aporta cada región y cuánto crecieron las ventas por año en promedio (CAGR).

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

### Ventas y ganancias por región y año (USD)

| Región | Año | Ventas | Ganancia | Margen % | Var. ventas % | Var. ganancia % | Puesto ventas | Puesto ganancia |
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

En 2014 no hay variación porque no existe un año anterior para comparar.

### Mejor y peor región de cada año (según la ganancia)

| Año | Mejor región | Ganancia | Peor región | Ganancia |
|-----|--------------|---------:|-------------|---------:|
| 2014 | West | 20 065.69 | Central | 539.55 |
| 2015 | East | 21 091.01 | South | 8 318.59 |
| 2016 | West | 24 051.61 | South | 17 702.81 |
| 2017 | West | 43 808.96 | Central | 7 550.84 |

### Total 2014–2017

| Región | Ventas | Ganancia | Margen % | % de ventas | % de ganancia | Crecimiento anual de ventas % | Resultado |
|--------|-------:|---------:|---------:|------------:|--------------:|------------------------------:|-----------|
| West | 725 457.82 | 108 418.45 | 14.94 | 31.58 | 37.86 | 19.15 | **Mejor desempeño** |
| East | 678 781.24 | 91 522.78 | 13.48 | 29.55 | 31.96 | 18.31 | – |
| South | 391 721.91 | 46 749.43 | 11.93 | 17.05 | 16.32 | 5.78 | – |
| Central | 501 239.89 | 39 706.36 | 7.92 | 21.82 | 13.86 | 12.31 | **Peor desempeño** |

### Total de la empresa por año

| Año | Ventas | Ganancia | Margen % | Var. ventas % | Var. ganancia % |
|-----|-------:|---------:|---------:|--------------:|----------------:|
| 2014 | 484 247.50 | 49 543.97 | 10.23 | – | – |
| 2015 | 470 532.51 | 61 618.60 | 13.10 | −2.83 | 24.37 |
| 2016 | 609 205.60 | 81 795.17 | 13.43 | 29.47 | 32.74 |
| 2017 | 733 215.26 | 93 439.27 | 12.74 | 20.36 | 14.24 |

## Interpretación técnica

- **West es la mejor región** en todo: es la que más vende, la que más gana (casi el 38 % de toda la ganancia), la que tiene mejor margen y la que más crece. En 2017 tuvo su mejor año, con un 82 % más de ganancia que en 2016.
- **East** va segunda y es bastante estable: sus ventas suben todos los años.
- **Central es la peor, aunque no es la que menos vende.** Vende más que South, pero gana menos porque su margen es muy bajo (7.9 %). Además su ganancia sube y baja mucho: en 2017 vendió casi lo mismo que en 2016, pero ganó 62 % menos. Si las ventas no cambian y la ganancia cae, el problema no es cuánto se vende sino a qué precio o con cuánto descuento. Esto lo reviso en la Pregunta 6.
- **South** es la región más pequeña y la más irregular: un año cae mucho y al siguiente se recupera.
- **En toda la empresa**, las ventas crecieron 51 % de 2014 a 2017, pero el margen se quedó en alrededor del 13 %. O sea, se vende más pero no se gana proporcionalmente más.
- Algunas variaciones son muy grandes (como +2 071 % en Central 2015), pero es porque en 2014 la ganancia fue muy pequeña (539 USD). Por eso los porcentajes hay que mirarlos junto con los montos.

## Conclusión

West es la región que más aporta y la de mejor desempeño. Central es la de peor desempeño: vende bastante, pero gana poco y su ganancia es inestable. La empresa crece en ventas sin mejorar su margen, así que convendría revisar cómo se está vendiendo en Central y South.
