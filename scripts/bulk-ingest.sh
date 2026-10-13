#!/usr/bin/env bash
# =============================================================
# bulk-ingest.sh  —  Server-side bulk document ingestion
# Walks any folder recursively, ingests every supported file
# into pgvector with progress reporting, retry on failure,
# and optional self-training trigger.
#
# Usage:
#   ./scripts/bulk-ingest.sh /path/to/docs [OPTIONS]
#
# Options:
#   --tenant      rsh-internal | public  (default: rsh-internal)
#   --base        knowledge base slug    (default: default)
#   --source-id   custom source prefix  (default: derived from folder name)
#   --workers     parallel jobs         (default: 3)
#   --retries     per-file retries      (default: 2)
#   --train       trigger self-training after ingestion
#   --steps       LoRA training steps   (default: 40)
#   --dry-run     list files only, do not ingest
# =============================================================
set -euo pipefail

RSH_DIR="/root/rsh-agent"
TENANT="rsh-internal"
BASE_SLUG="default"
SOURCE_PREFIX=""
WORKERS=3
RETRIES=2
DO_TRAIN=false
TRAIN_STEPS=40
DRY_RUN=false
TARGET_DIR=""

# ── Supported extensions ──────────────────────────────────────
SUPPORTED_EXTS="pdf docx epub txt md csv xls xlsx json yaml yml xml html htm log png jpg jpeg webp bmp tif tiff"

# ── Colour output ─────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
err()  { echo -e "${RED}  ✗${NC} $*"; }

# ── Argument parsing ──────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)    TENANT="$2";       shift 2 ;;
    --base)      BASE_SLUG="$2";    shift 2 ;;
    --source-id) SOURCE_PREFIX="$2";shift 2 ;;
    --workers)   WORKERS="$2";      shift 2 ;;
    --retries)   RETRIES="$2";      shift 2 ;;
    --steps)     TRAIN_STEPS="$2";  shift 2 ;;
    --train)     DO_TRAIN=true;     shift ;;
    --dry-run)   DRY_RUN=true;      shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | grep "^#" | sed 's/^# \?//'
      exit 0 ;;
    -*)  echo "Unknown option: $1"; exit 1 ;;
    *)   TARGET_DIR="$1"; shift ;;
  esac
done

[[ -z "$TARGET_DIR" ]] && { echo "Usage: $0 <folder> [options]"; exit 1; }
[[ ! -d "$TARGET_DIR" ]] && { err "Not a directory: $TARGET_DIR"; exit 1; }

TARGET_DIR="$(realpath "$TARGET_DIR")"
FOLDER_NAME="$(basename "$TARGET_DIR")"
[[ -z "$SOURCE_PREFIX" ]] && SOURCE_PREFIX="$(echo "$FOLDER_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g; s/^-//; s/-$//')"

# ── Build file list ───────────────────────────────────────────
declare -a FILES=()
while IFS= read -r -d '' f; do
  ext="${f##*.}"
  ext="${ext,,}"
  for s in $SUPPORTED_EXTS; do
    if [[ "$ext" == "$s" ]]; then
      FILES+=("$f")
      break
    fi
  done
done < <(find "$TARGET_DIR" -type f -print0 | sort -z)

TOTAL=${#FILES[@]}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " RSHNetwork AI — Bulk Ingest"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Folder   : $TARGET_DIR"
log "Files    : $TOTAL supported files found"
log "Tenant   : $TENANT"
log "Base     : $BASE_SLUG"
log "Source   : $SOURCE_PREFIX"
log "Workers  : $WORKERS"
log "Retries  : $RETRIES"
$DO_TRAIN && log "Training : enabled (steps=$TRAIN_STEPS)"
echo ""

if [[ "$TOTAL" -eq 0 ]]; then
  warn "No supported files found. Supported: $SUPPORTED_EXTS"
  exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY RUN — files that would be ingested:"
  for f in "${FILES[@]}"; do echo "  $f"; done
  exit 0
fi

cd "$RSH_DIR"

# ── State tracking ────────────────────────────────────────────
PASS=0; FAIL=0; SKIP=0
FAILED_FILES=()
TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# ── Ingest a single file with retry ──────────────────────────
ingest_file() {
  local fpath="$1"
  local idx="$2"
  local fname="$(basename "$fpath")"
  local rel="${fpath#$TARGET_DIR/}"
  # Derive source-id from relative path (folder/file without ext)
  local sid="${SOURCE_PREFIX}/$(echo "${rel%.*}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9/_-]/-/g')"
  # Map into container path — TARGET_DIR must be under /root/rsh-agent/data or we copy it
  local container_path=""
  if [[ "$fpath" == /root/rsh-agent/data/* ]]; then
    container_path="/app/data/${fpath#/root/rsh-agent/data/}"
  else
    # Copy file into data dir temporarily
    local tmpname="bulk-ingest-$(date +%s%N)"
    mkdir -p "${RSH_DIR}/data/.bulk-tmp"
    cp "$fpath" "${RSH_DIR}/data/.bulk-tmp/${tmpname}.${fname##*.}"
    container_path="/app/data/.bulk-tmp/${tmpname}.${fname##*.}"
  fi

  local attempt=0
  while [[ $attempt -le $RETRIES ]]; do
    attempt=$((attempt + 1))
    local result
    result=$(docker compose exec -T api python scripts/ingest.py \
      "$container_path" \
      --tenant "$TENANT" \
      --source-id "$sid" \
      --classification internal 2>&1) && {
        # Clean up tmp copy if needed
        [[ "$container_path" == /app/data/.bulk-tmp/* ]] && \
          rm -f "${RSH_DIR}/data/.bulk-tmp/${container_path##*/}"
        echo "ok:$result"
        return 0
      }
    local exit_code=$?
    if [[ $attempt -le $RETRIES ]]; then
      warn "[$idx/$TOTAL] Attempt $attempt failed: $fname — retrying in 3s..."
      sleep 3
    fi
  done
  # Clean up tmp copy
  [[ "$container_path" == /app/data/.bulk-tmp/* ]] && \
    rm -f "${RSH_DIR}/data/.bulk-tmp/${container_path##*/}"
  echo "fail:$result"
  return 1
}

export -f ingest_file
export RSH_DIR TENANT BASE_SLUG SOURCE_PREFIX TARGET_DIR RETRIES

# ── Process files (with limited parallelism via xargs) ───────
log "Starting ingestion (${WORKERS} parallel workers)..."
echo ""

IDX=0
declare -a PIDS=()
declare -a JOB_FILES=()

for fpath in "${FILES[@]}"; do
  IDX=$((IDX + 1))
  fname="$(basename "$fpath")"

  (
    result=$(ingest_file "$fpath" "$IDX")
    status="${result%%:*}"
    detail="${result#*:}"
    if [[ "$status" == "ok" ]]; then
      echo "OK|$fname|$detail"
    else
      echo "FAIL|$fname|$detail"
    fi
  ) > "$TMPDIR_WORK/result-$IDX" 2>&1 &

  PIDS+=($!)
  JOB_FILES+=("$fname")

  # Drain when we hit worker limit
  if [[ ${#PIDS[@]} -ge $WORKERS ]]; then
    for i in "${!PIDS[@]}"; do
      wait "${PIDS[$i]}" 2>/dev/null || true
      r="$(cat "$TMPDIR_WORK/result-$((IDX - WORKERS + 1 + i))" 2>/dev/null)"
      st="${r%%|*}"; rest="${r#*|}"; fn="${rest%%|*}"; detail="${rest#*|}"
      if [[ "$st" == "OK" ]]; then
        ok "[$((IDX - WORKERS + 1 + i))/$TOTAL] $fn — $detail"
        PASS=$((PASS + 1))
      else
        err "[$((IDX - WORKERS + 1 + i))/$TOTAL] $fn — FAILED: ${detail:0:120}"
        FAIL=$((FAIL + 1))
        FAILED_FILES+=("${JOB_FILES[$i]}")
      fi
    done
    PIDS=(); JOB_FILES=()
  fi
done

# ── Drain remaining jobs ──────────────────────────────────────
REMAIN_START=$((IDX - ${#PIDS[@]} + 1))
for i in "${!PIDS[@]}"; do
  wait "${PIDS[$i]}" 2>/dev/null || true
  r="$(cat "$TMPDIR_WORK/result-$((REMAIN_START + i))" 2>/dev/null)"
  st="${r%%|*}"; rest="${r#*|}"; fn="${rest%%|*}"; detail="${rest#*|}"
  if [[ "$st" == "OK" ]]; then
    ok "[$((REMAIN_START + i))/$TOTAL] $fn — $detail"
    PASS=$((PASS + 1))
  else
    err "[$((REMAIN_START + i))/$TOTAL] $fn — FAILED: ${detail:0:120}"
    FAIL=$((FAIL + 1))
    FAILED_FILES+=("${JOB_FILES[$i]}")
  fi
done

# ── Summary ───────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Ingestion Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok  "Succeeded : $PASS / $TOTAL"
[[ $FAIL -gt 0 ]] && err "Failed    : $FAIL / $TOTAL"
[[ $SKIP -gt 0 ]] && warn "Skipped   : $SKIP / $TOTAL"

if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
  echo ""
  warn "Failed files:"
  for f in "${FAILED_FILES[@]}"; do echo "    $f"; done
  echo ""
  warn "Re-run with --retries 5 for persistent failures"
  warn "Or check: docker compose -f $RSH_DIR/compose.yaml exec -T db psql -U rsh_agent -d rsh_agent -c \"SELECT id,source_id,status,error FROM ingestion_jobs WHERE status='failed' ORDER BY id DESC LIMIT 10;\""
fi

# ── Optional self-training trigger ───────────────────────────
if [[ "$DO_TRAIN" == "true" && "$PASS" -gt 0 ]]; then
  echo ""
  log "Triggering self-training pipeline (steps=$TRAIN_STEPS)..."
  ADAPTER_NAME="${SOURCE_PREFIX//\//-}-adapter"
  DATASET_NAME="${SOURCE_PREFIX//\//-}-dataset"
  PROGRESS_FILE="/app/training-data/${ADAPTER_NAME}-progress.json"

  # Can only fine-tune from JSONL — notify the user to generate Q&A from ingested content
  log "Knowledge ingested into pgvector — immediately available for retrieval."
  log "To create a fine-tuned LoRA adapter from this content:"
  log "  1. Generate Q&A pairs from the documents"
  log "  2. Save as /root/rsh-agent/data/${SOURCE_PREFIX}/training.jsonl"
  log "  3. Run: bash $RSH_DIR/scripts/train-coding.sh (or equivalent)"
  echo ""
  log "Or use the auto-train script to generate Q&A automatically:"
  log "  bash $RSH_DIR/scripts/auto-train.sh $TARGET_DIR --tenant $TENANT"
fi

echo ""
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
