# aura-tetris

Soft FlatAST Tetris — the live world is an Aura Soft program (board, pieces, lock,
line clear, score). M0 is Soft-only ASCII / scripted smoke; optional thin C input
can come later. Also an [aura-build](https://github.com/cybrid-systems/aura-build)
dogfood project under `examples/dogfood/`.

Repo: https://github.com/cybrid-systems/aura-tetris

## Soft smoke (CI)

Image `ghcr.io/cybrid-systems/dev:v1.0.9`, Soft tip binary
`/workspace/aura-grok/build/aura` (host GLIBC is often too old — smoke always
runs Soft inside Docker with `--entrypoint /usr/local/bin/gosu`). Needs
`AURA_SANDBOX=off`.

```bash
bash scripts/smoke_soft.sh
```

Exit 0. Stdout includes:

```
LINES=4
SCORE=400
TETRIS_M0_OK
```

Sequence (documented in `docs/m0.md`): four times fill bottom cols `0..5`,
hard-drop horizontal **I** into `6..9` → one line each; level stays 1 so
score is `4 × 100 = 400`.

## Soft demo (ASCII auto-play)

```bash
bash scripts/demo_soft.sh
```

Or manually:

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

Ends with `TETRIS_DEMO_DONE`. Prints ~20 gravity ticks of a 10×20 board.

## Engine

| Path | Role |
|------|------|
| `soft/tetris/world.aura` | 10×20 board, IJLOSTZ, move / soft·hard drop / CW rotate (kicks 0,-1,+1), lock, clear, score |
| `soft/tetris/m0_smoke.aura` | Deterministic smoke tokens |
| `soft/tetris/demo.aura` | Headless auto-play ASCII demo |
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

Hand-written Soft engine + smoke is the primary M0 gate; dogfood is optional
repair-loop exercise (`golden.aura` passes `verify.sh`).

## Soft tip

- Binary: `/workspace/aura-grok/build/aura`
- Image: `ghcr.io/cybrid-systems/dev:v1.0.9`
- Env: `AURA_SANDBOX=off AURA_PIPELINE_STRICT=0 AURA_PATH=/workspace/aura-grok/lib`

License: Apache-2.0

---

# aura-tetris（中文）

Soft FlatAST 俄罗斯方块：活世界在 Soft（棋盘 / 七种方块 / 消行 / 计分）。M0
只需 Soft ASCII 冒烟与演示，不必上 C。

```bash
bash scripts/smoke_soft.sh   # 期望 LINES=4 SCORE=400 TETRIS_M0_OK
bash scripts/demo_soft.sh    # ASCII 自动玩，结尾 TETRIS_DEMO_DONE
```

镜像 `ghcr.io/cybrid-systems/dev:v1.0.9`，Soft 二进制 `/workspace/aura-grok/build/aura`。
仓库：https://github.com/cybrid-systems/aura-tetris
