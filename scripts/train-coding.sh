#!/usr/bin/env bash
# train-coding.sh — re-ingest coding knowledge and run LoRA fine-tuning
set -euo pipefail
RSH_DIR="/root/rsh-agent"
TENANT="rsh-internal"
STEPS="${1:-40}"
MODEL="Qwen/Qwen2.5-0.5B-Instruct"
cd "$RSH_DIR"
echo "[1/3] Ingesting coding Markdown..."
chmod 644 data/coding/coding-knowledge.md data/coding/coding-training.jsonl
docker compose exec -T api python scripts/ingest.py \
  /app/data/coding/coding-knowledge.md \
  --tenant $TENANT --source-id coding-knowledge \
  --uri https://docs.python.org/3/ --classification internal
echo "[2/3] Preparing dataset..."
docker compose exec -T training-worker rm -rf /app/training-data/coding-dataset 2>/dev/null || true
docker compose exec -T api python scripts/prepare_training_data.py \
  /app/data/coding/coding-training.jsonl \
  /app/training-data/coding-dataset --tenant $TENANT
echo "[3/3] Launching training (steps=$STEPS)..."
docker compose exec -T training-worker rm -rf \
  /app/training-data/coding-adapter \
  /app/training-data/coding-progress.json 2>/dev/null || true
nohup docker compose exec -T training-worker python scripts/train_adapter.py \
  --dataset /app/training-data/coding-dataset \
  --output  /app/training-data/coding-adapter \
  --tenant-id $TENANT --model $MODEL \
  --steps $STEPS --max-length 512 --device cpu \
  --progress-file /app/training-data/coding-progress.json \
  > /root/rsh-coding-training.log 2>&1 &
echo "Training PID: $! | Log: /root/rsh-coding-training.log"
