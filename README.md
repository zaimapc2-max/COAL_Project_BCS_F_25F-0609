# Super Mario Engine

A 16-bit side-scrolling platform game written in **x86 assembly (NASM)** for **DOSBox**.
EL2003 – Computer Organization and Assembly Language, Semester Project, Fall 2026
National University of Computer & Emerging Sciences, Chiniot-Faisalabad Campus

## 1. Team

| Name | Roll number | Modules built |
|---|---|---|
| `<<< Zaima Amjad >>>` | `<<< 25F-0609 >>>` | `<<< Modules 1 - 15 >>>` |


- Section: `<<< CS 3rd Semester, section F>>>`
- Lab instructor: `<<< Shahzad Tanveer >>>`
- Repository: `<<< https://github.com/zaimapc2-max/COAL_Project_BCS_F_25F-0609 >>>`

---

## 2. What the game is

A single-player platform game. The player runs, jumps and stomps across a scrolling level, collects coins and
mushrooms, and touches the flag pole before running out of lives or time.

- **One complete level**, 60 tiles (960 pixels, three screens) wide and 12 tiles high.
- Two hero forms: **Small** Mario (health 1) and **Super** Mario (health 2).
- Two enemy types: **Goomba** and **Koopa Troopa** (with shell behaviour).
- Coins, `?` blocks (coin or mushroom), bricks, pipes, pits, stairs and a flag pole.
- A HUD with score, coins, world, time, lives and two hearts.
- Title, Playing, Paused, Dying, Life-lost, Win sequence, Level-complete and Game-over screens.
- Smooth, flicker-free drawing through an off-screen frame buffer.
- Our own keyboard and timer interrupt handlers (several keys at once, steady game speed).
- Restart without relaunching, and a clean exit that restores everything.

Everything the player sees and touches is built by us in assembly: the screen, the keyboard, the clock,
every character, sprite and rule. No libraries, engines, high-level code or ready-made sources are used.
All sprites, tiles, the font and the screens are our own artwork.

---

## 3. Tools

| Tool | Version |
|---|---|
| NASM (Netwide Assembler) | 2.x (tested with 2.16) |
| DOSBox | 0.74-3 or later |
| Processor / mode | 16-bit x86, Real Mode |
| Display | VGA Mode 13h, 320 x 200, 256 colours (segment `0A000h`) |
| Output | `MARIO.COM` (a `.COM` program: one segment, entry at offset `100h`) |

---

## 4. Build and run

### Build
```
nasm -f bin mario.asm -o MARIO.COM
```
The program must assemble **without errors or warnings**.

### Run in DOSBox
```
mount c C:\path\to\the\project
c:
MARIO
```

### Speed tip
The game draws a full 320 x 200 picture 30 times a second. If it runs slowly, give DOSBox more CPU power:
press **Ctrl + F12** a few times while the game runs, or set `cycles=max` in the DOSBox configuration file.
Game speed itself comes from the timer interrupt, so it is the same on every PC; a slow emulator can only
make the picture less smooth, never change the physics.

---

## 5. Controls

| Key | Scan code | Action |
|---|---|---|
| Left arrow | 4Bh | Move left |
| Right arrow | 4Dh | Move right |
| Left Shift | 2Ah | Run (higher speed limit) |
| Space | 39h | Jump (hold for a higher jump; needs a new press for every jump) |
| Up / Down arrow | 48h / 50h | Move the highlight in the title menu |
| Enter | 1Ch | Select in the menu, continue on end screens |
| P | 19h | Pause / resume |
| Esc | 01h | Playing or paused: back to the title. At the title: exit to DOS |

Several keys can be held together (for example Right + Shift + Space).

### Debug keys (listed here as the manual allows)

| Key | Scan code | Effect |
|---|---|---|
| T | 14h | Set the level clock to 5 seconds (test "time runs out") |
| C | 2Eh | Set coins to 99 (the next coin gives a life) |
| D | 20h | Show / hide the test overlay: lamps (ground, head hit, stomp, hurt, flag, Super), mini-map, speed/score/coin/life bars and a swatch for every palette colour |

---

## 6. Game states (in words)

The game is a state machine. A state number indexes a **jump table** of handler procedures; the main loop just
waits for the timer tick, calls the handler of the current state, copies the finished picture to the screen and
saves the keys.

| State | Entered when | Left when |
|---|---|---|
| **TITLE** | Program start; after Game Over; after Level Complete; Esc while playing or paused | Up/Down move the highlight. Enter on START GAME starts a new game (PLAYING). Enter on EXIT or Esc leaves (EXIT) |
| **PLAYING** | New game; after the Life-lost screen; P while paused | P pauses. Mario dies: DYING. Flag pole touched: WIN. Esc: TITLE |
| **PAUSED** | P while playing | P resumes. Esc: TITLE. Everything is frozen (updates and clock); the picture stays with a PAUSED banner |
| **DYING** | Mario dies (enemy, pit or clock at 0) | After about 1.5 s: lives - 1, then LIFE LOST (lives left) or GAME OVER (none left) |
| **LIFE LOST** | After the death animation | After about 2 s the level is reset and PLAYING resumes |
| **WIN** (win sequence) | Flag pole touched | Mario slides down the pole, then disappears for 1 s: LEVEL COMPLETE |
| **LEVEL COMPLETE** | After the win sequence | Enter: TITLE |
| **GAME OVER** | Last life lost | Enter: TITLE |
| **EXIT** | Exit chosen at the title (or Esc there) | Restores the keyboard and timer vectors and the timer rate, returns to text mode, exits to DOS |

---

## 7. How the game works (short version)

- **Frame order** (every frame, in PLAYING): wait for the timer tick, read the key table, update the clock, move
  Mario (one axis at a time with tile collision), update enemies, shells and mushrooms, resolve Mario against
  enemies, items and blocks, check death and the flag, update the camera, clear the frame buffer, draw
  background, tiles, items, enemies, Mario and HUD into it, copy it to video memory once.
- **Fixed-point physics**: speeds are 8.8 numbers (high byte = whole pixels, low byte = fraction), at 30 frames
  per second, with the suggested constants of the manual (acceleration, friction, walk and run limits, gravity,
  jump start, jump cut-off, maximum fall speed).
- **Camera**: `screen_x = world_x - camera_x`. The camera follows Mario when his screen x passes 160, never
  moves back to the left, and stops at 640 (level width - 320).
- **Tiles**: the level is a table of one byte per tile (60 x 12). Two copies are kept: `original_map` (never
  changed) and `working_map` (changed when blocks are hit and coins taken). A restart copies the original back
  with one block-move instruction.
- **Keyboard**: our own `INT 09h` handler fills a 128-byte key-state table (1 = held), ignoring the `E0h` prefix.
- **Timer**: our own `INT 08h` handler counts ticks at 30 per second and chains to the original handler about
  18.2 times per second so the DOS clock stays correct.

---

## 8. Memory choices

- A `.COM` program has **one 64 KB segment** for code, data and stack, loaded at offset `100h`. A full-screen
  frame buffer needs 64,000 bytes and cannot sit beside the code, so it lives in a **second segment**.
- **How it is reserved**: at the very start of `main`, `INT 21h, AH = 4Ah` shrinks our memory block to 64 KB
  (`1000h` paragraphs) and `INT 21h, AH = 48h` allocates **4000 paragraphs** (4000 x 16 = 64,000 bytes). The
  returned segment is stored in `buffer_seg`. If DOS refuses (carry flag set) the program prints a message and
  exits before changing the video mode.
- **All drawing goes through one variable, `draw_seg`.** It points at the frame buffer. Only `CopyBuffer`
  writes to video memory (`0A000h`).
- **Per frame**: `ClearBuffer` clears the buffer with `rep stosw` (32,000 words), the scene is drawn into it, and
  `CopyBuffer` copies it to the screen with `rep movsw` (32,000 words), once per timer tick.
- The program size is about 13.6 KB; the maps take 2 x 720 bytes, the sprites 3,840 bytes, the font 273 bytes.

---

## 9. The level (meets Section 5.15)

| Element | In our level |
|---|---|
| Size | 60 x 12 tiles (row 0 = HUD, ground in rows 10 and 11) |
| Pits | 2: columns 22-24 (3 wide) and 40-41 (2 wide) |
| Pipes | 2: columns 14-15 (2 high) and 30-31 (3 high) |
| `?` blocks | 3 with a coin (columns 10, 26, 46) and 2 with a mushroom (columns 8 and 34, one early) |
| Brick groups | 2: columns 17-19 and 36-39 |
| Free coins | 12 (row 8 columns 3-5, over the first pit, over the second pit, high above bricks) |
| Enemies | 4 Goombas and 2 Koopas, stored in their own table (not in the map) |
| End of level | Four ascending stair steps (columns 48-51), then a 7-tile flag pole with a base block |

Every item and block is reachable with the jump limits (a full jump is about 3.6 tiles).

---

## 10. Rules implemented (Section 5)

| Rule | Implemented as |
|---|---|
| Start | 3 lives, Small Mario (HP 1), 300 seconds |
| Coins | +200, coins counter + 1; 100 coins = +1 life, counter back to 0 |
| `?` block coin / mushroom | Becomes an empty block; coin +200 / mushroom appears on top and walks right |
| Mushroom | +1000; Small becomes Super (feet stay fixed); if already Super only the points |
| Brick | Small: nothing. Super: breaks, +50 |
| Stomp chain | 100, 200, 400, 500, 800, 1000, 2000, 4000, 5000, 8000, then 1-UP; resets on landing |
| Koopa shell | Stomped Koopa becomes a shell; kicking a stationary shell +400; sliding shell kills enemies +500 each and hurts Mario |
| Damage | Super becomes Small with 2 s of blinking invulnerability; Small dies; pits and clock kill at any health |
| Death | Hop up about 48 px then fall (pit: no hop), lives - 1, Life-lost screen or Game Over; score and coins kept; map, enemies, mushrooms, clock reset |
| Flag pole | Points by the height of the feet: 5000 / 2000 / 800 / 400 / 100; slide; time left x 50 bonus; no extra life |
| Clock | 300 down to 0, one per real second (from timer ticks), frozen while paused, dying and after the flag |
| Score | 32-bit (ADD/ADC), clamped to 999,999; lives capped at 99 |
| Enemies | At most 8 at once; they wait until within one tile of the screen; removed when they fall out or are far to the left |

---

## 11. Deviations from the manual (with reasons)

1. **Position format.** Velocities are exact 8.8 words, but the position is a 16-bit whole part plus an 8-bit
   fraction (16.8). A pure 8.8 position can only count to 255 pixels and the level is 960 pixels wide.
2. **A new Space press is needed for every jump.** Holding Space after landing does not bounce Mario again.
3. **Mushroom appears instantly** on top of its block instead of rising slowly out of it.
4. **Win sequence:** after sliding down the pole Mario simply disappears for one second (the manual allows
   "or simply disappears"); there is no castle.
5. **Higher stomp bounce:** holding Space after a stomp gives a bounce of -4.5 px/frame (normal -3.0).
6. **Stomping a stationary shell** kicks it (+400) without a bounce.
7. **Enemy and shell hitboxes** are the full 16 x 16 sprite; Mario's hitbox is 12 wide (centred) and 16 or 32
   high.
8. **Extra procedures.** The manual's Module 13 `AddScore(points)` takes a 16-bit amount (the largest single
   award is 15,000); the score itself is 32-bit.
9. **Debug keys** T, C and D (listed in section 5).
10. **Bricks** disappear without flying fragments; coin pop-ups are a short rising coin picture.

---

## 12. Bonus features

- **Walking animation:** while running on the ground Mario alternates between the standing and the running
  sprite every 8 frames.
- **Coin pop-up animation** above `?` blocks.
- Colour test screen with every palette colour (debug key D).

(Sound, a second level, a saved high score, the Fire flower, score pop-ups and the "hurry" blink are **not**
implemented.)

---

## 13. Known limitations

1. Mario can grow into a ceiling if he collects a mushroom directly under a very low block (cannot happen in
   our level, which always leaves two free tiles above the floor).
2. After winning, Mario disappears instead of walking into a castle.
3. A Koopa does not come back out of its shell.
4. The time bonus is added at once (no counting-down animation).
5. Sounds are not implemented.
6. Standing exactly on the border between two tiles uses the left and right edges of the hitbox only, so a
   very thin 1-pixel overlap with a ledge still counts as standing on it.

---

## 14. Project structure

```
COAL_Project_BCS_A_25F-0000_25F-0000/
|-- README.md
|-- build.bat            nasm -f bin mario.asm -o MARIO.COM
|-- MARIO.COM            the finished program
|-- src/
|   `-- mario.asm        all the source code (heavily commented)
|-- docs/
|   `-- report/          the Word report and screenshots
`-- assets/
    `-- sketches/        paper plans of the level and the sprites (optional)
```

The assembly source is organised in this order: header and constants, variables, palette, tile colours, level
maps, entity tables, enemy and chain tables, font, sprites, then the code (`main` and the state handlers,
interrupt handlers, physics, collision, items, enemies, drawing routines, screens).

Every procedure has a comment block: name, purpose, inputs, outputs and registers changed.

---

## 15. Testing

The 17 checks of the live demo (Section 7.7 of the manual) were exercised one by one:
title menu, walking/running/jumping, scrolling rules, coins, mushroom, bricks (Small and Super), stomp chain,
damage as Super and as Small, pit death, clock death, shell kick and kill, 100 coins, flag at top and bottom,
pause/resume/Esc, game over and new game, exit.

Debug keys (T, C, D) make the rare cases quick to reach.

---

## 16. References

- NASM documentation: *The Netwide Assembler* (nasm.us)
- Ralf Brown's Interrupt List (BIOS, DOS and hardware interrupts)
- Intel 8086/8088 family user's manual
- DOSBox documentation and debugger guide (dosbox.com)
- Course textbook and lecture slides on assembly language, interrupts and the stack
