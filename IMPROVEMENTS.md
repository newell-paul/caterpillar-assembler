# Caterpillar Improvements

### Improvements
- [ ] Revisit sounds
- [ ] Bonus Round seasons surrounded by acorns

### Code Quality (v0.9.6 - size optimizations, 3032 → 2644 bytes)
- [x] **Remove dead code** (-95 bytes)
  - `random`/`random_n`, `play_sound`, `do_gcol`, `colour_right`, `sound_buzz`, `sound_fruit`
- [x] **Tail-call optimizations** (-6 bytes)
  - 6x `JSR+RTS` → `JMP` in helpers and draw_map_row
- [x] **Zero-page memset loop** (-20 bytes)
  - Replace 13 individual STA with two tight loops (&66-&75, &95-&9E)
- [x] **Table-driven VDU sequences** (-43 bytes)
  - `send_vdu_seq` subroutine + data tables for init and row clear
- [x] **Extract scanline advance subroutine** (-112 bytes)
  - 4 duplicated 39-byte copies → shared `advance_scanline`
- [x] **Pair-format map compression** (-112 bytes)
  - Changed from row-terminated streams to (row, type_col) pairs
  - Empty rows cost 0 bytes (was 1 each, 165 eliminated)
  - Bonus cool-down: 80 → 33 bytes

### Map System
- [ ] **Seeded procedural generation** (Optional Major Refactor)
  - Replace static map data with seeded LFSR
  - Deterministic patterns (learnable like Flappy Bird)
  - Only consider if static maps become unmaintainable

## Known Issues

### Body Trail Flicker
- Last segment flickers while others are solid
- Try and move caterpillar up one

---

## Notes
- Performance is currently acceptable ~16Hz gameplay)
- Only optimize if new features demand it
