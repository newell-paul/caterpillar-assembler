# Caterpillar Improvements

## Completed

### v0.9.0 - MODE 7 BASIC Wrapper
- [x] **BASIC/Assembly split** - BASIC handles MODE 7 title/menu/scores, assembly handles MODE 2 game engine
- [x] Title screen, game over, game completed screens in BASIC
- [x] Clean return-to-BASIC via saved stack pointer (TSX/TXS)
- [x] Game result code at &9F (0=crash, 1=completed)
- [x] Removed title_screen, print_decimal, and title strings from assembly
- [x] ~300 fewer assembly lines, menus easy to edit in BASIC

## High Priority Improvements

### Performance (If Needed)
- [ ] **Direct screen collision detection** (Tier 2.1)
  - Replace OSWORD 9 with direct screen memory read
  - ~500-900 cycles saved per check
  - Medium effort, medium risk

### Code Quality
- [ ] **Remove dead code** (Tier 1.1)
  - `colour_left`/`colour_right` tables (32 bytes)
  - `random`/`random_n` routines (30 bytes)
  - `play_sound`/`do_gcol` (14 bytes)
  - Total: ~76 bytes saved

### Map System
- [ ] **Seeded procedural generation** (Optional Major Refactor)
  - Replace 273+ lines of static map data with seeded LFSR
  - Deterministic patterns (learnable like Flappy Bird)
  - Data: 4 seeds (8 bytes) vs 273 lines
  - Only consider if static maps become unmaintainable

## Known Issues

### Body Trail Flicker
- Last segment flickers while others are solid
- Attempted fixes: overlap detection (failed), BODY_MAX=6 (broke game)
- Likely needs delayed-erase with pending flag (complex)
- **Decision: Accept for now, low priority**

## Deferred / Low Priority

- Empty map row optimization (&FF compression)
- Factoring VDU sequences into subroutines
- All Tier 3 refactors (only if performance becomes critical)

---

## Notes
- Performance is currently acceptable (50Hz capable, ~16Hz gameplay)
- Only optimize if new features demand it
