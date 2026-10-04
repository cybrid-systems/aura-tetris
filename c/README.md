Thin ANSI viewport (`play.c`). Soft owns the matrix, the active piece,
next, hold, score, lines, and level. This binary only:

- spawns the Soft child (`scripts/soft_play.sh` by default)
- reads `SNAP v1` … `END` on the child's stdout
- sends `INPUT <verb>` lines
- draws the board (10 columns, or 12 after a Soft `rule_width` swap)

It does not clear lines or compute score. Build via `scripts/play.sh`
(CMake, C11). `scripts/duel.sh` passes `--duel` and draws `BOARD` next
to `BOARD2` when Soft sends both. `t` is `INPUT toggle`.
`v` is `INPUT race`, `m` is `INPUT mutate`, `u` is `INPUT propose`.
Ghost landings and `WORLD line=` come from Soft; C only blits them.
