#!/usr/bin/env bash
# Split ANSI duel. Soft owns both boards. C only blits.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
echo "aura-tetris: building viewport..."
cmake -S "$ROOT/c" -B "$ROOT/build/c" >/dev/null
cmake --build "$ROOT/build/c" --parallel >/dev/null
echo "aura-tetris duel: left aggressive, right defensive, same bag."
echo "  keys pilot the highlighted side (start LEFT). t toggles."
echo "  f auto-steps BOTH boards. Right (or the side you are not on) also"
echo "  auto-steps on gravity. v races the piloted board. m cycles rules."
echo "  u proposes a place-fn. Esc / Q quits."
echo "  First Soft seed can take a bit (set-code of the place-fn worldlines)."
exec "$ROOT/build/c/tetris_play" --duel -- "$ROOT/scripts/soft_duel.sh"
