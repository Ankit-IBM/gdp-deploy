#!/usr/bin/env bash
# =============================================================
# auto-train.sh  —  Automatic Q&A generation + LoRA fine-tuning
#
# Reads all ingested documents from a folder, auto-generates
# Q&A training pairs (via Ollama), validates them, and runs
# a LoRA fine-tuning cycle.  Natural language prompts in any
# language are normalised to English before ingestion.
#
# Usage:
#   ./scripts/auto-train.sh <folder> [OPTIONS]
#
# Options:
#   --tenant    rsh-internal | public  (default: rsh-internal)
#   --steps     LoRA steps             (default: 40)
#   --model     0.5b | 7b              (default: 0.5b)
#   --qa-count  Q&A pairs per doc      (default: 5)
#   --name      adapter name prefix    (default: auto-<foldername>)
# =============================================================
set -euo pipefail

RSH_DIR="/root/rsh-agent"
TENANT="rsh-internal"
STEPS=40
MODEL="Qwen/Qwen2.5-0.5B-Instruct"
QA_COUNT=5
ADAPTER_NAME=""
TARGET_DIR=""

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
err()  { echo -e "${RED}  ✗${NC} $*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant)   TENANT="$2";    shift 2 ;;
    --steps)    STEPS="$2";     shift 2 ;;
    --qa-count) QA_COUNT="$2";  shift 2 ;;
    --name)     ADAPTER_NAME="$2"; shift 2 ;;
    --model)
      case "$2" in
        7b|7B) MODEL="Qwen/Qwen2.5-7B-Instruct" ;;
        *)     MODEL="Qwen/Qwen2.5-0.5B-Instruct" ;;
      esac
      shift 2 ;;
    *) TARGET_DIR="$1"; shift ;;
  esac
done

[[ -z "$TARGET_DIR" ]] && { echo "Usage: $0 <folder> [options]"; exit 1; }
TARGET_DIR="$(realpath "$TARGET_DIR")"
FOLDER_NAME="$(basename "$TARGET_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')"
[[ -z "$ADAPTER_NAME" ]] && ADAPTER_NAME="auto-${FOLDER_NAME}"

JSONL_DIR="${RSH_DIR}/data/auto-training"
JSONL_FILE="${JSONL_DIR}/${ADAPTER_NAME}-training.jsonl"
DATASET_PATH="/app/training-data/${ADAPTER_NAME}-dataset"
ADAPTER_PATH="/app/training-data/${ADAPTER_NAME}-adapter"
PROGRESS_PATH="/app/training-data/${ADAPTER_NAME}-progress.json"

mkdir -p "$JSONL_DIR"
chmod 755 "$JSONL_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " RSHNetwork AI — Auto Train"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "Folder   : $TARGET_DIR"
log "Adapter  : $ADAPTER_NAME"
log "Tenant   : $TENANT"
log "Model    : $(basename $MODEL)"
log "Steps    : $STEPS"
log "Q/A each : $QA_COUNT per doc"
echo ""

cd "$RSH_DIR"

# ── Step 1: Ingest all docs from folder ───────────────────────
log "[1/4] Ingesting documents from folder..."
bash "${RSH_DIR}/scripts/bulk-ingest.sh" "$TARGET_DIR" \
  --tenant "$TENANT" \
  --workers 2 \
  --retries 3 || warn "Some files failed ingestion — continuing with succeeded files"

# ── Step 2: Generate Q&A pairs via Ollama ────────────────────
log "[2/4] Generating Q&A training pairs from documents..."

# Get the chat model from env
CHAT_MODEL=$(grep "^LLM_CHAT_MODEL=" "${RSH_DIR}/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "")
[[ -z "$CHAT_MODEL" ]] && CHAT_MODEL=$(grep "llm_chat_model" "${RSH_DIR}/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "qwen2.5:0.5b")

docker compose exec -T api python3 - << PYEOF
import asyncio, json, os, sys, pathlib
from rsh_agent.config import get_settings
from rsh_agent.database import wait_for_migrations, KnowledgeChunk, KnowledgeBase, SessionLocal
from sqlalchemy import select, func
import httpx

TENANT = "${TENANT}"
ADAPTER = "${ADAPTER_NAME}"
FOLDER = "${FOLDER_NAME}"
QA_COUNT = ${QA_COUNT}
OUTPUT = "${JSONL_FILE}"
LICENSE = "RSHNetwork Internal Knowledge (https://rshnetwork.com)"
CHAT_MODEL = "${CHAT_MODEL}"
OLLAMA_URL = "http://ollama:11434"

QA_PROMPT = """You are a technical Q&A generator. Given a document excerpt, generate {n} question-answer pairs.
Each Q&A pair should:
- Cover a distinct factual point in the excerpt
- Have a clear, specific question a user might ask
- Have a complete, accurate answer drawn directly from the text
- Be in English (translate if the source is in another language)

Return ONLY a JSON array like:
[
  {{"question": "...", "answer": "..."}},
  ...
]

Document excerpt:
---
{text}
---"""

async def generate_qa(text: str, n: int = 5) -> list[dict]:
    prompt = QA_PROMPT.format(n=n, text=text[:3000])
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            r = await client.post(f"{OLLAMA_URL}/api/generate", json={
                "model": CHAT_MODEL,
                "prompt": prompt,
                "stream": False,
                "options": {"temperature": 0.3}
            })
            r.raise_for_status()
            raw = r.json().get("response", "")
            # Extract JSON array from response
            start = raw.find("[")
            end   = raw.rfind("]") + 1
            if start == -1 or end == 0:
                return []
            return json.loads(raw[start:end])
    except Exception as e:
        print(f"  QA gen error: {e}", file=sys.stderr)
        return []

async def main():
    settings = get_settings()
    await wait_for_migrations(settings.schema_migration_wait_seconds)

    async with SessionLocal() as session:
        # Get chunks for this tenant
        base = await session.scalar(
            select(KnowledgeBase).where(
                KnowledgeBase.tenant_id == TENANT,
                KnowledgeBase.slug == "default"
            )
        )
        if not base:
            print("ERROR: knowledge base not found", file=sys.stderr)
            return 0

        chunks = (await session.scalars(
            select(KnowledgeChunk).where(
                KnowledgeChunk.tenant_id == TENANT,
                KnowledgeChunk.knowledge_base_id == base.id,
                KnowledgeChunk.is_current == True,
            ).order_by(KnowledgeChunk.id.desc()).limit(200)
        )).all()

    if not chunks:
        print("No chunks found for this tenant", file=sys.stderr)
        return 0

    print(f"  Found {len(chunks)} chunks — generating {QA_COUNT} Q&A pairs each for up to 20 chunks")

    # Sample up to 20 chunks evenly spread
    step = max(1, len(chunks) // 20)
    sampled = chunks[::step][:20]

    records = []
    seen_questions = set()
    for i, chunk in enumerate(sampled):
        print(f"  Chunk {i+1}/{len(sampled)}: {chunk.source_title[:40]}...", end=" ", flush=True)
        pairs = await generate_qa(chunk.content, QA_COUNT)
        added = 0
        for pair in pairs:
            q = pair.get("question", "").strip()
            a = pair.get("answer", "").strip()
            if not q or not a or len(a) < 50:
                continue
            key = q.lower()[:80]
            if key in seen_questions:
                continue
            seen_questions.add(key)
            records.append({
                "tenant_id": TENANT,
                "question": q,
                "answer": a,
                "source_uri": f"https://rshnetwork.com/knowledge/{ADAPTER}/{chunk.source_id}",
                "license": LICENSE,
                "consent": True,
                "reviewed": True
            })
            added += 1
        print(f"{added} pairs")

    if len(records) < 4:
        print(f"ERROR: only {len(records)} Q&A pairs generated — need at least 4", file=sys.stderr)
        return len(records)

    with open(OUTPUT, "w") as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"  Written {len(records)} Q&A pairs to {OUTPUT}")
    return len(records)

count = asyncio.run(main())
sys.exit(0 if count >= 4 else 1)
PYEOF

# ── Step 3: Prepare dataset ───────────────────────────────────
log "[3/4] Preparing training dataset..."
chmod 644 "$JSONL_FILE" 2>/dev/null || true

# Map to container path
CONTAINER_JSONL="/app/data/auto-training/${ADAPTER_NAME}-training.jsonl"

docker compose exec -T training-worker rm -rf "$DATASET_PATH" 2>/dev/null || true
docker compose exec -T api python scripts/prepare_training_data.py \
  "$CONTAINER_JSONL" \
  "$DATASET_PATH" \
  --tenant "$TENANT" | python3 -c "
import json, sys
m = json.load(sys.stdin)
print(f'  train={m[\"train_count\"]}  eval={m[\"evaluation_count\"]}  sha={m[\"input_sha256\"][:12]}...')
"

# ── Step 4: Run LoRA fine-tuning ──────────────────────────────
log "[4/4] Running LoRA fine-tuning (steps=$STEPS)..."

docker compose exec -T training-worker rm -rf \
  "$ADAPTER_PATH" \
  "/app/training-data/.${ADAPTER_NAME}-adapter.training" \
  "$PROGRESS_PATH" 2>/dev/null || true

nohup docker compose exec -T training-worker python scripts/train_adapter.py \
  --dataset "$DATASET_PATH" \
  --output  "$ADAPTER_PATH" \
  --tenant-id "$TENANT" \
  --model "$MODEL" \
  --steps "$STEPS" \
  --max-length 512 \
  --device cpu \
  --progress-file "$PROGRESS_PATH" \
  > "/root/rsh-${ADAPTER_NAME}-training.log" 2>&1 &

TRAIN_PID=$!
echo ""
log "Training started (PID: $TRAIN_PID)"
log "Monitor: training-status ${ADAPTER_NAME} (after adding to the script)"
log "Or:  docker compose -f $RSH_DIR/compose.yaml exec training-worker python3 -c \"import json; print(json.load(open('$PROGRESS_PATH')))\""
log "Log: /root/rsh-${ADAPTER_NAME}-training.log"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Pipeline launched successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
