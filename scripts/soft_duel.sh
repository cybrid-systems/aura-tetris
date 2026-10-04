#!/usr/bin/env bash
# Soft duel child for tetris_play --duel.
# stdin: INPUT lines. stdout: SNAP blocks only (line-buffered).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
AURA_IN="/workspace/aura-grok/build/aura"
AURA_SRC="${AURA_SRC:-/workspace/aura-grok}"

if [[ ! -x "${AURA_SRC}/build/aura" ]]; then
  echo "soft_duel: missing executable ${AURA_SRC}/build/aura" >&2
  exit 1
fi
echo "soft_duel: AURA_SRC=${AURA_SRC}" >&2

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "soft_duel: docker not available" >&2
  exit 1
fi

EXTRA=()
if [[ -n "${TETRIS_STRATEGY_FILE:-}" ]]; then
  EXTRA+=(-e TETRIS_STRATEGY_FILE)
  if [[ -f "${TETRIS_STRATEGY_FILE}" ]]; then
    EXTRA+=(-v "${TETRIS_STRATEGY_FILE}:${TETRIS_STRATEGY_FILE}:ro")
  fi
fi

exec "${DOCKER[@]}" run --rm -i --entrypoint /usr/local/bin/gosu \
  -v "${AURA_SRC}:/workspace/aura-grok" \
  -v "${ROOT}:/workspace/aura-tetris" \
  -w /workspace/aura-tetris \
  -e AURA_PATH=/workspace/aura-grok/lib \
  -e AURA_PIPELINE_STRICT=0 \
  -e AURA_SANDBOX=off \
  -e "AURA_BIN=${AURA_IN}" \
  "${EXTRA[@]}" \
  "${IMG}" \
  dev /usr/bin/stdbuf -oL -eL "${AURA_IN}" /workspace/aura-tetris/soft/tetris/duel_main.aura
