# Pregunta 6. Análisis del impacto de los descuentos

## Enunciado

Analice la relación entre los descuentos comerciales y la rentabilidad. Clasifique los registros en: sin descuento (0), descuento bajo (> 0 y hasta 20 %), descuento medio (> 20 % y hasta 50 %) y descuento alto (> 50 %). Calcule ventas y ganancias por rango, margen de rentabilidad, cantidad de registros con pérdidas, porcentaje de registros no rentables, descuento promedio y categorías y subcategorías más afectadas. Finalmente, identifique si los descuentos elevados están asociados con una mayor proporción de operaciones no rentables.

## Estrategia de solución

1. **Asignar un rango a cada venta:** creé la vista `superstore_rango_desc` con un `CASE` que pone a cada registro en su rango. Lo hice como vista para no repetir el `CASE` en todas las consultas. Los límites incluyen el valor de la derecha, como dice el enunciado: 20 % es “bajo” y 50 % es “medio”.
2. **Definiciones que usé:**
   - **Registro con pérdida:** la ganancia es negativa (`profit < 0`).
   - **Registro no rentable:** la ganancia es cero o negativa (`profit <= 0`), o sea, que no dejó ganancia. Incluye 30 ventas con ganancia exactamente 0.
   - **Margen:** ganancia total dividida entre ventas totales del rango.
3. **Indicadores por rango:** agrupé por rango y calculé ventas, ganancia, margen, registros con pérdida, % no rentable y descuento promedio.
4. **Cada nivel de descuento por separado** (10 %, 15 %, 20 %, … 80 %), para ver en qué punto el margen se vuelve negativo.
5. **Categorías y subcategorías más afectadas:** las ordené con `RANK()` según cuánto dinero pierden en las ventas con descuento, y comparé su margen con y sin descuento.
6. **¿Hay relación?** Calculé la correlación (`CORR`), que va de −1 a 1 y mide si dos cosas se mueven juntas. Un valor cercano a −1 significa que cuando una sube, la otra baja. También comparé directamente el % no rentable entre los rangos.

## Consulta HiveQL desarrollada

Script completo: [`sql/p06_impacto_descuentos.sql`](../sql/p06_impacto_descuentos.sql)

```sql
CREATE OR REPLACE VIEW superstore_rango_desc AS
SELECT s.*,
       CASE WHEN discount = 0     THEN '1 Sin descuento'
            WHEN discount <= 0.20 THEN '2 Bajo (0-20%]'
            WHEN discount <= 0.50 THEN '3 Medio (20-50%]'
            ELSE                       '4 Alto (>50%)'
       END AS rango_descuento
FROM superstore s;

SELECT rango_descuento,
       COUNT(*)                                                AS registros,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)      AS pct_registros,
       ROUND(SUM(sales), 2)                                    AS ventas,
       ROUND(SUM(profit), 2)                                   AS ganancia,
       ROUND(SUM(profit) / SUM(sales) * 100, 2)                AS margen_pct,
       SUM(IF(profit < 0, 1, 0))                               AS registros_con_perdida,
       SUM(IF(profit <= 0, 1, 0))                              AS registros_no_rentables,
       ROUND(SUM(IF(profit <= 0, 1, 0)) * 100.0 / COUNT(*), 2) AS pct_no_rentables,
       ROUND(AVG(discount) * 100, 2)                           AS descuento_prom_pct
FROM superstore_rango_desc
GROUP BY rango_descuento
ORDER BY rango_descuento;
```

## Evidencia de ejecución

[`evidencias/p06_impacto_descuentos.txt`](../evidencias/p06_impacto_descuentos.txt)

## Resultado obtenido

### Resultados por rango de descuento

| Rango | Registros | % reg. | Ventas | Ganancia | Margen % | Con pérdida | No rentables | % no rentables | Desc. prom. % |
|-------|---------:|-------:|-------:|---------:|---------:|------------:|-------------:|---------------:|--------------:|
| Sin descuento | 4 798 | 48.01 | 1 087 908.47 | 320 987.60 | **29.51** | 0 | 30 | **0.63** | 0.00 |
| Bajo (0–20 %] | 3 803 | 38.05 | 846 522.24 | 100 785.47 | 11.91 | 523 | 545 | 14.33 | 19.68 |
| Medio (20–50 %] | 537 | 5.37 | 298 541.41 | −58 817.00 | −19.70 | 492 | 505 | 94.04 | 36.70 |
| Alto (> 50 %) | 856 | 8.57 | 64 228.74 | −76 559.05 | **−119.20** | 856 | 856 | **100.00** | 71.89 |

### Margen en cada nivel de descuento

| Descuento | Registros | Margen % | % no rentables |
|----------:|----------:|---------:|---------------:|
| 0 % | 4 798 | 29.51 | 0.63 |
| 10 % | 94 | 16.61 | 4.26 |
| 15 % | 52 | 5.15 | 32.69 |
| 20 % | 3 657 | 11.82 | 14.33 |
| **30 %** | 227 | **−10.05** | 97.36 |
| 32 % | 27 | −16.50 | 100.00 |
| 40 % | 206 | −19.81 | 87.38 |
| 45 % | 11 | −45.45 | 100.00 |
| 50 % | 66 | −34.80 | 100.00 |
| 60 % | 138 | −89.46 | 100.00 |
| 70 % | 418 | −98.66 | 100.00 |
| 80 % | 300 | −180.03 | 100.00 |

**El margen se vuelve negativo a partir del 30 % de descuento.**

### Categorías más afectadas

| Puesto | Categoría | Ventas con desc. | Desc. prom. % | Pérdidas en ventas con desc. | Margen sin desc. % | Margen con desc. % | % no rentable con desc. |
|:---:|-----------|-----------------:|--------------:|-----------------------------:|-------------------:|-------------------:|------------------------:|
| 1 | Furniture | 1 285 | 28.71 | −60 936.11 | 22.71 | **−8.17** | 58.13 |
| 2 | Office Supplies | 2 897 | 32.72 | −56 615.26 | 29.52 | −2.89 | 30.62 |
| 3 | Technology | 1 014 | 24.10 | −38 579.92 | 33.96 | 2.94 | 26.82 |

Por categoría y rango: en Furniture, hasta con descuento bajo el 28 % de las ventas ya no es rentable, y con descuento medio no lo es el 99.5 %. Office Supplies no tiene ventas con descuento medio: pasa directamente del 20 % al 70–80 %.

### Subcategorías más afectadas (top 10 por pérdidas en ventas con descuento)

| Puesto | Categoría | Subcategoría | Desc. prom. % | % ventas con desc. > 20 % | Ganancia total | Margen % | Pérdidas con desc. | % no rentables |
|:---:|-----------|--------------|--------------:|--------------------------:|---------------:|---------:|-------------------:|---------------:|
| 1 | Office Supplies | Binders | 37.23 | 40.25 | 30 221.76 | 14.86 | −38 510.50 | 40.25 |
| 2 | Furniture | **Tables** | 26.13 | 55.17 | **−17 725.48** | −8.56 | −32 412.15 | 64.26 |
| 3 | Technology | Machines | 30.61 | 46.09 | 3 384.76 | 1.79 | −30 118.67 | 38.26 |
| 4 | Furniture | **Bookcases** | 21.11 | 30.70 | **−3 472.56** | −3.02 | −12 152.21 | 48.68 |
| 5 | Furniture | Chairs | 17.02 | 25.61 | 26 590.17 | 8.10 | −9 880.84 | 41.33 |
| 6 | Office Supplies | Appliances | 16.65 | 14.38 | 18 138.01 | 16.87 | −8 629.64 | 14.38 |
| 7 | Technology | Phones | 15.46 | 12.26 | 44 515.73 | 13.49 | −7 530.62 | 15.52 |
| 8 | Furniture | Furnishings | 13.83 | 14.42 | 13 059.14 | 14.24 | −6 490.91 | 18.39 |
| 9 | Office Supplies | Storage | 7.47 | 0.00 | 21 278.83 | 9.51 | −6 426.30 | 21.87 |
| 10 | Office Supplies | **Supplies** | 7.68 | 0.00 | **−1 189.10** | −2.55 | −3 015.62 | 17.37 |

Tres subcategorías terminaron con **pérdida total**: Tables (−17 725.48), Bookcases (−3 472.56) y Supplies (−1 189.10).

### ¿Hay relación entre descuento y rentabilidad?

| Indicador | Valor |
|-----------|------:|
| Correlación entre descuento y ganancia | −0.2195 |
| Correlación entre descuento y margen de cada venta | **−0.8645** |
| % no rentables con descuento alto (> 50 %) | **100.00 %** |
| % no rentables sin descuento | 0.63 % |
| % no rentables con descuento mayor a 20 % | 97.70 % |
| % no rentables con descuento de hasta 20 % | 6.69 % |

## Interpretación técnica

- **Mientras más descuento, menos margen.** Sin descuento se gana casi 30 centavos por cada dólar vendido; con descuento bajo, 12 centavos; con descuento medio se pierden 20 centavos, y con descuento alto se pierde más de lo que se vende.
- **El 20 % parece ser el límite.** Hasta el 20 % de descuento, la mayoría de las ventas todavía deja ganancia. Desde el 30 %, casi ninguna.
- **Pocas ventas hacen mucho daño.** Las ventas con descuento medio y alto son solo el 14 % del total, pero juntas pierden 135 376 USD, que es como un tercio de la ganancia de la empresa.
- **Sobre la correlación:** entre descuento y ganancia es débil (−0.22), porque la ganancia también depende de si la venta fue grande o pequeña. Pero entre descuento y margen es fuerte (−0.86). Esto confirma que, a más descuento, menos margen.
- **Furniture es la categoría más afectada:** sin descuento gana 22.7 %, pero con descuento pierde 8.2 %. Tables y Bookcases terminan perdiendo dinero en total, aunque sin descuento sí son rentables.
- **Binders es la subcategoría que más pierde por descuentos** (−38 510 USD), porque el 40 % de sus ventas se hicieron con 70–80 % de descuento. Aun así gana en total gracias a sus ventas sin descuento.
- Esto conecta con lo que vi antes: el margen bajo de la región Central (Pregunta 3) y los productos que más pierden (Pregunta 5) tienen descuentos altos.

## Conclusión

**Sí, los descuentos altos están relacionados con más ventas no rentables.** El 100 % de las ventas con más del 50 % de descuento perdió dinero, mientras que sin descuento solo el 0.63 % no fue rentable. Mi recomendación sería no dar descuentos de más del 20 % y revisar sobre todo Tables, Bookcases, Binders y Machines, que es donde más se pierde.
