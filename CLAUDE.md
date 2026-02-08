# Caterpillar - 6502 Assembly

Converting a 1983 BBC BASIC game to native 6502 assembly for BBC Micro Model B.

## Quick Start
```bash
make              # Build caterpillar.ssd disc image
make clean        # Remove build artifacts
```

Load `caterpillar.ssd` in BeebEm-mac or jsbeeb (bbc.godbolt.org), then Shift+Break to boot.

## Files
- `caterpillar.asc` - Original BASIC (reference only, **do not modify**)
- `caterpillar.asm` - 6502 assembly source
- `caterpillar.ssd` - BBC Micro disc image (auto-generated)
- `beebasm` - Assembler binary (macOS)

## Roadmap
- [ ] Move Caterpillar head up one char
- [ ] Define challenging repeating mapped scrolling field of mushrooms and items. Ensure items do not overlap
- [ ] Speed up after each season/stage
- [ ] Pixel-perfect collision detection

## Memory Layout
- `&0070-&007F` - Zero page variables (position, score, PRNG)
- `&0080-&008F` - OSWORD parameter block (timer/sound/pixel)
- `&1900-&2183` - Program code + data
- `&3000-&7FFF` - MODE 2 screen memory

## Version Bumping
- **Always bump the version** in `str_version` (near end of `caterpillar.asm`) after every change, incrementing the patch number by .1 (e.g. v0.8.4 → v0.8.5)

## Key Conventions
- MOS calls: OSWRCH (&FFEE), OSBYTE (&FFF4), OSWORD (&FFF1), OSRDCH (&FFE0)
- 16-bit values: little-endian (lo byte first)
- Branch-out-of-range: invert condition + JMP
- PRNG: 16-bit Galois LFSR seeded from system timer
- Game speed: 3x OSBYTE 19 (vsync) per frame (~16Hz)

## Common Pitfalls
- 6502 branches limited to ±127 bytes (use inverted condition + JMP for long jumps)
- LFSR: store shifted low byte BEFORE `ROL rng_hi`
- 16-bit "greater than": compare against N+1 with SEC/SBC
