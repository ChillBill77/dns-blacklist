#!/usr/bin/env bash
# =============================================================================
# YaWorks DNS Blocklist Merger
# Fetches multiple threat intelligence blocklists, normalizes, deduplicates
# and produces a single plain-domain list for use with Technitium DNS,
# Pi-hole, AdGuard, or any DNS resolver that accepts a flat domain list.
#
# Usage:
#   ./merge.sh                  # normal run, outputs to dist/blocklist.txt
#   ./merge.sh --dry-run        # download + parse, skip writing output
#   ./merge.sh --sources FILE   # use a custom sources file
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SOURCES_FILE="${SOURCES_FILE:-sources.txt}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
OUTPUT_FILE="${OUTPUT_DIR}/blocklist.txt"
STATS_FILE="${OUTPUT_DIR}/stats.json"
CACHE_DIR="${CACHE_DIR:-.cache}"
MAX_TIMEOUT=60          # seconds per download
MIN_DOMAINS=100         # sanity: abort if a list returns fewer than this
DRY_RUN=false

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true ;;
    --sources)    SOURCES_FILE="$2"; shift ;;
    --output-dir) OUTPUT_DIR="$2";   shift ;;
    *)            echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date -u +%H:%M:%S)] $*"; }
warn() { echo "[$(date -u +%H:%M:%S)] WARN: $*" >&2; }
die()  { echo "[$(date -u +%H:%M:%S)] ERROR: $*" >&2; exit 1; }

DOMAIN_RE='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

# Extract domains from a raw file (handles both hosts and plain formats)
extract_domains() {
  local file="$1"
  grep -v '^[[:space:]]*#' "$file" | \
  grep -v '^[[:space:]]*$' | \
  awk '
    /^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]/ { print $2; next }
    /^[a-zA-Z0-9]/ { print $1 }
  ' | \
  tr '[:upper:]' '[:lower:]' | \
  grep -Ev '^(localhost|localhost\.localdomain|local|broadcasthost|ip6-localhost|ip6-loopback|0\.0\.0\.0)$' | \
  grep -E "$DOMAIN_RE"
}

# ---------------------------------------------------------------------------
# Prepare directories
# ---------------------------------------------------------------------------
mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"

[[ -f "$SOURCES_FILE" ]] || die "Sources file not found: $SOURCES_FILE"

# ---------------------------------------------------------------------------
# Parse sources.txt
# ---------------------------------------------------------------------------
declare -a SOURCE_NAMES=()
declare -a SOURCE_URLS=()

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue
  name=$(echo "$line" | awk '{print $1}')
  url=$(echo "$line"  | awk '{print $2}')
  [[ -z "$name" || -z "$url" ]] && continue
  SOURCE_NAMES+=("$name")
  SOURCE_URLS+=("$url")
done < "$SOURCES_FILE"

log "Loaded ${#SOURCE_NAMES[@]} sources from $SOURCES_FILE"

# ---------------------------------------------------------------------------
# Download & extract
# ---------------------------------------------------------------------------
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

# Parallel arrays to store per-source results (bash 3.2 compatible)
COUNTS_NAMES=()
COUNTS_VALUES=()
FAILED_SOURCES=()

for i in "${!SOURCE_NAMES[@]}"; do
  name="${SOURCE_NAMES[$i]}"
  url="${SOURCE_URLS[$i]}"
  cache_file="$CACHE_DIR/${name}.raw"

  log "Fetching [$name] ..."
  if curl -sL \
       --max-time "$MAX_TIMEOUT" \
       --retry 3 \
       --retry-delay 5 \
       --fail \
       -o "$cache_file" \
       "$url" 2>/dev/null; then

    # Extract to a per-source temp file first so we can count before appending
    src_tmp=$(mktemp)
    extract_domains "$cache_file" > "$src_tmp"
    count=$(wc -l < "$src_tmp" | tr -d ' ')

    if [[ "$count" -lt "$MIN_DOMAINS" ]]; then
      warn "[$name] only $count domains — skipping (below MIN_DOMAINS=$MIN_DOMAINS)"
      FAILED_SOURCES+=("$name (too few: $count)")
    else
      cat "$src_tmp" >> "$TMPFILE"
      COUNTS_NAMES+=("$name")
      COUNTS_VALUES+=("$count")
      log "  → $count domains extracted"
    fi
    rm -f "$src_tmp"
  else
    warn "[$name] download failed — skipping"
    FAILED_SOURCES+=("$name (download failed)")
  fi
done

# ---------------------------------------------------------------------------
# Deduplicate & write output
# ---------------------------------------------------------------------------
UNIQUE_COUNT=$(sort -u "$TMPFILE" | wc -l)
log "Deduplication: $(wc -l < "$TMPFILE") total → $UNIQUE_COUNT unique domains"

if [[ "$DRY_RUN" == "true" ]]; then
  log "Dry run — skipping output write."
  exit 0
fi

sort -u "$TMPFILE" > "$OUTPUT_FILE"
log "Written to $OUTPUT_FILE"

# ---------------------------------------------------------------------------
# Write stats.json
# ---------------------------------------------------------------------------
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

{
  echo "{"
  echo "  \"generated_at\": \"$TIMESTAMP\","
  echo "  \"git_sha\": \"$GIT_SHA\","
  echo "  \"total_unique_domains\": $UNIQUE_COUNT,"
  echo "  \"sources\": {"
  first=true
  for i in "${!COUNTS_NAMES[@]}"; do
    [[ "$first" == "true" ]] || echo ","
    printf '    "%s": %s' "${COUNTS_NAMES[$i]}" "${COUNTS_VALUES[$i]}"
    first=false
  done
  echo ""
  echo "  },"
  if [[ ${#FAILED_SOURCES[@]} -gt 0 ]]; then
    echo "  \"failed_sources\": ["
    for s in "${FAILED_SOURCES[@]}"; do
      echo "    \"$s\","
    done | sed '$ s/,$//'
    echo "  ]"
  else
    echo "  \"failed_sources\": []"
  fi
  echo "}"
} > "$STATS_FILE"

log "Stats written to $STATS_FILE"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "====================================================="
echo "  ChillBill77 Blocklist — Build Summary"
echo "====================================================="
echo "  Generated : $TIMESTAMP"
echo "  Output    : $OUTPUT_FILE"
printf "  %-28s %s\n" "Unique domains:" "$UNIQUE_COUNT"
echo "-----------------------------------------------------"
for i in "${!COUNTS_NAMES[@]}"; do
  printf "  %-28s %s\n" "${COUNTS_NAMES[$i]}" "${COUNTS_VALUES[$i]}"
done | sort
if [[ ${#FAILED_SOURCES[@]} -gt 0 ]]; then
  echo "-----------------------------------------------------"
  echo "  FAILED SOURCES:"
  for s in "${FAILED_SOURCES[@]}"; do
    echo "    ✗ $s"
  done
fi
echo "====================================================="