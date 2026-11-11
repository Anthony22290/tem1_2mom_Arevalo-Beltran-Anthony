#!/usr/bin/env bash
# Prepara el CSV original para la ingesta en Hive.
#  1. Convierte la codificacion de Windows-1252 (Latin-1) a UTF-8.
#  2. Quita el fin de linea de Windows (CRLF -> LF) para que el ultimo
#     campo (Profit) no quede con un caracter '\r' al final.
# No se modifica ningun valor: las demas correcciones se hacen en HiveQL.
set -euo pipefail
cd "$(dirname "$0")/.."

ORIGEN="csv/Sample - Superstore.csv"
DESTINO="csv/preparado/superstore_utf8.csv"

mkdir -p csv/preparado
iconv -f WINDOWS-1252 -t UTF-8 "$ORIGEN" | sed 's/\r$//' > "$DESTINO"

# Copia de referencia (ya esta en UTF-8, solo se quita el CRLF).
# Se usa unicamente para recuperar la posicion del punto decimal.
sed 's/\r$//' csv/referencia/superstore_referencia.csv > csv/preparado/referencia_utf8.csv

echo "Lineas origen : $(wc -l < "$ORIGEN")"
echo "Lineas destino: $(wc -l < "$DESTINO")"
file "$ORIGEN" "$DESTINO" csv/preparado/referencia_utf8.csv
