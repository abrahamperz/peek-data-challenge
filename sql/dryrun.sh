#!/usr/bin/env bash
# Dry-run every statement in a .sql file against BigQuery. A dry run validates
# syntax + all table/column/type references WITHOUT running the query or billing
# any bytes — so it doubles as a free "typecheck" for our SQL in CI.
#
# Usage: sql/dryrun.sh [file.sql] [project_id]
#   file.sql    defaults to sql/part1_queries.sql
#   project_id  defaults to $GOOGLE_CLOUD_PROJECT (or .env)
set -uo pipefail

FILE="${1:-sql/part1_queries.sql}"
PROJECT="${2:-${GOOGLE_CLOUD_PROJECT:-}}"

# fall back to .env if present and project still unset
if [ -z "$PROJECT" ] && [ -f .env ]; then
  # shellcheck disable=SC1091
  set -a; . ./.env; set +a
  PROJECT="${GOOGLE_CLOUD_PROJECT:-}"
fi

if [ -z "$PROJECT" ]; then
  echo "ERROR: no project id. Pass one as arg 2 or set GOOGLE_CLOUD_PROJECT." >&2
  exit 2
fi

echo "Dry-running $FILE against project '$PROJECT'..."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# strip comments first — a ';' inside a /* block */ or -- line comment must NOT
# be treated as a statement separator (otherwise the comment tail leaks out as
# bare SQL). Then split the comment-free text on ';' into numbered statements,
# keeping only those that contain SELECT.
CLEAN="$TMP/_clean.sql"
perl -0777 -pe 's{/\*.*?\*/}{}gs; s{--[^\n]*}{}g' "$FILE" > "$CLEAN"

awk 'BEGIN{RS=";"; n=0}
     { if ($0 ~ /[Ss][Ee][Ll][Ee][Cc][Tt]/){ n++; printf "%s;", $0 > sprintf("%s/stmt_%02d.sql", d, n) } }' \
     d="$TMP" "$CLEAN"

ok=0; fail=0; n=0
for f in "$TMP"/stmt_*.sql; do
  [ -e "$f" ] || { echo "  (no statements parsed)"; break; }
  n=$((n+1))
  if err=$(bq query --use_legacy_sql=false --dry_run --project_id="$PROJECT" < "$f" 2>&1); then
    bytes=$(echo "$err" | grep -oE '[0-9,]+ bytes' | head -1)
    printf "  stmt %02d  OK    (%s)\n" "$n" "${bytes:-dry-run valid}"
    ok=$((ok+1))
  else
    printf "  stmt %02d  FAIL\n" "$n"
    echo "$err" | grep -iE 'error|not found|unrecognized|syntax|invalid' | head -3 | sed 's/^/      /'
    fail=$((fail+1))
  fi
done

echo "  -----"
echo "  $ok OK, $fail FAIL, $n total"
[ "$n" -gt 0 ] && [ "$fail" -eq 0 ]
