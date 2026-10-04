# aura-tetris — design (Aura-native)

The product is a live Soft FlatAST world: the board, the active piece, the
bag, lock, line clear, and score are Soft definitions in one Aura process.
A thin C program is a viewport. It is not the game.

This is the same loop aura-parkour already plays: Soft emits a snapshot,
the viewport blits it, keys come back as `INPUT` lines, and strategy bodies
are swapped with `hot-strategy:swap!` / `hot-strategy:heal!`.

## One sentence

Classic piece control is hygiene. The game is: Soft owns the matrix, a
placement strategy can be hot-swapped mid-game, a proposal is gated and
probed before it sticks, and (next) worldlines pick the best body without
restarting the process or teaching C the rules.

## Aura loop

```
keys → C (blit + INPUT only)
         │  INPUT left|right|soft|hard|cw|ccw|hold|tick|auto|restart|quit
         ▼
      soft/tetris/play.aura
         │  applies the verb with the Soft rules in world.aura
         │  may hot-swap tetris:place-fn (strategy.aura)
         ▼
      stdout: SNAP v1 … END
         │  board cells, active piece, next, hold,
         │  score, lines, level, mid/reason
         ▼
      C draws. It does not clear lines or add points.
```

One `INPUT` line, one `SNAP`. Logs (`TETRIS_PLAY_READY` and friends) go to
stderr. The pipe stays parseable.

`tick` is gravity. Soft, not C, decides how many ticks equal one row from
the current level (`16 - level`, minimum 2). Level itself is
`1 + lines/10`, updated only inside `tetris:clear-lines!`.

## Soft vs C

| Soft owns | C may do |
|-----------|----------|
| 10×20 matrix, shapes, kicks, lock, clear | ANSI blit of the SNAP |
| bag, next, hold | raw keys → `INPUT` verbs |
| score, lines, level, alive, tick | pause locally (stop sending `tick`) |
| `tetris:place-fn` heuristic | nothing about candidate geometry |

Score table (unchanged from M0): 1/2/3/4 lines → `100/300/500/800 × level`.
Soft-drop and hard-drop do not add points. C must not invent a second table.

The SNAP board is locked cells only (`.` or type digit `1`–`7`, which is
`ptype+1`). The active piece is a separate `PIECE` record with cell list.
Overlaying those cells is drawing, not physics.

## Soft ≠ Restricted

Two Aura surfaces are easy to mix up. This game uses one of them.

| | This product | Not this product |
|--|----------------|------------------|
| World | FlatAST workspace defines | A native plugin / `.so` region |
| Swap | `std/hot-strategy` (`mutate:rebind` + `ast:snapshot`) | `std/hot-update` (`aot:reload`, region masks) |
| Heal | `hot-strategy:heal!` (restore last-good snap, else rebind) | `std/heal` (`set-code` surgery mid-match) |
| Sandbox | **off** for the one-time `set-code` seed of `tetris:place-fn` | Restricted mode as the play loop |

`hot-strategy:aot?` is `#f`. Shipping a C++ or Rust "strategy plugin" would
be a different product: a moat made of a loader, not a world you can probe.

Honesty about the seed: the Soft tip still plants the first named define
with `set-code` + `eval-current`, and that call is the sandbox-off path
(`AURA_SANDBOX=off`, same as aura-parkour). After `hot-strategy:register!`,
the match only `swap!` / `heal!`. M1 does not pretend Restricted-mode play
already works. If a future tip rejects `set-code` under the sandbox, the
seed has to move; the in-match gate does not.

## Pilot, steer, propose

1. **Pilot.** Keys become `INPUT` verbs. Soft moves, rotates (kicks `0,-1,+1`),
   soft-drops, hard-drops, holds, or applies gravity. The viewport never
   writes `*score*` or `*lines*`.
2. **Steer.** `tetris:place-fn` is a workspace strategy.
   `(tetris:place-fn board piece)` returns a number; higher is a better
   candidate. M1 passes the landing row (larger means deeper) and the piece
   type, not a full grid — enough to swap the heuristic without handing it
   the score variables. `tetris:choose-move` turns that number into one of
   `left` / `right` / `cw` / `hard`. The `f` key (verb `auto`) takes one
   such step. Swapping the body mid-game changes later steps; it does not
   retcon the matrix.
3. **Propose.** A strategy arrives as a string (M1 hook:
   `TETRIS_STRATEGY_FILE`, read once on the first `INPUT`). Soft gates it
   before `swap!`:
   - must look like `(lambda …)` mentioning `board` and `piece`
   - rejected if the text mentions `set!`, `score`, `lines`, `display`,
     `mutate:`, `eval`, `load`, `shell`, or `http`
   - `mutate:boundary-safe?` and `mutate:quota-ok?` must hold
     (MutationBoundary-shaped check; this is `std/mutate`, not a renamed
     `set!`)
   - after a swap that passes the gate, probe `(tetris:place-fn 4 0)` and
     require a number; otherwise `hot-strategy:heal!` back to the previous
     good body

   The model is not asked for a score. A body that mentions score is
   dropped on the floor. Worldline select-best (several candidate bodies,
   probe each, keep the winner) is the next layer on this same gate. M1
   is one live slot plus heal, not a swarm.

`MID` in the SNAP is `mid` (0 seed, 1 once a proposal was judged) and
`reason` (`seed`, `gate`, `boundary`, `swap`, `heal`, `probe`, …). That is
how the viewport shows a swap without computing it.

## Non-goals

- **Not another Tetris clone.** Guideline finesse, t-spins, DAS tuning, and
  a polished skin are not the milestone. Seven pieces and a 10×20 matrix
  exist so the Aura loop has something real to own.
- **Not a plugin moat.** No AOT hot-update region, no C strategy table, no
  "load a .so to change the heuristic." If the interesting part can be
  copied by swapping a function pointer in C, it is the wrong product.
- **Not C-authoritative physics.** A viewport that clears lines "for
  latency" and later reconciles with Soft is a second game. Soft is the
  only writer of score.

## Files

| Path | Role |
|------|------|
| `soft/tetris/world.aura` | matrix, pieces, lock, clear, score (M0 + CCW) |
| `soft/tetris/strategy.aura` | `tetris:place-fn` seed, gate, swap, probe, heal, `choose-move` |
| `soft/tetris/play.aura` | bag, hold, `INPUT` loop, `SNAP v1` |
| `soft/tetris/m0_smoke.aura` | `LINES=4 SCORE=400 TETRIS_M0_OK` |
| `soft/tetris/m1_strategy_smoke.aura` | gate + swap + probe + heal → `TETRIS_M1_STRATEGY_OK` |
| `c/play.c` | ANSI 10×20 viewport |
| `scripts/play.sh` | build viewport, spawn Soft |
| `scripts/smoke_m1.sh` | M0 + M1 + SNAP pipe + viewport build |

## 短中文

产品是活的 Soft 世界，不是又一个 C 俄罗斯方块。C 只把 `SNAP v1 … END`
画出来，并把按键收成 `INPUT`。消行和分数只在 Soft 里改。

三层：Pilot（按键驱动 Soft）、Steer（对局中 `hot-strategy:swap!` 换
`tetris:place-fn`）、Propose（字符串策略先过门：禁止 `set!` / `score` /
`lines` / `display` / `mutate:` / `eval` / `load` / `shell` / `http`，再
probe，失败则 `heal!`）。这不是 Restricted 沙箱对局，也不是 AOT 插件热更新；
种子仍是沙箱外的一次 `set-code`，之后只 swap / heal。

非目标：不做另一个方块克隆，也不做「换策略必须上原生插件」的护城河。
多条世界线择优是下一层，M1 先把可替换、可探测、可回滚的策略槽落地。
