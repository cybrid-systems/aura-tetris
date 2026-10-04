#!/usr/bin/env bash
# One command: Soft world + thin C ANSI viewport.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
echo "aura-tetris: building viewport..."
cmake -S "$ROOT/c" -B "$ROOT/build/c" >/dev/null
cmake --build "$ROOT/build/c" --parallel >/dev/null
echo "aura-tetris: Soft owns the board. C only blits SNAPs and sends keys."
echo "  a/d move | s soft | w/space hard | z/q ccw | e/x cw | c hold"
echo "  f one strategy step | p pause | r restart | Esc quit"
echo "  First Soft seed can take a bit (set-code of place-fn)."
exec "$ROOT/build/c/tetris_play" -- "$ROOT/scripts/soft_play.sh"
