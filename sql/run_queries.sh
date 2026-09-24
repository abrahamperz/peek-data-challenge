#!/usr/bin/env bash
#
# run_queries.sh — regenerate data/*.csv from sql/part1_queries.sql
# ------------------------------------------------------------------
# Runs every Part 1 query against BigQuery and writes the results to data/.
# This closes the reproducibility loop:  SQL  ->  data/*.csv  ->  notebook charts.
#
# Requirements:
#   - Google Cloud SDK (`bq` CLI) installed.
#   - Authenticated:   gcloud auth application-default login
#   - A GCP project id in GOOGLE_CLOUD_PROJECT (see .env.example).
#
# The queries read only the PUBLIC dataset `bigquery-public-data.thelook_ecommerce`.
# GOOGLE_CLOUD_PROJECT is just the project that RUNS/BILLS the query — it is NOT a
# credential and NOT baked into the SQL, so the reviewer uses their own.
#
# Usage:
#   cp .env.example .env   # then edit .env with your project id
#   bash sql/run_queries.sh
#   # or:  GOOGLE_CLOUD_PROJECT=my-project bash sql/run_queries.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env if present (for GOOGLE_CLOUD_PROJECT).
if [ -f "$REPO_ROOT/.env" ]; then
  set -a; . "$REPO_ROOT/.env"; set +a
fi

PROJECT="${GOOGLE_CLOUD_PROJECT:-}"
if [ -z "$PROJECT" ]; then
  echo "ERROR: GOOGLE_CLOUD_PROJECT is not set."
  echo "       Copy .env.example to .env and set your project id, or run:"
  echo "       export GOOGLE_CLOUD_PROJECT=your-gcp-project-id"
  exit 1
fi

if ! command -v bq >/dev/null 2>&1; then
  echo "ERROR: 'bq' CLI not found. Install the Google Cloud SDK: https://cloud.google.com/sdk"
  exit 1
fi

SQL="$SCRIPT_DIR/part1_queries.sql"
OUT="$REPO_ROOT/data"
mkdir -p "$OUT"

# Output filenames, in the SAME ORDER the queries appear in part1_queries.sql.
names=(
  taskA_monthly_financials
  taskB_new_vs_returning
  taskC_churn_90d
  taskC_cohort_retention
  taskD1_monthly_trend
  taskD2_prepost_valueband
  taskD3_traffic_source
)

# Why split? `bq query` runs ONE statement per call — feeding it the whole file
# (7 queries separated by ';') makes BigQuery error out, and even if it didn't, all
# results would land in a single CSV. So we split part1_queries.sql into 7 separate
# statements and run each on its own, sending each result to its own data/*.csv.
# The split is on ';' (awk RS=";"), which requires every ';' in the file to be a real
# statement terminator (no ';' inside comments) — the count guard below enforces this.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
awk -v dir="$tmp" 'BEGIN{RS=";"} {
  s=$0; sub(/^[ \t\r\n]+/,"",s);
  if (length(s)>0) { n++; printf "%s", s > sprintf("%s/q%02d.sql", dir, n) }
}' "$SQL"

count=$(ls "$tmp"/q*.sql 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -ne "${#names[@]}" ]; then
  echo "ERROR: parsed $count statements but expected ${#names[@]}."
  echo "       The query/CSV mapping in this script is out of sync with part1_queries.sql."
  exit 1
fi

echo "Project: $PROJECT   |   Regenerating ${#names[@]} CSVs into data/ ..."
i=0
for f in "$tmp"/q*.sql; do
  name="${names[$i]}"
  echo ">> ${name}"
  bq query --use_legacy_sql=false --project_id="$PROJECT" \
           --format=csv --max_rows=1000000 < "$f" > "$OUT/${name}.csv"
  rows=$(( $(wc -l < "$OUT/${name}.csv") - 1 ))
  echo "   wrote data/${name}.csv (${rows} rows)"
  i=$((i+1))
done

echo "Done. All CSVs in data/ are regenerated from sql/part1_queries.sql."
