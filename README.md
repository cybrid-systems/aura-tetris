# aura-tetris

Aura Tetris is a live Soft world. The board, pieces, lock, line clear, and
score are a Soft FlatAST program. A thin C viewport only blits `SNAP` frames
and turns keys into `INPUT` lines. Classic controls are hygiene; the product
is a hot-swappable placement strategy (`hot-strategy:swap!` / `heal!`) that
Soft gates before it can touch the match.

Design: [`docs/DESIGN.md`](docs/DESIGN.md).
Repo: https://github.com/cybrid-systems/aura-tetris

Also an [aura-build](https://github.com/cybrid-systems/aura-build) dogfood
project under `examples/dogfood/`.

## Play

```bash
bash scripts/play.sh   # one board
bash scripts/duel.sh   # two boards, same bag, split ANSI
```

`scripts/duel.sh` is the M2 duel. Soft runs two matrices on one shared 7-bag.
The left worldline is aggressive (`tetris:place-agg`, deeper and righter).
The right worldline is defensive (`tetris:place-def`, shallower and lefter).
Keys pilot the left board until `t` toggles. The other board auto-plays its
place-fn on each gravity tick. `f` auto-steps both. C only blits `BOARD` and
`BOARD2`. Score and the winner `mid` / `reason` (`lines_lead`, `survive`, …)
stay in Soft.

Soft seed (`set-code` of `tetris:place-fn`) runs once at startup inside
`ghcr.io/cybrid-systems/dev:v1.0.9`. Then:

| Key | INPUT | Effect (Soft) |
|-----|--------|----------------|
| a / d / arrows | `left` / `right` | move |
| s / down | `soft` | one row |
| w / space / up | `hard` | hard drop + lock |
| z / q | `ccw` | rotate counter-clockwise |
| e / x | `cw` | rotate clockwise |
| c | `hold` | hold (once per piece) |
| f | `auto` | one step of `tetris:choose-move` |
| t | `toggle` | duel only: pilot the other board |
| p | — | pause (C stops sending `tick`) |
| r | `restart` | Soft reset, same strategy slot |
| Esc / Q | `quit` | leave |

`q` rotates. Quit is Esc or uppercase `Q`, so it does not fight the rotate key.

C never clears a line and never adds to the score. Gravity timing is Soft:
each `tick` from the viewport counts, and a row falls every `max(2, 16-level)` ticks.

To drop a proposed strategy in mid-game, set `TETRIS_STRATEGY_FILE` to a file
whose contents are a single `(lambda (board piece) …)` body. Soft reads it
once on the first `INPUT`, rejects bodies that mention `set!`, `score`,
`lines`, `display`, `mutate:`, `eval`, `load`, `shell`, or `http`, probes the
swap, and `heal!`s if the probe does not return a number. See `docs/DESIGN.md`.

## Soft smoke

Image `ghcr.io/cybrid-systems/dev:v1.0.9`, Soft tip binary
`/workspace/aura-grok/build/aura` (host GLIBC is often too old — smoke always
runs Soft inside Docker with `--entrypoint /usr/local/bin/gosu`). Needs
`AURA_SANDBOX=off`.

```bash
bash scripts/smoke_soft.sh    # M0: LINES=4 SCORE=400 TETRIS_M0_OK
bash scripts/smoke_m1.sh      # M0 + strategy gate/swap/heal + SNAP pipe
bash scripts/smoke_m2.sh      # duel + explain + storm → TETRIS_M2_SMOKE_OK
bash scripts/demo_soft.sh     # headless ASCII, ends TETRIS_DEMO_DONE
```

M0 sequence (documented in `docs/m0.md`): four times fill bottom cols `0..5`,
hard-drop horizontal **I** into `6..9` → one line each; level stays 1 so
score is `4 × 100 = 400`.

Manual Soft run:

```bash
sudo docker run --rm --entrypoint /usr/local/bin/gosu \
  -v /workspace/aura-grok:/workspace/aura-grok \
  -v "$PWD":/workspace/aura-tetris \
  -w /workspace/aura-tetris \
  -e AURA_PATH=/workspace/aura-grok/lib \
  -e AURA_PIPELINE_STRICT=0 \
  -e AURA_SANDBOX=off \
  ghcr.io/cybrid-systems/dev:v1.0.9 \
  dev /workspace/aura-grok/build/aura /workspace/aura-tetris/soft/tetris/demo.aura
```

## Engine

| Path | Role |
|------|------|
| `soft/tetris/world.aura` | 10×20 board, IJLOSTZ, move / soft·hard drop / CW+CCW (kicks 0,-1,+1), lock, clear, score |
| `soft/tetris/strategy.aura` | `tetris:place-fn` hot-strategy slot, gate, probe, heal, `choose-move` |
| `soft/tetris/play.aura` | interactive SNAP/INPUT loop, seeded 7-bag |
| `soft/tetris/m0_smoke.aura` | deterministic line-clear tokens |
| `soft/tetris/m1_strategy_smoke.aura` | swap + probe + heal → `TETRIS_M1_STRATEGY_OK` |
| `soft/tetris/duel.aura` | two boards, one bag, aggressive vs defensive worldlines |
| `soft/tetris/m2_duel_smoke.aura` | `TETRIS_M2_DUEL_OK` |
| `soft/tetris/m2_explain_smoke.aura` | `TETRIS_M2_EXPLAIN_OK` |
| `soft/tetris/m2_storm_smoke.aura` | `TETRIS_M2_STORM_OK` |
| `c/play.c` | ANSI viewport (blit + keys only; `--duel` splits the frame) |
| `examples/dogfood/` | GOAL / stub / verify / dogfood.json for `aura-build llm-dogfood` |

Score: `1/2/3/4` lines → `100/300/500/800 × level`; `level = 1 + lines/10`.

## aura-build dogfood

```bash
cd /workspace/aura-build
export AURA_BIN=/workspace/aura-grok/build/aura
# verify.sh wraps Soft in docker when host GLIBC cannot run AURA_BIN
aura-build llm-dogfood --project /workspace/aura-tetris/examples/dogfood \
  --max-rounds 12 --worldlines 3 --prefer-session \
  --out /workspace/aura-tetris/trajectories/tetris_dogfood.jsonl --json || true
```

Hand-written Soft engine + smoke is the primary gate; dogfood is optional
repair-loop exercise (`golden.aura` passes `verify.sh`).

## Soft tip

- Binary: `/workspace/aura-grok/build/aura`
- Image: `ghcr.io/cybrid-systems/dev:v1.0.9`
- Env: `AURA_SANDBOX=off AURA_PIPELINE_STRICT=0 AURA_PATH=/workspace/aura-grok/lib`

License: Apache-2.0

---

# aura-tetris（中文）

活世界在 Soft：棋盘、七种方块、锁定、消行、计分。C 只是 ANSI 视口，把
`SNAP` 画出来，把按键变成 `INPUT`。对局中可以热换落子策略
（`hot-strategy:swap!`，失败 `heal!`）。Soft 不是 Restricted 沙箱模式，
也不是原生插件热更新。详见 `docs/DESIGN.md`。

```bash
bash scripts/play.sh         # 单盘。q/z 逆时针，e/x 顺时针，Esc 或 Q 退出
bash scripts/duel.sh         # 双盘同袋。t 换边，f 两边各走一步
bash scripts/smoke_soft.sh   # LINES=4 SCORE=400 TETRIS_M0_OK
bash scripts/smoke_m1.sh     # M0 + 策略门 + SNAP 管道
bash scripts/smoke_m2.sh     # 对决 + explain + storm
bash scripts/demo_soft.sh    # ASCII 自动演示，结尾 TETRIS_DEMO_DONE
```

镜像 `ghcr.io/cybrid-systems/dev:v1.0.9`，Soft 二进制 `/workspace/aura-grok/build/aura`。
仓库：https://github.com/cybrid-systems/aura-tetris
