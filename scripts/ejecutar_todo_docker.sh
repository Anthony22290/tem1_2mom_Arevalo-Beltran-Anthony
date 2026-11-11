#!/usr/bin/env bash
# Ejecuta todos los scripts HiveQL en orden dentro del contenedor de Hive
# y guarda la salida de cada uno en evidencias/hive/.
#
# Uso (desde la carpeta del repositorio):
#   docker compose up -d
#   docker compose exec hive bash scripts/ejecutar_todo_docker.sh
set -euo pipefail
cd "$(dirname "$0")/.."

URL="jdbc:hive2://localhost:10000/"
SALIDA="evidencias/hive"
mkdir -p "$SALIDA"

echo "Esperando a que HiveServer2 este listo..."
for i in $(seq 1 60); do
    if beeline -u "$URL" -e "SELECT 1;" > /dev/null 2>&1; then
        echo "HiveServer2 listo."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "HiveServer2 no respondio despues de 5 minutos." >&2
        exit 1
    fi
    sleep 5
done

SCRIPTS=(
    sql/p01_ddl.sql
    sql/p01_carga.sql
    sql/p02_calidad.sql
    sql/p03_evolucion_region.sql
    sql/p04_rfm.sql
    sql/p05_ranking_productos.sql
    sql/p06_impacto_descuentos.sql
)

for f in "${SCRIPTS[@]}"; do
    nombre=$(basename "$f" .sql)
    echo ""
    echo "=============================================="
    echo " Ejecutando $f"
    echo "=============================================="
    beeline -u "$URL" \
        --hiveconf hive.exec.dynamic.partition.mode=nonstrict \
        --hiveconf hive.strict.checks.cartesian.product=false \
        --showHeader=true --outputformat=table \
        -f "$f" 2>&1 | tee "$SALIDA/$nombre.txt"
done

echo ""
echo "Listo. Resultados guardados en $SALIDA/"
