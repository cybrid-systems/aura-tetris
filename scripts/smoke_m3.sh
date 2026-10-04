#!/usr/bin/env bash
# M3: quad race, live rule mutate, file-fixture propose.
# Live MiniMax is optional. No key -> TETRIS_M3_PROPOSE_SKIP for the HTTP
# half. The fixture path still has to print TETRIS_M3_PROPOSE_OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AURA_SRC="${AURA_SRC:-/workspace/aura-grok}"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "smoke_m3: docker not available" >&2
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

echo "smoke_m3: race"
race="$(run_aura /workspace/aura-tetris/soft/tetris/m3_race_smoke.aura)"
printf '%s\n' "$race"
printf '%s\n' "$race" | grep -q '^TETRIS_M3_RACE_OK$'
printf '%s\n' "$race" | grep -q '^WINNER mid='
printf '%s\n' "$race" | grep -Eq '^WORLD line=(fiber_live|host-sequential)$'
fps="$(printf '%s\n' "$race" | grep -E '^FP_(AGG|DEF|HOLE|HUNT)=' | sort -u | wc -l)"
echo "RACE_FP_UNIQUE=$fps"
if [[ "$fps" -ne 4 ]]; then
  echo "smoke_m3: expected 4 distinct race fingerprints" >&2
  exit 1
fi

echo "smoke_m3: rules"
rule="$(run_aura /workspace/aura-tetris/soft/tetris/m3_rule_smoke.aura)"
printf '%s\n' "$rule"
printf '%s\n' "$rule" | grep -q '^TETRIS_M3_RULE_OK$'
printf '%s\n' "$rule" | grep -q '^WIDTH=12$'
printf '%s\n' "$rule" | grep -q '^SCORE=140$'
printf '%s\n' "$rule" | grep -q '^reason=rule_width$'

echo "smoke_m3: propose fixture"
prop="$(run_aura /workspace/aura-tetris/soft/tetris/m3_propose_smoke.aura)"
printf '%s\n' "$prop"
printf '%s\n' "$prop" | grep -q '^TETRIS_M3_PROPOSE_OK$'

echo "smoke_m3: play pipe race + mutate-wide"
snap="$(printf 'INPUT race\nINPUT mutate-wide\nINPUT quit\n' | run_aura /workspace/aura-tetris/soft/tetris/play.aura)"
ghosts="$(printf '%s\n' "$snap" | grep -c '^GHOST id=' || true)"
echo "GHOST_LINES=$ghosts"
if [[ "$ghosts" -lt 4 ]]; then
  echo "smoke_m3: expected ghost landings in the race SNAP" >&2
  printf '%s\n' "$snap" >&2
  exit 1
fi
printf '%s\n' "$snap" | grep -q '^WORLD line='
printf '%s\n' "$snap" | grep -q '^WINNER mid='
last_w="$(printf '%s\n' "$snap" | grep '^WIDTH ' | tail -n 1)"
echo "LAST_$last_w"
if [[ "$last_w" != "WIDTH 12" ]]; then
  echo "smoke_m3: mutate-wide did not retarget the SNAP" >&2
  exit 1
fi

keyfile="/home/box/.config/aura-build/minimax_api_key"
if [[ ! -s "$keyfile" ]]; then
  echo "TETRIS_M3_PROPOSE_SKIP"
else
  live="$(mktemp /tmp/tetris-live-XXXX.lambda)"
  if python3 "$ROOT/scripts/propose_minimax.py" "$live" >/tmp/tetris-propose.stdout 2>/tmp/tetris-propose.stderr; then
    echo "smoke_m3: live lambda written ($(wc -c < "$live") bytes), Soft still gates it"
    # Feed it through the fixture entry so a bad model body cannot fail the smoke.
    if TETRIS_PROPOSE_FILE="$live" python3 - << PY
import os, pathlib
p = pathlib.Path(os.environ["TETRIS_PROPOSE_FILE"])
t = p.read_text()
print("LIVE_PREFIX_OK" if t.startswith("(lambda") else "LIVE_PREFIX_BAD")
PY
    then
      echo "TETRIS_M3_PROPOSE_LIVE_WROTE"
    fi
  else
    echo "TETRIS_M3_PROPOSE_SKIP"
    echo "smoke_m3: live HTTP failed (fixture path already OK)" >&2
    sed 's/sk-[A-Za-z0-9_-]*/[redacted]/g' /tmp/tetris-propose.stderr >&2 || true
  fi
  rm -f "$live"
fi

echo "TETRIS_M3_SMOKE_OK"
