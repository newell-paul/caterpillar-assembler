# 43 Years Later: Finishing My BBC Micro Game in Assembly

In 1983, the first program I ever wrote appeared in the September issue of *Computer & Video Games* which was the pre-eminent UK games magazine of the day.

<p align="center">
  <img src="assets/CVG-cover.jpg" alt="Computer & Video Games issue 23, September 1983" width="500"><br>
  <em>Computer & Video Games issue 23, September 1983</em>
</p>

Inside that issue, in the type-in listings section, was my game:

**Caterpillar**

Like most type-in games of the era, it was pretty awful. Mine was doubly so as it was my first fumbling attempt at programming, written in BBC BASIC.

And like a lot of coders back then, I told myself I'd rewrite it properly in assembly one day.

This is that rewrite.

It's only 43 years late.

---

## 📖 The original

Back in the early 80s, publishing a game didn't mean uploading to GitHub or pushing to Steam.

It meant seeing your code printed across pages of a magazine and hoping someone, somewhere, would type it in correctly. And that was no easy feat, as anyone who ever tackled a multi-page listing will remember. One mistyped `DATA` statement and the whole thing fell over.

<p align="center">
  <img src="assets/CVG-program.png" alt="The Caterpillar type-in listing as printed in C&VG" width="500"><br>
  <em>The Caterpillar type-in listing as printed in C&VG</em>
</p>

The premise was simple: guide a caterpillar through a maze, collecting food and avoiding the poisonous mushrooms. About 110 lines of BASIC. It ran, it was playable-ish, and it was slow and I mean SLOW ...

<p align="center">
  <img src="assets/caterpillar-1983.gif" alt="The 1983 original in play — flat green mushrooms, all in BBC BASIC" width="500"><br>
  <em>The 1983 original in play. Painfully slow in BBC BASIC</em>
</p>

---

## 💾 The constraints

The BBC Micro Model B gave you 32K of RAM, a 2 MHz 6502, and not much else. The original Caterpillar lived inside that, and the limits showed:

- **BASIC was the bottleneck.** BBC BASIC was truly one of the best versions of the language but still pretty hopeless for action games.
- **Performance.** Scrolling was very slow even using hardware calls. 
- **Collision detection.** I remember struggling to get this right 

---

## ⚙️ The promise

Even as a kid, I knew what the "proper" version would need to be coded in:

6502 Assembly.

I just could not get to grips with it in those early days. 

I did eventually become competent in 6502 a couple of years later but that was with the Commodore 64 (C64) and its hardware sprites which were way easier to get moving.

I never did get back to the BBC game.

---

## 🧠 43 years later

I knew my original game was hosted in the [BBC Micro Archive](https://www.bbcmicro.co.uk/game.php?id=1066) and it always nagged me that I was never able to make the game I wanted back in the day.

So this wasn't just a translation. It was adding all the things I wanted to do on the first version but could not fit in.

- **6502 assembly handles the game.** Sprites, scrolling, collision and the season cycle, in MODE 2 (16 colours), running on a vsync-locked 50Hz loop.

BASIC runs `CALL &1900` to hand control to the engine; the engine plays the game, then returns a result code and the score in zero page for BASIC to display.

---

## 🔍 1983 vs 2026

Although they look similar, they are quite different under the hood.

- **Hardware scrolling, kept.** Both versions scroll the easy way: a `VDU 30, 11` at the top of the screen makes the MOS nudge the CRTC display-start registers, so the hardware does the work for almost free. The 1983 version already got this right, so the rewrite kept it. I did consider writing directly to the CRTC's R12/R13 registers itself instead of going through the MOS, games like Repton did this, but I backed out of that pretty quickly due to the added complexity.
- **Direct sprite blits.** Each sprite is pre-encoded and written straight to screen memory, four bytes per scanline. No slow BASIC, no OS character calls in the path.
- **Ring-buffer collision.** Items are tracked in a 24-slot ring as they scroll from the top of the screen down to the caterpillar's row, so a "hit" is just a position lookup, with no per-pixel scan.
- **Deterministic by design.** The original just splatted random mushrooms on the screen but this one has a proper map like any other speed runner.
- **Score Attack.** The new version finishes at 4 seasons. Score is everything - grab what you can.
- **Game mechanics.** Hot streaks, bonus rounds and an easter egg 🥚

What I could not grasp in 1983 was that MODE 2 memory is laid out in character cells of 8 bytes. So stepping down one pixel row is usually just `+1`, until you fall off the bottom of a cell and have to leap `+633` bytes to land on the next character row down:

```asm
.advance_scanline
    INC temp0
    LDA temp0 : AND #7        ; still inside this character cell?
    BNE as_same_row           ; yes next byte is just +1
    CLC                       ; no cross to the next character row
    LDA scr_addr_lo : ADC #LO(633) : STA scr_addr_lo
    LDA scr_addr_hi : ADC #HI(633) : STA scr_addr_hi
.as_same_row
    INC scr_addr_lo
```

That one odd number, 633, is the whole quirk of BBC screen memory in a nutshell. No wonder I struggled with this at the time and why I found C64 sprites so much easier.

The original was ~110 lines of BASIC. The rewrite is around 1,250 lines of lightly commented 6502, which assembles down to just **3 KB** of machine code.

---

## 🎮 Seeing it run again

There's something uniquely satisfying about seeing old code come back to life.

Not really modernised. Just finished, the way I always meant to write it.

<p align="center">
  <img src="assets/caterpillar-2026.gif" alt="The 2026 rewrite — the same game in native 6502, with proper multi-colour sprites" width="500"><br>
  <em>The 2026 rewrite — the same game in native 6502, fast and fluid sprites</em>
</p>

---

## 🏆 Score to beat

**Will Newell — 3950**

---

## ⏳ Why this mattered

This was never really about optimisation.

It was about finishing something.

> If I say I'll do something, I'll do it.

Some things just take a little longer than expected 😄

---

## 🔗 Links

- BBC Micro Archive (the 1983 original): https://www.bbcmicro.co.uk/game.php?id=1066
- GitHub: https://github.com/newell-paul/caterpillar-assembler
- Play in the browser: https://newell-paul.github.io/caterpillar-assembler/

