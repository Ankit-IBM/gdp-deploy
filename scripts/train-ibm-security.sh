#!/usr/bin/env bash
# ============================================================
# train-ibm-security.sh
# Re-ingest IBM Security knowledge and run LoRA fine-tuning
# for the rsh-agent system.
#
# Usage: ./train-ibm-security.sh [--steps N] [--model 0.5b|7b]
# ============================================================
set -euo pipefail

RSH_DIR="/root/rsh-agent"
DATA_DIR="${RSH_DIR}/data/ibm-security"
TRAINING_DATA_DIR="/app/training-data"   # inside container
DATASET_NAME="ibm-security-dataset"
ADAPTER_NAME="ibm-security-adapter"
TENANT="rsh-internal"
STEPS=30
MAX_LENGTH=512
MODEL="Qwen/Qwen2.5-0.5B-Instruct"

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --steps)   STEPS="$2";  shift 2 ;;
    --model)
      case "$2" in
        7b|7B)  MODEL="Qwen/Qwen2.5-7B-Instruct" ;;
        *)      MODEL="Qwen/Qwen2.5-0.5B-Instruct" ;;
      esac
      shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

cd "${RSH_DIR}"

echo ""
echo "=== IBM Security rsh-agent Training Pipeline ==="
echo "Tenant   : ${TENANT}"
echo "Model    : ${MODEL}"
echo "Steps    : ${STEPS}"
echo "Max-len  : ${MAX_LENGTH}"
echo ""

# ── Step 1: Ingest Markdown knowledge into pgvector ──────────────
echo "[1/4] Ingesting Markdown knowledge file into pgvector..."
docker compose exec -T api python scripts/ingest.py \
  /app/data/ibm-security/ibm-security-products-knowledge.md \
  --tenant "${TENANT}" \
  --source-id ibm-security-products \
  --uri https://www.ibm.com/docs/en/security \
  --classification internal
echo "      Done."

# ── Step 2: Validate JSONL ────────────────────────────────────────
echo "[2/4] Validating training JSONL..."
python3 - << 'PYEOF'
import json, sys
path = "/root/rsh-agent/data/ibm-security/ibm-security-training.jsonl"
errors = []
source_uris = set()
count = 0
with open(path) as f:
    for i, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            for field in ["tenant_id","question","answer","source_uri","license","consent","reviewed"]:
                if field not in obj:
                    errors.append(f"Line {i}: missing {field}")
            source_uris.add(obj.get("source_uri",""))
            count += 1
        except Exception as e:
            errors.append(f"Line {i}: {e}")
if errors:
    for e in errors:
        print("ERROR:", e, file=sys.stderr)
    sys.exit(1)
if len(source_uris) < 2:
    print("ERROR: need ≥2 distinct source_uris", file=sys.stderr)
    sys.exit(1)
print(f"      {count} records validated, {len(source_uris)} distinct sources. OK.")
PYEOF

# ── Step 3: Prepare training dataset ─────────────────────────────
echo "[3/4] Preparing training/evaluation split..."
docker compose exec -T training-worker rm -rf \
  "${TRAINING_DATA_DIR}/${DATASET_NAME}" \
  "${TRAINING_DATA_DIR}/.${DATASET_NAME}.tmp" 2>/dev/null || true

docker compose exec -T api python scripts/prepare_training_data.py \
  /app/data/ibm-security/ibm-security-training.jsonl \
  "${TRAINING_DATA_DIR}/${DATASET_NAME}" \
  --tenant "${TENANT}" | python3 -c "
import json,sys
m=json.load(sys.stdin)
print(f'      train={m[\"train_count\"]}  eval={m[\"evaluation_count\"]}  sha256={m[\"input_sha256\"][:16]}...')
"

# ── Step 4: Run LoRA fine-tuning ──────────────────────────────────
PROGRESS_FILE="${TRAINING_DATA_DIR}/ibm-security-progress.json"
ADAPTER_OUT="${TRAINING_DATA_DIR}/${ADAPTER_NAME}"

echo "[4/4] Running LoRA fine-tuning (steps=${STEPS}, model=$(basename ${MODEL}))..."
echo "      Progress file: ${PROGRESS_FILE}"
echo "      Output adapter: ${ADAPTER_OUT}"
echo "      Logs: /root/rsh-agent-training.log"
echo ""

# Remove stale output
docker compose exec -T training-worker sh -c \
  "rm -rf '${ADAPTER_OUT}' '${PROGRESS_FILE}' '/app/training-data/.${ADAPTER_NAME}.training'" 2>/dev/null || true

# Run training in background with live progress tail
nohup docker compose exec -T training-worker python scripts/train_adapter.py \
  --dataset "${TRAINING_DATA_DIR}/${DATASET_NAME}" \
  --output  "${ADAPTER_OUT}" \
  --tenant-id "${TENANT}" \
  --model "${MODEL}" \
  --steps "${STEPS}" \
  --max-length "${MAX_LENGTH}" \
  --device cpu \
  --progress-file "${PROGRESS_FILE}" \
  > /root/rsh-agent-training.log 2>&1 &

TRAIN_PID=$!
echo "Training PID: ${TRAIN_PID}"
echo "Waiting for completion (tail /root/rsh-agent-training.log for live output)..."

# Tail progress until done
while kill -0 "${TRAIN_PID}" 2>/dev/null; do
  if [ -f "/root/rsh-agent/data/training-progress-proxy.json" ] || \
     docker compose exec -T training-worker test -f "${PROGRESS_FILE}" 2>/dev/null; then
    STAGE=$(docker compose exec -T training-worker sh -c \
      "python3 -c \"import json; d=json.load(open('${PROGRESS_FILE}')); print(d.get('stage','?'), d.get('step',0), '/', d.get('total_steps',0))\" 2>/dev/null" || echo "loading...")
    echo "  [progress] ${STAGE}"
  fi
  sleep 15
done

wait "${TRAIN_PID}" && STATUS=0 || STATUS=$?

if [ "${STATUS}" -eq 0 ]; then
  echo ""
  echo "=== Training complete ==="
  docker compose exec -T training-worker python3 -c "
import json
r = json.load(open('${ADAPTER_OUT}/trial_report.json'))
print(f'  Base model   : {r[\"base_model\"]}')
print(f'  Tenant       : {r[\"tenant_id\"]}')
print(f'  Steps        : {r[\"steps\"]}')
print(f'  Loss before  : {r[\"held_out_loss_before\"]:.4f}')
print(f'  Loss after   : {r[\"held_out_loss_after\"]:.4f}')
print(f'  Device       : {r[\"device\"]}')
" 2>/dev/null || cat /root/rsh-agent-training.log | tail -5
else
  echo "Training failed (exit ${STATUS}). Check /root/rsh-agent-training.log"
  tail -20 /root/rsh-agent-training.log
  exit "${STATUS}"
fi
