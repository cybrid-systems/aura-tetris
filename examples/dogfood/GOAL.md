# aura-tetris dogfood — success predicate

Write a small **Aura Soft** program that implements Tetris line-clear helpers and
prints exactly these lines (each plus a trailing newline):

```
LINES=4
SCORE=400
TETRIS_M0_OK
```

## Semantics

Board is **10×20**. Scoring: clearing `n` lines at once awards
`100/300/500/800 × level` for `n=1/2/3/4`. `level = 1 + floor(lines/10)`.

Deterministic sequence (level stays 1):

1. Start empty.
2. Four times: fill bottom row columns `0..5`, spawn horizontal **I** covering
   columns `6..9`, hard-drop → clear exactly one line each time.
3. After four clears: `LINES=4`, `SCORE=400` (`4 × 100 × level1`).

## Required structure

- Must define helpers used by the sequence, e.g. `(define (tetris:clear-lines! …) …)`
  and/or `(define (tetris:hard-drop! …) …)` / `(define (score-for …) …)` so scoring
  is real (not only hardcoded display strings).
- Prefer `display` / `newline` / `set!` / vectors or lists for the board.
- Hardcoding only the three display literals without real clear/score logic is a fail.

## Why stub starts wrong

`stub.aura` intentionally clears wrong / scores wrong so aura-build’s MiniMax
propose → Aura verify → repair loop has real work.
