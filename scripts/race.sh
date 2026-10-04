#!/usr/bin/env bash
# Interactive board with the M3 keys highlighted. Same viewport as play.sh.
# v races four worldlines, m cycles rules, u asks MiniMax (host Python).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "aura-tetris race mode"
echo "  v quad worldline (agg / def / hole-fill / tetris-hunt)"
echo "  m cycle rules: width 12, then ghost-bonus score, then heal"
echo "  u propose a place-fn via scripts/propose_minimax.py (HTTP on the host)"
exec "$ROOT/scripts/play.sh"
