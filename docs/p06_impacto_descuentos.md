# Pregunta 6. Análisis del impacto de los descuentos

## Enunciado

Analice la relación entre los descuentos comerciales y la rentabilidad. Clasifique los registros en: sin descuento (0), descuento bajo (> 0 y hasta 20 %), descuento medio (> 20 % y hasta 50 %) y descuento alto (> 50 %). Calcule ventas y ganancias por rango, margen de rentabilidad, cantidad de registros con pérdidas, porcentaje de registros no rentables, descuento promedio y categorías y subcategorías más afectadas. Finalmente, identifique si los descuentos elevados están asociados con una mayor proporción de operaciones no rentables.

## Estrategia de solución

1. **Vista `superstore_rango_desc`:** agrega a cada línea su rango con un `CASE` (los límites son inclusivos a la derecha, como pide el enunciado: 0.20 es “bajo” y 0.50 es “medio”). La vista evita repetir el `CASE` en cada consulta.
2. **Definiciones:**
   - **Registro con pérdida:** `profit < 0`.
   - **Registro no rentable:** `profit <= 0`, es decir, que no genera ganancia (incluye 30 líneas con ganancia exactamente 0).
   - **Margen:** `SUM(profit) / SUM(sales)`, ponderado por venta y no como promedio de márgenes.
3. **Indicadores por rango** con `GROUP BY rango_descuento`, y el porcentaje de registros con `SUM(COUNT(*)) OVER ()`.
4. **Curva por nivel exacto de descuento** (0.10, 0.15, … 0.80) para ubicar el punto donde el margen se vuelve negativo.
5. **Afectación por categoría y subcategoría:** se ordena con `RANK()` según el monto de pérdidas en líneas con descuento, y se compara el margen con y sin descuento.
6. **Asociación:** correlación de Pearson (`CORR`) entre descuento y ganancia, y entre descuento y margen de la línea, además de comparar directamente el % no rentable entre rangos.

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

### Indicadores por rango de descuento

| Rango | Registros | % reg. | Ventas | Ganancia | Margen % | Con pérdida | No rentables | % no rentables | Desc. prom. % |
|-------|---------:|-------:|-------:|---------:|---------:|------------:|-------------:|---------------:|--------------:|
| Sin descuento | 4 798 | 48.01 | 1 087 908.47 | 320 987.60 | **29.51** | 0 | 30 | **0.63** | 0.00 |
| Bajo (0–20 %] | 3 803 | 38.05 | 846 522.24 | 100 785.47 | 11.91 | 523 | 545 | 14.33 | 19.68 |
| Medio (20–50 %] | 537 | 5.37 | 298 541.41 | −58 817.00 | −19.70 | 492 | 505 | 94.04 | 36.70 |
| Alto (> 50 %) | 856 | 8.57 | 64 228.74 | −76 559.05 | **−119.20** | 856 | 856 | **100.00** | 71.89 |

### Margen por nivel exacto de descuento

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

**Umbral de quiebre:** el primer nivel con margen negativo es **30 %**.

### Categorías más afectadas

| Pos. | Categoría | Líneas con desc. | Desc. prom. % | Pérdidas en líneas con desc. | Margen sin desc. % | Margen con desc. % | % no rent. con desc. |
|:---:|-----------|-----------------:|--------------:|-----------------------------:|-------------------:|-------------------:|---------------------:|
| 1 | Furniture | 1 285 | 28.71 | −60 936.11 | 22.71 | **−8.17** | 58.13 |
| 2 | Office Supplies | 2 897 | 32.72 | −56 615.26 | 29.52 | −2.89 | 30.62 |
| 3 | Technology | 1 014 | 24.10 | −38 579.92 | 33.96 | 2.94 | 26.82 |

Por categoría y rango: Furniture ya pierde 28 % de sus líneas con descuento bajo y el 99.5 % con descuento medio. Office Supplies no tiene líneas en el rango medio: pasa directo del 20 % al 70–80 % (en *Binders*) y en el rango alto su margen es −119 %.

### Subcategorías más afectadas (top 10 por pérdidas en líneas con descuento)

| Pos. | Categoría | Subcategoría | Desc. prom. % | % líneas con desc. > 20 % | Ganancia total | Margen % | Pérdidas con desc. | % no rentables |
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

Tres subcategorías tienen ganancia total negativa: **Tables (−17 725.48), Bookcases (−3 472.56) y Supplies (−1 189.10)**.

### Asociación descuento – rentabilidad

| Indicador | Valor |
|-----------|------:|
| Correlación descuento vs. ganancia de la línea | −0.2195 |
| Correlación descuento vs. margen de la línea | **−0.8645** |
| % no rentables con descuento alto (> 50 %) | **100.00 %** |
| % no rentables sin descuento | 0.63 % |
| % no rentables con descuento > 20 % | 97.70 % |
| % no rentables con descuento ≤ 20 % | 6.69 % |

## Interpretación técnica

- **El descuento destruye el margen de forma escalonada:** sin descuento el margen es de 29.5 %; con hasta 20 % baja a 11.9 %; entre 20 % y 50 % es −19.7 %, y por encima de 50 % es −119 %, es decir, se pierde más de lo que se vende.
- **Hay un umbral claro en el 30 %:** hasta el 20 % de descuento la mayoría de las líneas siguen siendo rentables (86 %). Desde el 30 %, prácticamente ninguna lo es (97.7 %). El 20 % es el último nivel seguro.
- **Los descuentos medio y alto son solo el 14 % de las líneas, pero borran el 33 % de la ganancia:** juntos pierden 135 376 USD, mientras que las líneas sin descuento ganan 320 988 USD.
- **La correlación confirma la asociación:** contra la ganancia absoluta es débil (−0.22), porque la ganancia depende también del tamaño de la venta. Contra el **margen de cada línea es fuerte (−0.86)**: a mayor descuento, menor margen, casi de forma lineal.
- **Por categoría, Furniture es la más afectada:** con descuento su margen pasa de +22.7 % a −8.2 %, y es la única que pierde en el agregado de líneas con descuento. *Tables* y *Bookcases* terminan con pérdida total aunque sin descuento son rentables.
- **Binders es la subcategoría que más pierde por descuentos** (−38 510 USD): el 40 % de sus líneas se venden con 70–80 % de descuento. Aun así, la subcategoría es rentable en total gracias a sus ventas sin descuento.
- Esto explica hallazgos anteriores: el bajo margen de la región Central (P3) y los productos con más pérdida (P5: impresoras 3D, mesas) coinciden con descuentos de 40 % a 80 %.

## Conclusión

**Sí: los descuentos elevados están asociados a una mayor proporción de operaciones no rentables.** El 100 % de las líneas con descuento mayor a 50 % pierde dinero, frente al 0.63 % de las líneas sin descuento, y la correlación entre descuento y margen es de −0.86. La recomendación es poner un tope de descuento del 20 % (el último nivel con margen positivo) y revisar en especial *Tables*, *Bookcases*, *Binders* y *Machines*, donde se concentran las pérdidas.
