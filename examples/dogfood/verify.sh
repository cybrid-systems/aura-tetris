#!/usr/bin/env bash
# Exit 0 iff candidate prints LINES=4 / SCORE=400 / TETRIS_M0_OK and defines helpers.
set -euo pipefail
CAND="${1:-}"
if [[ -z "$CAND" || ! -f "$CAND" ]]; then
  echo "usage: verify.sh <candidate.aura>" >&2
  exit 2
fi

src="$(cat "$CAND")"
if ! printf '%s\n' "$src" | grep -qE '\(define[[:space:]]+\(score-for([[:space:]]|\))'; then
  echo "verify fail: missing (define (score-for …)" >&2
  exit 1
fi
if ! printf '%s\n' "$src" | grep -qE '\(define[[:space:]]+\(tetris:(clear-lines!|hard-drop!)([[:space:]]|\))'; then
  echo "verify fail: missing (define (tetris:clear-lines! …) or (define (tetris:hard-drop! …)" >&2
  exit 1
fi

AURA_SRC="${AURA_SRC:-/workspace/aura-grok}"
IMG="ghcr.io/cybrid-systems/dev:v1.0.9"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

run_aura() {
  local cand="$1"
  if [[ -n "${AURA_BIN:-}" && -x "${AURA_BIN}" ]] && "${AURA_BIN}" -e '(display 1)' >/dev/null 2>&1; then
    AURA_SANDBOX="${AURA_SANDBOX:-off}" AURA_PIPELINE_STRICT="${AURA_PIPELINE_STRICT:-0}" \
      AURA_PATH="${AURA_PATH:-$AURA_SRC/lib}" \
      "$AURA_BIN" "$cand" 2>&1 || true
    return
  fi
  if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
  elif sudo docker info >/dev/null 2>&1; then
    DOCKER=(sudo docker)
  else
    echo "verify fail: no usable AURA_BIN and no docker" >&2
    exit 2
  fi
  local abs
  abs="$(cd "$(dirname "$cand")" && pwd)/$(basename "$cand")"
  "${DOCKER[@]}" run --rm --entrypoint /usr/local/bin/gosu \
    -v "$AURA_SRC":/workspace/aura-grok \
    -v "$ROOT":/workspace/aura-tetris \
    -v "$abs":/tmp/candidate.aura:ro \
    -w /workspace/aura-tetris \
    -e AURA_PATH=/workspace/aura-grok/lib \
    -e AURA_PIPELINE_STRICT=0 \
    -e AURA_SANDBOX=off \
    "$IMG" \
    dev /workspace/aura-grok/build/aura /tmp/candidate.aura 2>&1 || true
}

out="$(run_aura "$CAND")"
printf '%s\n' "$out"
ok=1
printf '%s\n' "$out" | grep -qE 'LINES[[:space:]]*=[[:space:]]*4' || ok=0
printf '%s\n' "$out" | grep -qE 'SCORE[[:space:]]*=[[:space:]]*400' || ok=0
printf '%s\n' "$out" | grep -q 'TETRIS_M0_OK' || ok=0
if printf '%s\n' "$out" | grep -qiE '\berror:|\bunbound variable\b'; then
  ok=0
fi
if [[ "$ok" -eq 1 ]]; then
  echo "verify ok LINES=4 SCORE=400 TETRIS_M0_OK"
  exit 0
fi
echo "verify fail (expected LINES=4 / SCORE=400 / TETRIS_M0_OK + score-for + tetris clear/drop)" >&2
exit 1
