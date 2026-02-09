# Caterpillar - 6502 Assembly

Converting a 1983 BBC BASIC game to native 6502 assembly for BBC Micro Model B.

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
- [ ] Move Caterpillar head up one char
- [ ] Define challenging repeating mapped scrolling field of mushrooms and items. Ensure items do not overlap
- [ ] Speed up after each season/stage
- [ ] Pixel-perfect collision detection

## Memory Layout
- `&0060-&009F` - Zero page variables (position, score, PRNG, game_result)
- `&1900-&251C` - Assembly game engine code + data
- `&2800-&2FFF` - BASIC program (PAGE=&2800, HIMEM=&3000)
- `&3000-&7FFF` - MODE 2 screen memory

## Version Bumping
- **Always bump the version** in `caterpillar.bas` (line 260) after every change, incrementing the patch number by .1 (e.g. v0.9.0 → v0.9.1)

## Key Conventions
- MOS calls: OSWRCH (&FFEE), OSBYTE (&FFF4), OSWORD (&FFF1), OSRDCH (&FFE0)
- 16-bit values: little-endian (lo byte first)
- Branch-out-of-range: invert condition + JMP
- PRNG: 16-bit Galois LFSR seeded from system timer (BASIC pokes &78/&79 before CALL)
- Game speed: 1x OSBYTE 19 (vsync) per frame (50Hz capable, scroll rate controlled by scroll_div)
- Score at &74/&75, hiscore at &76/&77 (read by BASIC after CALL returns)
- Game result at &9F (0=crash, 1=completed)

## Common Pitfalls
- 6502 branches limited to ±127 bytes (use inverted condition + JMP for long jumps)
- LFSR: store shifted low byte BEFORE `ROL rng_hi`
- 16-bit "greater than": compare against N+1 with SEC/SBC
- BASIC program + variables must fit below &3000 (MODE 2 screen memory)
- Assembly returns to BASIC via saved stack pointer (TSX/TXS pattern)
