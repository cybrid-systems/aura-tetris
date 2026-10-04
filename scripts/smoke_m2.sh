#!/usr/bin/env bash
# M2: duel worldlines, explain mid/reason, storm bag. Does not replace M0/M1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA_SRC="${AURA_SRC:-/workspace/aura-grok}"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "smoke_m2: docker not available" >&2
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

echo "smoke_m2: duel"
duel="$(run_aura /workspace/aura-tetris/soft/tetris/m2_duel_smoke.aura)"
printf '%s\n' "$duel"
printf '%s\n' "$duel" | grep -q '^TETRIS_M2_DUEL_OK$'
printf '%s\n' "$duel" | grep -q '^WINNER mid='
printf '%s\n' "$duel" | grep -q '^reason='

echo "smoke_m2: explain"
ex="$(run_aura /workspace/aura-tetris/soft/tetris/m2_explain_smoke.aura)"
printf '%s\n' "$ex"
printf '%s\n' "$ex" | grep -q '^mid='
printf '%s\n' "$ex" | grep -q '^reason='
printf '%s\n' "$ex" | grep -q '^TETRIS_M2_EXPLAIN_OK$'

echo "smoke_m2: storm"
st="$(run_aura /workspace/aura-tetris/soft/tetris/m2_storm_smoke.aura)"
printf '%s\n' "$st"
printf '%s\n' "$st" | grep -q '^reason='
printf '%s\n' "$st" | grep -q '^TETRIS_M2_STORM_OK$'

echo "smoke_m2: duel SNAP pipe"
snap="$(printf 'INPUT tick\nINPUT auto\nINPUT toggle\nINPUT quit\n' | run_aura /workspace/aura-tetris/soft/tetris/duel_main.aura)"
snaps="$(printf '%s\n' "$snap" | grep -c '^SNAP v1$' || true)"
ends="$(printf '%s\n' "$snap" | grep -c '^END$' || true)"
echo "SNAP_COUNT=$snaps END_COUNT=$ends"
if [[ "$snaps" -ne 4 || "$ends" -ne 4 ]]; then
  echo "smoke_m2: expected 4 SNAP blocks (initial, tick, auto, toggle)" >&2
  printf '%s\n' "$snap" >&2
  exit 1
fi
printf '%s\n' "$snap" | grep -q '^BOARD2$'
printf '%s\n' "$snap" | grep -q '^WINNER mid='
printf '%s\n' "$snap" | grep -q '^EXPLAIN mid='
printf '%s\n' "$snap" | grep -q '^MID mid='
# toggle flips the pilot. Initial snap is L; after toggle the last PILOT is R.
pilots="$(printf '%s\n' "$snap" | grep '^PILOT side=' | tail -n 1)"
echo "LAST_$pilots"
if [[ "$pilots" != "PILOT side=R" ]]; then
  echo "smoke_m2: toggle did not move the pilot to R" >&2
  exit 1
fi

echo "TETRIS_M2_SMOKE_OK"
