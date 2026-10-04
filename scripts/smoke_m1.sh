#!/usr/bin/env bash
# M0 line-clear smoke must stay green, then M1 strategy swap/probe/heal,
# then a short SNAP/INPUT pipe (stdout is SNAP only).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA_SRC="${AURA_SRC:-/workspace/aura-grok}"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "smoke_m1: docker not available" >&2
  exit 1
fi

run_aura() {
  local src="$1"
  "${DOCKER[@]}" run --rm -i --entrypoint /usr/local/bin/gosu \
    -v "$AURA_SRC":/workspace/aura-grok \
    -v "$ROOT":/workspace/aura-tetris \
    -w /workspace/aura-tetris \
    -e AURA_PATH=/workspace/aura-grok/lib \
    -e AURA_PIPELINE_STRICT=0 \
    -e AURA_SANDBOX=off \
    -e AURA_BIN=/workspace/aura-grok/build/aura \
    "$IMG" \
    dev /usr/bin/stdbuf -oL -eL /workspace/aura-grok/build/aura "$src"
}

echo "smoke_m1: M0"
m0="$(run_aura /workspace/aura-tetris/soft/tetris/m0_smoke.aura)"
printf '%s\n' "$m0"
printf '%s\n' "$m0" | grep -q '^LINES=4$'
printf '%s\n' "$m0" | grep -q '^SCORE=400$'
printf '%s\n' "$m0" | grep -q '^TETRIS_M0_OK$'

echo "smoke_m1: strategy"
st="$(run_aura /workspace/aura-tetris/soft/tetris/m1_strategy_smoke.aura)"
printf '%s\n' "$st"
printf '%s\n' "$st" | grep -q '^TETRIS_M1_STRATEGY_OK$'

echo "smoke_m1: SNAP pipe"
snap="$(printf 'INPUT cw\nINPUT tick\nINPUT quit\n' | run_aura /workspace/aura-tetris/soft/tetris/play.aura)"
snaps="$(printf '%s\n' "$snap" | grep -c '^SNAP v1$' || true)"
ends="$(printf '%s\n' "$snap" | grep -c '^END$' || true)"
echo "SNAP_COUNT=$snaps END_COUNT=$ends"
if [[ "$snaps" -ne 3 || "$ends" -ne 3 ]]; then
  echo "smoke_m1: expected 3 SNAP blocks (initial, cw, tick)" >&2
  printf '%s\n' "$snap" >&2
  exit 1
fi
printf '%s\n' "$snap" | grep -q '^SCORE score='
printf '%s\n' "$snap" | grep -q '^MID mid='
printf '%s\n' "$snap" | grep -q 'rot=1'
# C is not in this pipe: score text must come from Soft, and the pipe
# must not carry the M0 banner.
if printf '%s\n' "$snap" | grep -q 'TETRIS_M0_OK'; then
  echo "smoke_m1: play stdout polluted" >&2
  exit 1
fi

echo "smoke_m1: viewport builds"
cmake -S "$ROOT/c" -B "$ROOT/build/c" >/dev/null
cmake --build "$ROOT/build/c" --parallel >/dev/null
test -x "$ROOT/build/c/tetris_play"

echo "TETRIS_M1_SMOKE_OK"
