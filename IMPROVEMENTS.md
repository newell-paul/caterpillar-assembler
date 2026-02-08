# Code Improvements & Optimizations

## High Priority

### **MAJOR REFACTOR: Replace Static Maps with Seeded Procedural Generation**
- [ ] **Current approach is bloated: 273+ lines of static map data (10.8% of codebase)**
  - Problem: Static maps = massive data tables, hard to edit, not space-efficient
  - Better approach: **Deterministic procedural generation** (like Flappy Bird, Geometry Wars)
  - Solution options:
    1. **Seeded LFSR** (Recommended): Use fixed seed per season, generate same pattern every time
       - Data: 4 seeds (8 bytes) instead of 273+ lines
       - Code: ~50 lines of generation logic
       - Result: Learnable patterns, minimal storage
    2. **Algorithmic patterns**: Mathematical curves (sine waves, spirals)
       - Very small code + data
       - Predictable but interesting
    3. **Compressed templates**: Store pattern chunks + sequencing rules
       - ~40 bytes vs 273 lines
  - **Impact: Reduce codebase from 2520 lines to ~500-800 lines**
  - Players can still learn patterns (deterministic from seed)
  - Easy to tweak difficulty (just change seed)

### Map Data Optimization (If Keeping Static Maps)
- [ ] **Empty map rows for season transitions are sub-optimal and full of &FF**
  - Current: Each empty row = `EQUB &FF` (1 byte per row)
  - Problem: Wastes bytes, harder to edit
  - Solution: Consider run-length encoding or packed format (e.g., `rows 0-2: empty, row 3: mushroom col 5`)
  - Impact: ~50-100 bytes saved across all season maps

### Performance
- [ ] Reduce POINT calls in collision detection (very expensive MOS call)
  - Current: Multiple OSWORD calls per frame
  - Solution: Track item positions in memory, check bounds first
- [ ] Cache screen address calculations
  - Reuse results when drawing at same Y coordinate
- [ ] Optimize sprite drawing loop
  - Unroll inner loops where practical
  - Use self-modifying code for critical paths

## Code Quality

### Magic Numbers
- [ ] Extract hardcoded item encoding values to named constants
  - `&00-&13` = mushroom range
  - `&20-&33` = fruit range
  - `&40-&53` = acorn range
  - `&FF` = end-of-row marker
- [ ] Define column count constant (currently hardcoded as 20)
- [ ] Define map row count constant (currently 64)

### Code Duplication
- [ ] Consolidate VDU sequence sending (many repeated patterns)
- [ ] Extract common OSWORD parameter setup into helper
- [ ] Merge similar sprite drawing routines (head/body share logic)

### Label Naming
- [ ] Improve consistency between zero-page variable names
- [ ] Add `_` prefix for internal subroutine labels
- [ ] Use verb-noun pattern for action routines (e.g., `draw_sprite` not `sprite_draw`)

## Memory Optimization
- [ ] Look at optimisations everywhere this is 

### Data Packing
- [ ] Pack character bitmaps more efficiently
  - Some sprite data could share common rows
- [ ] Consider using lookup tables for repeated calculations
  - Screen address offset tables
  - Multiplication by 20 (columns) for map indexing
- [ ] Evaluate zero-page usage
  - Are all variables frequently accessed?
  - Could some be moved to regular RAM?

### Buffer Management
- [ ] Review body segment ring buffer size (BODY_MAX=5)
  - Is this optimal for gameplay?
  - Could it be smaller to save RAM?
- [ ] Consolidate save buffers if possible
  - Do head/body save buffers need separate storage?

## Technical Debt

### Documentation
- [ ] Add inline comments for branch-out-of-range workarounds
  - Document why inverted condition + JMP is used
- [ ] Document LFSR algorithm more clearly
  - Explain the Galois LFSR implementation
  - Note the requirement to store shifted low byte first
- [ ] Add header comments to each major section
  - What each subroutine does
  - Input/output registers
  - Clobbers

### Map Design
- [ ] Create map editor/generator tool
  - Current: Hand-editing hex values is error-prone
  - Solution: Simple tool to visualize and edit maps
  - Could validate no-overlap rules automatically
- [ ] Add map validation at build time
  - Check for column reuse on consecutive rows
  - Verify item encoding is valid
  - Ensure &FF termination

## Future Enhancements

### Gameplay
- [ ] Variable body segment growth (eat items → grow longer)
- [ ] Multiple caterpillars (2-player mode?)
- [ ] Power-ups (speed boost, invincibility)
- [ ] Persistent high score (save to disc or CMOS RAM)

### Portability
- [ ] Abstract MOS-specific calls for easier porting
  - Create abstraction layer for video/sound/input
- [ ] Document BBC Micro-specific assumptions
  - MODE 2 screen layout
  - 6845 CRTC hardware scrolling
  - OSWORD parameter formats

### Build System
- [ ] Add version auto-increment hook
  - Bump version on every successful build
- [ ] Generate build timestamp in binary
- [ ] Create debug vs release builds (different optimizations)

## Low Priority

### Polish
- [ ] Add more varied sound effects
  - Different tones for different items
  - Musical cues for season transitions
- [ ] Smooth difficulty curve between seasons
  - Currently: scroll_div changes abruptly
  - Consider gradual acceleration
- [ ] Better title screen layout
  - More attractive MODE 7 graphics
  - Instructions screen

### Code Style
- [ ] Consistent indentation for nested blocks
- [ ] Align comments at column 40
- [ ] Use consistent capitalization for labels
  - Currently mixed: `game_init` vs `OSWRCH`

---

## Notes
- Improvements marked with [] are tracked but not started
- Mark [x] when complete
- Add priority labels (HIGH/MED/LOW) as needed
- Link to specific line numbers when filing improvements
