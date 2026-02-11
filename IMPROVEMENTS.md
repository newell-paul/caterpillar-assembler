# Caterpillar Improvements

### Done
- [x] Cycle-based seasons (6 map cycles per season, fully deterministic)
- [x] Acorn scoring: incrementing 10, 20, 30, ... per collection
- [x] Acorn bonus: 2000 points for collecting 16+ acorns across all seasons
- [x] ACORN letter collection during season transitions (1000 bonus for all 5)
- [x] Pre-clear screen memory to eliminate MODE 7→2 transition garbage
- [x] Map compression: single base map with per-season col_offset and item_skip

### Improvements
- [ ] Speed up after each season/stage
- [ ] Pixel-perfect collision detection

## Known Issues

## Notes
- Performance is currently acceptable (~16Hz gameplay)
- Only optimize if new features demand it
