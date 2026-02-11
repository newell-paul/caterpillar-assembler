# Caterpillar - 6502 Assembly

Convert a 1983 BBC BASIC game to native 6502 assembly for BBC Micro Model B.
Relearn some forgotten architecture

## Quick Start
```bash
make              # Build caterpillar.ssd disc image
make clean        # Remove build artifacts
```

Load `caterpillar.ssd` in BeebEm-mac or jsbeeb (bbc.godbolt.org), then Shift+Break to boot.

## Architecture
BASIC (MODE 7) handles title screen, menus, game over/completed screens.
Assembly (MODE 2) handles the game engine: sprites, scrolling, collision, seasons.

```
BASIC (MODE 7)              Assembly (MODE 2)
─────────────              ─────────────────
Title screen     ─CALL→    game_init
Instructions                game_loop (50Hz)
Score display               sprite/scroll/collision
Press any key               seasons/maps
                 ←RTS──    return_to_basic (game_result: 0=crash, 1=completed)
Game over screen
Completed screen
Loop back to title
```

## Files
- `caterpillar.asc` - Original BASIC (reference only, **do not modify**)
- `caterpillar.asm` - 6502 assembly game engine
- `caterpillar.bas` - BASIC MODE 7 wrapper (title/menu/scores)
- `!BOOT` - Disc boot file (*LOAD GAME, PAGE=&2800, CHAIN "CATER")
- `caterpillar.ssd` - BBC Micro disc image (auto-generated)
- `beebasm` - Assembler binary (macOS)

## Roadmap
[ ] Document
[ ] README.md
[ ] Deploy (frictionless)
[ ] Play testers (Will, Billy)
[ ] Stardot forums

## Seasons
Cycle-based: each season = exactly 6 map cycles (384 rows). After the 6th cycle wraps,
`season` increments and `enter_transition` shows the next season name (76 empty scroll rows).
After season 3 (Summer) completes → `round_over` → bonus phase.
No system timer — fully deterministic, same gameplay every run.

`map_cycle` (ZP &79) counts 0–5, reset to 0 by `load_season`.

## Map System
All 4 seasons share a single base map (`map_base`: 33 mushrooms, 14 fruits, 1 acorn).
Per-season variation via two config values in `season_config` (bytes 6-7):

- **col_offset** (0-19) — shifts mushroom/fruit columns right, wrapping at 20
- **item_skip** (0-N) — skip every Nth mushroom (0=none). Fruits always drawn.

| Season | col_offset | item_skip | Mushrooms | Fruits | Difficulty  |
|--------|------------|-----------|-----------|--------|-------------|
| Autumn | 5          | 2         | ~17 (50%) | 14     | Easy        |
| Winter | 10         | 3         | ~22 (67%) | 14     | Medium      |
| Spring | 15         | 4         | ~25 (75%) | 14     | Medium-hard |
| Summer | 0          | 0         | 33 (100%) | 14     | Hard        |

Mushroom columns in base map avoid {4,9,14,19} so no cap overflows column 19 after offset.

## Acorn System
One acorn per map cycle at row 59, drawn unconditionally from map data (no timer gating).
Column rotates via `acorn_col_table` (10, 3, 16, 7) indexed by `acorn_col_idx` (ZP &9B).
Sequence is fully deterministic — same positions every playthrough.

- **Scoring**: incrementing 10, 20, 30, ... per collection (`acorn_score` at ZP &78)
- **All-acorn bonus**: collecting 16 acorns (acorn_score=160) awards 2000 points + celebration sound at round_over. 24 acorns available (6 cycles x 4 seasons), so 16 is the threshold.
- **ACORN letters**: during season transitions, passing over the correct column collects a letter (A/C/O/R/N per season). All 5 letters → 1000 bonus at show_completed.
- **BASIC display**: `saved_acorn_word` at fixed address &1908 (non-ZP, survives MODE switch). BASIC reads `?&1908` for title screen letter colouring.

## Memory Layout
- `&0060-&009F` - Zero page variables (position, score, game_result)
- `&1900-&22D9` - Assembly game engine code + data
- `&2800-&2FFF` - BASIC program (PAGE=&2800, HIMEM=&3000)
- `&3000-&7FFF` - MODE 2 screen memory

## Version Bumping
- **Auto-bumped by git pre-commit hook** (`.git/hooks/pre-commit`)
- Patch version increments automatically on every commit that includes `caterpillar.asm` or `caterpillar.bas`
- Updates all 3 locations: `.asm` header, `.bas` REM line, `.bas` title screen
- **Do NOT manually bump** — the hook handles it

## Key Conventions
- MOS calls: OSWRCH (&FFEE), OSBYTE (&FFF4), OSWORD (&FFF1), OSRDCH (&FFE0)
- 16-bit values: little-endian (lo byte first)
- Branch-out-of-range: invert condition + JMP
- Game speed: 1x OSBYTE 19 (vsync) per frame (50Hz capable, scroll rate controlled by scroll_div)
- Score at &74/&75, hiscore at &76/&77 (read by BASIC after CALL returns)
- Game result at &9F (0=crash, 1=completed)

## Common Pitfalls
- 6502 branches limited to ±127 bytes (use inverted condition + JMP for long jumps)
- 16-bit "greater than": compare against N+1 with SEC/SBC
- BASIC program + variables must fit below &3000 (MODE 2 screen memory)
- Assembly returns to BASIC via saved stack pointer (TSX/TXS pattern)

## Code Quality
[ ] Every byte counts. I do not want to lose current functionality but want this expertly coded with accurate and expansive commments for every section so I can learn how this works. Accurately describe each section of the code so reviewers have context.
[ ] Ideally I want the code excluding comments to be less than 1200 lines
[ ] Make use of BBC hardware when possible to trim down code but not if there is a large performance hit
