# Diccionario de datos – Sample Superstore

**Archivo de origen:** `csv/Sample - Superstore.csv`
**Formato original:** texto delimitado por `;`, codificación Windows-1252, fin de línea CRLF, 1 fila de cabecera + 9 994 registros, 21 campos.
**Granularidad:** una fila = una línea de producto dentro de una orden.
**Tabla analítica en Hive:** `superstore_db.superstore` (ORC + SNAPPY, particionada por `order_year`).

| # | Campo original | Columna Hive | Tipo Hive | Descripción | Restricciones / dominio observado |
|---|----------------|--------------|-----------|-------------|-----------------------------------|
| 1 | Row ID | `row_id` | INT | Identificador secuencial de la línea | NOT NULL, único, 1 – 9 994 |
| 2 | Order ID | `order_id` | STRING | Identificador de la orden (`XX-AAAA-NNNNNN`) | NOT NULL; 5 009 órdenes distintas; una orden tiene 1 o más líneas |
| 3 | Order Date | `order_date` | DATE | Fecha en que se registró el pedido | NOT NULL; formato origen `M/d/yyyy`; rango 2014-01-03 a 2017-12-30 |
| 4 | Ship Date | `ship_date` | DATE | Fecha de envío | NOT NULL; `ship_date >= order_date`; rango 2014-01-07 a 2018-01-05 |
| 5 | Ship Mode | `ship_mode` | STRING | Modalidad de envío | First Class, Same Day, Second Class, Standard Class |
| 6 | Customer ID | `customer_id` | STRING | Identificador del cliente | NOT NULL; 793 clientes distintos |
| 7 | Customer Name | `customer_name` | STRING | Nombre del cliente | NOT NULL; contiene acentos (requiere UTF-8) |
| 8 | Segment | `segment` | STRING | Segmento de mercado | Consumer, Corporate, Home Office |
| 9 | Country | `country` | STRING | País | Valor único: United States |
| 10 | City | `city` | STRING | Ciudad | 531 valores distintos |
| 11 | State | `state` | STRING | Estado | 49 valores distintos |
| 12 | Postal Code | `postal_code` | STRING | Código postal (ZIP) | 5 dígitos; STRING para conservar ceros a la izquierda (`5408` → `05408`) |
| 13 | Region | `region` | STRING | Región comercial | Central, East, South, West |
| 14 | Product ID | `product_id` | STRING | Identificador del producto (`CAT-SC-NNNNNNNN`) | NOT NULL; 1 862 valores distintos |
| 15 | Category | `category` | STRING | Categoría del producto | Furniture, Office Supplies, Technology |
| 16 | Sub-Category | `sub_category` | STRING | Subcategoría del producto | 17 valores distintos |
| 17 | Product Name | `product_name` | STRING | Nombre del producto | 1 850 valores distintos; 6 nombres contienen `;` |
| 18 | Sales | `sales` | DECIMAL(12,4) | Importe neto de venta de la línea (USD, ya con descuento) | > 0; rango 0.444 – 22 638.48; hasta 4 decimales |
| 19 | Quantity | `quantity` | INT | Unidades vendidas | > 0; rango 1 – 14 |
| 20 | Discount | `discount` | DECIMAL(4,2) | Descuento aplicado como fracción | 0 ≤ discount < 1; valores: 0, 0.10, 0.15, 0.20, 0.30, 0.32, 0.40, 0.45, 0.50, 0.60, 0.70, 0.80 |
| 21 | Profit | `profit` | DECIMAL(12,4) | Ganancia (o pérdida) de la línea (USD) | Puede ser negativa; rango −6 599.978 – 8 399.976 |
| – | (derivado) | `order_year` | INT (partición) | Año de `order_date` | 2014, 2015, 2016, 2017 |

## Por qué elegí estos tipos

- **DATE para las fechas:** en el CSV vienen como texto (`11/8/2016`). Al convertirlas a fecha puedo restar fechas (`DATEDIFF`), sacar el año o el mes y ordenarlas bien.
- **DECIMAL para los montos:** `DOUBLE` puede dar pequeños errores de redondeo al sumar muchos valores. `DECIMAL(12,4)` guarda los 4 decimales exactos que tiene el dataset.
- **DECIMAL(4,2) para el descuento:** el valor más alto es 0.80, así que alcanza con 2 decimales.
- **STRING para el código postal:** es un código y no un número para hacer cuentas. Además, si lo guardo como número se pierden los ceros a la izquierda (`05408` quedaría `5408`).
- **INT para `row_id` y `quantity`:** son números enteros.

## Problemas que encontré en el archivo original

| Problema | Ejemplo | Cómo lo resolví |
|----------|---------|-------------|
| Separador decimal eliminado en `Sales`, `Discount` y `Profit` | `Sales = 26196` (real 261.96), `Discount = 45` (real 0.45), `Profit = 419136` (real 41.9136) | `Discount`: se reconstruye como `0.` + dígitos. `Sales`/`Profit`: se toma la posición del punto de una copia pública del dataset, solo si los dígitos coinciden al 100 % (ver `docs/p01_modelo_datos.md`) |
| Separador `;` dentro de un campo | `"Imation Secure+ ... Flash Drive; 16GB"` (6 filas) | Tabla cruda con `OpenCSVSerde` y `quoteChar = '"'` |
| Codificación Windows-1252 | `Französisch`, espacios no separables en nombres de producto | Conversión a UTF-8 con `iconv` antes de la carga |
| Fin de línea CRLF | `Profit` terminaría en `\r` | Se elimina el `\r` con `sed` antes de la carga |
| Código postal sin cero inicial | `5408` | `LPAD(postal_code, 5, '0')` |
| Fechas como texto `M/d/yyyy` | `11/8/2016` | Conversión a DATE en la carga |
