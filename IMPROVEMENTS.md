# Caterpillar Improvements

### Improvements
- [ ] multiplier for getting mushrooms. For every acorn the value for the next one goes up by another 50
  - 50 acorns 

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
