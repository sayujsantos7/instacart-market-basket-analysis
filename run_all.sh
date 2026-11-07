#!/usr/bin/env bash
# Builds the whole database layer in the right order.
#
#   DATA_DIR=/path/to/csvs ./run_all.sh              # full build
#   DB=mydb DATA_DIR=... ./run_all.sh                # different database name
#   SKIP_LOAD=1 ./run_all.sh                         # raw tables already loaded: rebuild analytics only
#   EXPORT=1 DATA_DIR=... ./run_all.sh               # also write CSV extracts of the summary tables
#   DQ_GATE=0 ./run_all.sh                           # keep building even if a data-quality check fails
#
# Needs: psql on PATH, an existing empty database (createdb instacart_db).
set -euo pipefail
cd "$(dirname "$0")"

DB="${DB:-instacart_db}"
PSQL=(psql -v ON_ERROR_STOP=1 -d "$DB")

run() { echo; echo "==> $1"; "${PSQL[@]}" "${@:2}" -f "sql/$1"; }

if [[ "${SKIP_LOAD:-0}" != "1" ]]; then
  if [[ -z "${DATA_DIR:-}" ]]; then
    echo "Set DATA_DIR to the folder holding the Kaggle CSVs (or SKIP_LOAD=1)." >&2; exit 1
  fi
  run 01_schema.sql
  run 02_load.sql -v "data_dir=$DATA_DIR"
  run 03_indexes.sql
fi

if [[ "${DQ_GATE:-1}" == "0" ]]; then
  run 04_data_quality.sql -v ON_ERROR_STOP=0
else
  run 04_data_quality.sql
fi
run 05_analytics_layer.sql
run 06_dashboard_queries.sql
run 07_insights.sql
run 08_workload_analysis.sql

if [[ "${EXPORT:-0}" == "1" ]]; then
  mkdir -p exports
  run 09_export_csv_extracts.sql
fi
echo; echo "Done."
