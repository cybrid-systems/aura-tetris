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
   dropped on the floor. A live LLM call is optional; the file hook is the
   propose path. M2 does not add a network call.

`MID` in the SNAP is the strategy id and a short reason tag
(`seed`, `gate`, `swap`, `heal`, …). `EXPLAIN` is the human line:
`mid=` and `reason=` (`gate_reject`, `heal`, `lines_lead`, `survive`,
`storm_sz`, `lock`). stderr mirrors `EXPLAIN mid=… reason=…`. C does not
invent either field.

## M2 — duel, explain, storm

Two boards, one bag. `soft/tetris/duel.aura` deals the same 7-bag sequence
to both matrices. The left worldline calls `tetris:place-agg` (deeper row,
then a righter column). The right worldline calls `tetris:place-def`
(shallower row, then a lefter column). Both functions are seeded with the
same sandbox-off `set-code` as `tetris:place-fn`. Search still goes through
Soft. C never scores a candidate.

Each scripted tick gravity-steps and auto-steps that worldline on the live
matrix. The smoke plays the aggressive game, then the defensive game, on
the shared sequence (the heuristics do not read each other's cells, so the
lockstep copy is not required for the token). It prints `WINNER mid=`
`side=` `reason=` and `TETRIS_M2_DUEL_OK` only when the fingerprints differ.
Reasons: `lines_lead` (more lines, else more score) or `survive` (the other
board topped out).

The live slot is still one `hot-strategy:swap!` / `heal!` name. After both
worldlines finish, Soft sets `*commit-live*` and swaps `tetris:place-fn`
onto the winner body. Doing that swap earlier snapshots the filled matrix
and makes later cell writes very slow, so the interactive loop stamps the
winner every step and commits the swap on `quit` (and immediately when a
storm fires). That is the real mutate path, not a `set!` of the function
and not `std/hot-update`.

`scripts/duel.sh` is `tetris_play --duel`. Keys pilot the side in
`PILOT side=L|R` (default left). `t` sends `toggle`. `f` sends `auto` and
Soft steps both boards. Gravity (`tick`) steps both and auto-plays the
side you are not piloting. The frame is `BOARD` beside `BOARD2`.

Explain stamps on gate rejection (`gate_reject`), a probed swap (`swap`),
a failed probe (`heal`), a lock (`lock` or `lines_lead` when the lock
cleared lines), and a duel select (`lines_lead` / `survive`). The M1 return
tags stay `gate` / `swap` / `probe` so `m1_strategy_smoke.aura` does not
change meaning. `*strat-reason*` after a heal is still `heal`.

Storm: if the next 6 pieces contain at least four S/Z or a run of three,
Soft `hot-strategy:swap!`s the defensive body and stamps `storm_sz`. When
the next 6 fall to one or zero S/Z, `hot-strategy:heal!` restores the
previous body. A calm bag does not swap.

Play:

```bash
bash scripts/duel.sh
bash scripts/smoke_m2.sh
```

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
| `soft/tetris/duel.aura` | shared bag, two place-fn worldlines, SNAP `BOARD2` |
| `soft/tetris/m2_duel_smoke.aura` | `TETRIS_M2_DUEL_OK` |
| `soft/tetris/m2_explain_smoke.aura` | `TETRIS_M2_EXPLAIN_OK` |
| `soft/tetris/m2_storm_smoke.aura` | `TETRIS_M2_STORM_OK` |
| `c/play.c` | ANSI viewport; `--duel` draws both boards |
| `scripts/play.sh` | build viewport, spawn Soft |
| `scripts/duel.sh` | split-screen duel |
| `scripts/smoke_m1.sh` | M0 + M1 + SNAP pipe + viewport build |
| `scripts/smoke_m2.sh` | duel + explain + storm tokens |

## 短中文

产品是活的 Soft 世界，不是又一个 C 俄罗斯方块。C 只把 `SNAP v1 … END`
画出来，并把按键收成 `INPUT`。消行和分数只在 Soft 里改。

三层：Pilot（按键驱动 Soft）、Steer（对局中 `hot-strategy:swap!` 换
`tetris:place-fn`）、Propose（字符串策略先过门：禁止 `set!` / `score` /
`lines` / `display` / `mutate:` / `eval` / `load` / `shell` / `http`，再
probe，失败则 `heal!`）。这不是 Restricted 沙箱对局，也不是 AOT 插件热更新；
种子仍是沙箱外的一次 `set-code`，之后只 swap / heal。

非目标：不做另一个方块克隆，也不做「换策略必须上原生插件」的护城河。

M2：同一 7-bag 上两盘。左 `place-agg`（更深、更靠右），右 `place-def`
（更浅、更靠左）。`scripts/duel.sh` 左右分屏，按键操纵当前边（`t` 切换），
`f` 两边各自动一步。择优写 `WINNER mid=` `reason=lines_lead|survive`。
解释行是 `EXPLAIN mid=` `reason=`（`gate_reject`、`heal`、`storm_sz`）。
S/Z 扎堆时 `hot-strategy:swap!` 到防守，袋子平静后 `heal!`。
对局里的换策仍是 swap / heal，不是 Restricted，也不是 AOT。
