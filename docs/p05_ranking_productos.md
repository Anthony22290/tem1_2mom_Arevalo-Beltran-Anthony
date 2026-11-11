# Pregunta 5. Ranking de productos según rentabilidad

## Enunciado

Identifique los productos de mayor y menor desempeño económico: los cinco productos con mayor ganancia acumulada por categoría, los cinco con mayor volumen de ventas, los cinco con menor rentabilidad, el margen de ganancia de cada producto y la posición de cada producto dentro de su categoría. Utilice `RANK()`, `DENSE_RANK()` y funciones de agregación acumulativa.

## Estrategia de solución

1. **Qué es un producto:** en la Pregunta 2 vi que hay 32 códigos de producto con dos nombres distintos. Para no mezclar productos diferentes, agrupé por **código y nombre**. Así quedaron **1 894 productos**.
2. **Tabla `producto_metricas`:** primero calculé, para cada producto, las ventas, la ganancia, las unidades, el margen y el descuento promedio. La guardé como tabla para no repetir el cálculo en cada consulta.
3. **Funciones de ventana que usé:**
   - `RANK()`: posición del producto dentro de su categoría. Si dos productos empatan, los dos quedan en el mismo puesto y se salta el siguiente (1, 2, 2, 4).
   - `DENSE_RANK()`: igual que `RANK`, pero sin saltar puestos (1, 2, 2, 3). Lo usé en unidades y margen, donde hay muchos empates.
   - `SUM() OVER (... ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)`: suma acumulada. Va sumando la ganancia desde el primer producto hasta el actual, para ver cuánto aportan entre todos los primeros puestos.
   - `PERCENT_RANK()`: en qué porcentaje del ranking está cada producto.
4. Tomé **“volumen de ventas”** como el dinero vendido (USD), pero también muestro el ranking por unidades.
5. Para **“menor rentabilidad”** hice dos rankings: por **mayor pérdida en dinero** y por **peor margen %**. En el segundo solo incluí productos con ventas de al menos 1 000 USD, para que no aparezca un producto que se vendió una sola vez por poco dinero.
6. Guardé el ranking de todos los productos en la tabla `producto_ranking` y lo exporté a un CSV.

## Consulta HiveQL desarrollada

Script completo: [`sql/p05_ranking_productos.sql`](../sql/p05_ranking_productos.sql)

```sql
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
       ROUND(ganancia_acumulada, 2)                      AS ganancia_acumulada,
       ROUND(ganancia_acumulada / ganancia_cat * 100, 2) AS pct_acum_categoria
FROM ranking
WHERE rank_cat <= 5
ORDER BY category, rank_cat;
```

En Hive, el ranking completo también se puede exportar a una carpeta con:

```sql
INSERT OVERWRITE LOCAL DIRECTORY 'resultados/p05_ranking'
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
SELECT * FROM producto_ranking ORDER BY category, rank_ganancia;
```

## Evidencia de ejecución

- [`evidencias/p05_ranking_productos.txt`](../evidencias/p05_ranking_productos.txt)
- [`evidencias/p05_ranking_completo.csv`](../evidencias/p05_ranking_completo.csv): margen y posición de los 1 894 productos.

## Resultado obtenido

### Los 5 productos con más ganancia en cada categoría

| Categoría | Puesto | Producto | Ventas | Ganancia | Margen % | % acumulado de la categoría |
|-----------|:---:|----------|-------:|---------:|---------:|----------------------------:|
| Furniture | 1 | Hon Deluxe Fabric Upholstered Stacking Chairs, Rounded Back | 10 637.53 | 1 927.44 | 18.12 | 10.45 |
| Furniture | 2 | Global Deluxe High-Back Manager's Chair | 8 665.19 | 1 558.59 | 17.99 | 18.89 |
| Furniture | 3 | Hon Pagoda Stacking Chairs | 6 483.80 | 1 540.70 | 23.76 | 27.24 |
| Furniture | 4 | Hon 4070 Series Pagoda Armless Upholstered Stacking Chairs | 8 431.00 | 1 388.63 | 16.47 | 34.77 |
| Furniture | 5 | Office Star - Professional Matrix Back Chair … | 8 774.50 | 1 305.65 | 14.88 | 41.85 |
| Office Supplies | 1 | Fellowes PB500 Electric Punch Plastic Comb Binding Machine … | 27 453.38 | 7 753.04 | 28.24 | 6.33 |
| Office Supplies | 2 | Ibico EPK-21 Electric Binding System | 15 875.92 | 3 345.28 | 21.07 | 9.06 |
| Office Supplies | 3 | Honeywell Enviracaire Portable HEPA Air Cleaner … | 11 304.44 | 3 247.02 | 28.72 | 11.71 |
| Office Supplies | 4 | Fellowes PB300 Plastic Comb Binding Machine | 8 070.19 | 2 518.06 | 31.20 | 13.77 |
| Office Supplies | 5 | Ibico Ibimaster 300 Manual Binding System | 7 985.38 | 2 318.34 | 29.03 | 15.66 |
| Technology | 1 | Canon imageCLASS 2200 Advanced Copier | 61 599.82 | 25 199.93 | 40.91 | 17.32 |
| Technology | 2 | Hewlett Packard LaserJet 3310 Copier | 18 839.69 | 6 983.88 | 37.07 | 22.13 |
| Technology | 3 | Canon PC1060 Personal Laser Copier | 11 619.83 | 4 570.93 | 39.34 | 25.27 |
| Technology | 4 | HP Designjet T520 Inkjet Large Format Printer - 24" Color | 18 374.90 | 4 094.98 | 22.29 | 28.08 |
| Technology | 5 | Ativa V4110MDD Micro-Cut Shredder | 7 699.89 | 3 772.95 | 49.00 | 30.68 |

### Los 5 productos que más vendieron (en dólares)

| Puesto | Categoría | Producto | Ventas | Unidades (puesto) | Ganancia | Margen % |
|:---:|-----------|----------|-------:|------------------:|---------:|---------:|
| 1 | Technology | Canon imageCLASS 2200 Advanced Copier | 61 599.82 | 20 (41°) | 25 199.93 | 40.91 |
| 2 | Office Supplies | Fellowes PB500 Electric Punch … Binding Machine | 27 453.38 | 31 (30°) | 7 753.04 | 28.24 |
| 3 | Technology | Cisco TelePresence System EX90 Videoconferencing Unit | 22 638.48 | 6 (55°) | −1 811.08 | −8.00 |
| 4 | Furniture | HON 5400 Series Task Chairs for Big and Tall | 21 870.58 | 39 (22°) | 0.00 | 0.00 |
| 5 | Office Supplies | GBC DocuBind TL300 Electric Binding System | 19 823.48 | 37 (24°) | 2 233.51 | 11.27 |

Si se ordena por **unidades**, el primero es *GBC Premium Transparent Covers* (67 unidades, pero solo 780 USD). Aquí se ve la diferencia entre `RANK` y `DENSE_RANK`: dos productos empatan en el puesto 4 con 59 unidades, y con `DENSE_RANK` el siguiente queda 5°, mientras que con `RANK` quedaría 6°.

### Los 5 productos con menor rentabilidad (los que más dinero perdieron)

| Puesto | Categoría / Subcategoría | Producto | Ventas | Ganancia | Margen % | Descuento prom. % | Puesto en su categoría |
|:---:|--------------------------|----------|-------:|---------:|---------:|------------------:|------------------------|
| 1 | Technology / Machines | Cubify CubeX 3D Printer Double Head Print | 11 099.96 | −8 879.97 | −80.00 | 53.33 | 413 de 413 |
| 2 | Technology / Machines | Lexmark MX611dhe Monochrome Laser Printer | 16 829.90 | −4 589.97 | −27.27 | 40.00 | 412 de 413 |
| 3 | Technology / Machines | Cubify CubeX 3D Printer Triple Head Print | 7 999.98 | −3 839.99 | −48.00 | 50.00 | 411 de 413 |
| 4 | Furniture / Tables | Chromcraft Bull-Nose Wood Oval Conference Tables & Bases | 9 917.64 | −2 876.12 | −29.00 | 28.00 | 383 de 383 |
| 5 | Furniture / Tables | Bush Advantage Collection Racetrack Conference Table | 9 544.73 | −1 934.40 | −20.27 | 35.00 | 382 de 383 |

Ordenando por **peor margen %** (con ventas de al menos 1 000 USD) aparecen: Epson TM-T88V Thermal Printer (−87.18 %), Cubify CubeX Double Head (−80.00 %), BoxOffice Meeting Room Tables (−67.31 %), Bevis Conference Tables (−58.26 %) y Cubify CubeX Triple Head (−48.00 %). Todos se vendieron con descuentos promedio de entre 47 % y 55 %.

### Resumen por categoría

| Categoría | Productos | Ventas | Ganancia | Margen % | Productos con pérdida | % con pérdida |
|-----------|----------:|-------:|---------:|---------:|----------------------:|--------------:|
| Technology | 413 | 836 154.02 | 145 455.07 | 17.40 | 57 | 13.80 |
| Office Supplies | 1 098 | 719 047.08 | 122 490.89 | 17.04 | 124 | 11.29 |
| Furniture | 383 | 741 999.86 | 18 451.27 | 2.49 | 123 | 32.11 |

En total, **304 de los 1 894 productos (16 %) perdieron dinero**, en conjunto −77 092.05 USD.

## Interpretación técnica

- **En Technology un solo producto pesa mucho:** la copiadora Canon imageCLASS 2200 genera el 17 % de toda la ganancia de la categoría. Además es el producto más vendido de toda la tienda y tiene un margen del 41 %. Casi todo el top 5 de Technology son copiadoras.
- **En Office Supplies la ganancia está más repartida:** como tiene 1 098 productos, los 5 primeros solo suman el 15.7 % de la ganancia de la categoría. Sus mejores productos son máquinas encuadernadoras.
- **Vender mucho no siempre significa ganar:** entre los 5 productos más vendidos, la Cisco TelePresence perdió 1 811 USD y la silla HON 5400 no dejó ninguna ganancia. Si solo hubiera mirado las ventas, habría pensado que eran buenos productos.
- **Los productos que más pierden se parecen:** son impresoras 3D, impresoras láser y mesas de conferencia, y todos tienen descuentos altos (de 28 % a 53 %). Esto me hace pensar que el problema son los descuentos, y lo reviso en la Pregunta 6.
- **Furniture es la categoría con más problemas:** vende casi lo mismo que Office Supplies, pero gana casi 7 veces menos, y 1 de cada 3 de sus productos pierde dinero.

## Conclusión

Los productos más rentables son las copiadoras (Technology) y las encuadernadoras (Office Supplies). Los que más pierden son impresoras y mesas vendidas con mucho descuento. Furniture es la categoría más preocupante, porque casi un tercio de sus productos tiene pérdidas. Antes de buscar vender más de esos productos, habría que revisar sus precios y descuentos.
