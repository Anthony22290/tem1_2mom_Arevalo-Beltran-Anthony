-- =====================================================================
-- PREGUNTA 1 - Diseno e implementacion del modelo de datos (DDL)
-- Dataset: Sample Superstore
-- Modelo en tres tablas:
--   superstore_raw : capa cruda, CSV original tal cual, todo STRING
--   superstore_ref : copia publica del dataset, solo para recuperar
--                    la posicion del punto decimal (ver docs/p01)
--   superstore     : tabla analitica tipada, ORC, particionada por anio
-- =====================================================================

CREATE DATABASE IF NOT EXISTS superstore_db
COMMENT 'Examen practico 2do momento - Sample Superstore';

USE superstore_db;

-- ---------------------------------------------------------------------
-- 1) Capa cruda. OpenCSVSerde porque 6 nombres de producto vienen entre
--    comillas y contienen ';' (el separador del archivo).
--    OpenCSVSerde solo admite STRING, por eso se tipa en la capa analitica.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS superstore_raw;

CREATE TABLE superstore_raw (
    row_id        STRING,
    order_id      STRING,
    order_date    STRING,
    ship_date     STRING,
    ship_mode     STRING,
    customer_id   STRING,
    customer_name STRING,
    segment       STRING,
    country       STRING,
    city          STRING,
    state         STRING,
    postal_code   STRING,
    region        STRING,
    product_id    STRING,
    category      STRING,
    sub_category  STRING,
    product_name  STRING,
    sales         STRING,
    quantity      STRING,
    discount      STRING,
    profit        STRING
)
COMMENT 'Capa cruda: CSV original del examen (separador ;) sin transformar'
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ';', 'quoteChar' = '"')
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count' = '1');

-- ---------------------------------------------------------------------
-- 2) Copia de referencia (separador ',') con los decimales intactos.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS superstore_ref;

CREATE TABLE superstore_ref (
    row_id        STRING,
    order_id      STRING,
    order_date    STRING,
    ship_date     STRING,
    ship_mode     STRING,
    customer_id   STRING,
    customer_name STRING,
    segment       STRING,
    country       STRING,
    city          STRING,
    state         STRING,
    postal_code   STRING,
    region        STRING,
    product_id    STRING,
    category      STRING,
    sub_category  STRING,
    product_name  STRING,
    sales         STRING,
    quantity      STRING,
    discount      STRING,
    profit        STRING
)
COMMENT 'Copia publica del dataset, usada solo para restaurar decimales'
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"')
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count' = '1');

-- ---------------------------------------------------------------------
-- 3) Tabla analitica. Tipos adecuados para el analisis:
--    fechas DATE, montos DECIMAL (sin error de redondeo de DOUBLE),
--    codigo postal STRING (conserva ceros a la izquierda).
--    ORC + SNAPPY: formato columnar comprimido.
--    Particion por order_year: las consultas por anio leen solo
--    la particion necesaria (partition pruning).
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS superstore;

CREATE TABLE superstore (
    row_id        INT            COMMENT 'Identificador unico de la linea',
    order_id      STRING         COMMENT 'Identificador de la orden',
    order_date    DATE           COMMENT 'Fecha del pedido',
    ship_date     DATE           COMMENT 'Fecha de envio',
    ship_mode     STRING         COMMENT 'Modalidad de envio',
    customer_id   STRING         COMMENT 'Identificador del cliente',
    customer_name STRING         COMMENT 'Nombre del cliente',
    segment       STRING         COMMENT 'Segmento: Consumer, Corporate, Home Office',
    country       STRING         COMMENT 'Pais',
    city          STRING         COMMENT 'Ciudad',
    state         STRING         COMMENT 'Estado',
    postal_code   STRING         COMMENT 'Codigo postal de 5 digitos',
    region        STRING         COMMENT 'Region: Central, East, South, West',
    product_id    STRING         COMMENT 'Identificador del producto',
    category      STRING         COMMENT 'Categoria',
    sub_category  STRING         COMMENT 'Subcategoria',
    product_name  STRING         COMMENT 'Nombre del producto',
    sales         DECIMAL(12,4)  COMMENT 'Venta neta de la linea (USD)',
    quantity      INT            COMMENT 'Unidades vendidas',
    discount      DECIMAL(4,2)   COMMENT 'Descuento aplicado (0 a 1)',
    profit        DECIMAL(12,4)  COMMENT 'Ganancia de la linea (USD), puede ser negativa'
)
COMMENT 'Tabla analitica Superstore (tipada y corregida)'
PARTITIONED BY (order_year INT)
STORED AS ORC
TBLPROPERTIES ('orc.compress' = 'SNAPPY');

-- ---------------------------------------------------------------------
-- 4) Vistas de lectura de las capas de texto. Excluyen la fila de
--    cabecera por si el motor no respeta 'skip.header.line.count'
--    (Hive lo respeta; Spark SQL con OpenCSVSerde no).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW superstore_raw_v AS
SELECT * FROM superstore_raw WHERE row_id <> 'Row ID';

CREATE OR REPLACE VIEW superstore_ref_v AS
SELECT * FROM superstore_ref WHERE row_id <> 'Row ID';

SHOW TABLES;

DESCRIBE superstore;
