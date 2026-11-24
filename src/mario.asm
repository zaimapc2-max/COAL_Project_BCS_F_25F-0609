; ============================================================================
;  MARIO.ASM  -  Super Mario Engine, DAY 9 reference build
;  Modules covered: 2-8 (video, map, sprites, buffer, camera, keyboard, timer),
;                   9 (physics), 10 (collision),
;                   12 (blocks, coins, mushroom)  + AddScore (part of 13)
; ============================================================================
        cpu 186                         ; allows OUTSB and PUSH imm
        bits 16
        org 100h

        jmp  main                       ; data goes after this jump

; ---------------- constants ----------------
SCREEN_W        equ 320
SCREEN_H        equ 200
VIDEO_SEG       equ 0A000h
TILE_SIZE       equ 16
SCREEN_COLS     equ 20
MAP_W           equ 60
MAP_H           equ 12
MAP_SIZE        equ MAP_W * MAP_H

LEVEL_W_PX      equ MAP_W * TILE_SIZE   ; level width in pixels = 960
CAMERA_FOLLOW   equ 160                 ; camera follows once Mario is past this
CAMERA_MAX      equ LEVEL_W_PX - SCREEN_W  ; last camera position = 640
MARIO_START_X   equ 32                  ; world x where every life starts

; ---- physics constants: 8.8 fixed point, 30 frames per second (Appendix A.5)
ACCEL           equ 0020h               ; 0.125 px/frame^2  direction key held
BRAKE           equ 0040h               ; 0.25  pressing the opposite direction
FRICTION        equ 0010h               ; 0.0625 no direction key
MAX_WALK        equ 0180h               ; 1.5  px/frame
MAX_RUN         equ 0280h               ; 2.5  px/frame (Shift held)
GRAVITY         equ 0040h               ; 0.25 added to vertical speed each frame
JUMP_START      equ 0FA80h              ; -5.5 (two's complement)
JUMP_CUT        equ 0FE00h              ; -2.0 space released while rising
MAX_FALL        equ 0400h               ; 4.0
MARIO_START_Y   equ 144                 ; top of Mario standing on row 9 (row 9 * 16)
MAX_LIVES       equ 99
START_LIVES     equ 3
MUSH_MAX        equ 4                   ; mushrooms alive at once
MUSH_REC        equ 12                  ; bytes per mushroom record (6 words)
M_ACTIVE        equ 0                   ; record fields (byte offsets)
M_X             equ 2                   ;   world x
M_Y             equ 4                   ;   world y (top)
M_YF            equ 6                   ;   fraction of y (low byte used)
M_VY            equ 8                   ;   vertical speed, 8.8
M_DIR           equ 10                  ;   +1 right, -1 left
POP_MAX         equ 4                   ; coin pop-ups at once
POP_REC         equ 6                   ; bytes per pop-up record: x, y, timer
POP_FRAMES      equ 16                  ; how long a coin pop-up lives

HB_OFF          equ 2                   ; hitbox starts 2 pixels inside the sprite
HB_W            equ 12                  ; hitbox is 12 pixels wide (centred)
HERO_H_SMALL    equ 16
HERO_H_SUPER    equ 32
PIT_Y           equ 192                 ; top of Mario at this y = fell out of the map
STOMP_BOUNCE    equ 0FD00h              ; -3.0 after defeating an enemy
FORM_SMALL      equ 0
FORM_SUPER      equ 1

SC_ESC          equ 01h                 ; scan codes (Appendix A.3)
SC_P            equ 19h
SC_ENTER        equ 1Ch
SC_LSHIFT       equ 2Ah
SC_SPACE        equ 39h
SC_UP           equ 48h
SC_LEFT         equ 4Bh
SC_RIGHT        equ 4Dh
SC_DOWN         equ 50h

PIT_DIVISOR     equ 39773               ; 1,193,182 Hz / 39,773 = 30 ticks/second
TICKS_PER_SEC   equ 30

BUFFER_PARAS    equ 4000                ; 64,000 bytes / 16 = 4000 paragraphs
BUFFER_WORDS    equ 32000               ; 64,000 bytes / 2 = 32,000 words
KEEP_PARAS      equ 1000h               ; 64 KB kept for the .COM program
SPRITE_W        equ 16                  ; every sprite is 16 pixels wide
SPRITE_H        equ 16                  ; normal height (tall = 2 x this)

TILE_SKY        equ 0
TILE_GROUND     equ 1
TILE_BRICK      equ 2
TILE_Q_COIN     equ 3
TILE_Q_MUSH     equ 4
TILE_EMPTY      equ 5
TILE_PIPE_TL    equ 6
TILE_PIPE_TR    equ 7
TILE_PIPE_BL    equ 8
TILE_PIPE_BR    equ 9
TILE_STAIR      equ 10
TILE_COIN       equ 11
TILE_FLAG       equ 12
TILE_COUNT      equ 13

COL_SKY         equ 1           ; strawberry milk pink
COL_GROUND      equ 2           ; deep matcha
COL_BRICK       equ 3           ; strawberry pink
COL_PIPE        equ 4           ; bright matcha
COL_HERO        equ 5           ; strawberry red
COL_ENEMY       equ 6           ; chocolate brown
COL_TEXT        equ 7           ; cream white
COL_HUD         equ 8           ; dark matcha
COL_OUTLINE     equ 9           ; dark berry
COL_PIPE_LIGHT  equ 10          ; matcha highlight
COL_COIN        equ 11          ; golden yellow
COL_GROUND_TOP  equ 12          ; light matcha grass
COL_SKIN        equ 13          ; warm tan
COL_WHITE       equ 14          ; pure white
COL_DARKBROWN   equ 15          ; hair and shoes
COL_TAN         equ 16          ; goomba body
COL_BLUSH       equ 17          ; cat blush and inner ears
PAL_COUNT       equ 18          ; number of palette entries

SPR_MIRROR      equ 1           ; flag bit 0: flip left-right
SPR_BLINK       equ 2           ; flag bit 1: draw on even frames only
SPR_TALL        equ 4           ; flag bit 2: 16x32 instead of 16x16

; ---------------- variables ----------------
draw_seg        dw VIDEO_SEG    ; segment all drawing goes to
frame_counter   dw 0            ; used by the blink flag
sprites_ready   db 0            ; 1 after DecodeSprites has run (run only once)
buffer_seg      dw 0            ; segment of the off-screen frame buffer
camera_x       dw 0            ; world x of the left edge of the screen
; ---- hero data (Module 9): position is whole pixels + 8-bit fraction,
;      velocity is 8.8 fixed point (signed word: high byte = whole pixels)
mario_x         dw MARIO_START_X ; WORLD x, whole pixels (used for camera/draw)
mario_xf        db 0            ; fraction of x (0..255 = 0..255/256 pixel)
mario_y         dw MARIO_START_Y ; y of the top of the sprite, whole pixels
mario_yf        db 0            ; fraction of y
mario_vx        dw 0            ; horizontal speed, 8.8 signed
mario_vy        dw 0            ; vertical speed, 8.8 signed (negative = up)
on_ground       db 1            ; 1 = standing on something solid
form            db FORM_SMALL   ; small or super
hp              db 1            ; health 1 or 2
invuln_timer    dw 0            ; frames of invulnerability left
stomp_chain     db 0            ; stomps since last touching the ground
space_was_down  db 0            ; Space state last frame (new press = new jump)
prev_feet_y     dw 0            ; y of his feet at the start of this frame
head_timer      db 0            ; frames the "head hit" lamp stays lit
stomp_timer     db 0            ; frames the "stomp" lamp stays lit (+ grace time)
hurt_timer      db 0            ; frames the "hurt" lamp stays lit
flag_touched    db 0            ; 1 once the flag pole was touched
flag_row        db 0            ; map row of his feet at that moment (2..8)

; ---- score, coins, lives (Module 13 will draw them as numbers)
score_lo        dw 0            ; 32-bit score = score_hi:score_lo
score_hi        dw 0
coins           db 0            ; 0..99
lives           db START_LIVES  ; 1..99

; which sprite for which pose: stand, run, jump (one word each)
small_poses     dw spr_small_stand, spr_small_run, spr_small_jump
super_poses     dw spr_super_stand, spr_super_run, spr_super_jump

; ---- entities (kept together so ClearEntities can wipe them in one go)
entities_start:
mushrooms:      times MUSH_MAX * MUSH_REC db 0
pops:           times POP_MAX * POP_REC db 0
entities_end:

; test enemies: x, y, width, height (a Goomba and a Koopa standing on row 9)
hit_targets:
        dw 300, 144, 16, 16
        dw 420, 144, 16, 16
hit_targets_end:
TARGET_COUNT    equ (hit_targets_end - hit_targets) / 8
key_table       times 128 db 0  ; 1 = key held, 0 = released (index = scan code)
tick_count      dw 0            ; +1 on every timer tick (changed by the handler)
last_tick       dw 0            ; tick_count seen by UpdateClock last frame
chain_acc       dw 0            ; accumulator: decides when to call the old timer
sec_acc         dw 0            ; ticks collected towards the next second
game_seconds    dw 0            ; real seconds elapsed (test bar; HUD clock later)
old_int8_off    dw 0            ; original timer vector  (offset first,
old_int8_seg    dw 0            ;                         then segment: JMP FAR)
old_int9_off    dw 0            ; original keyboard vector
old_int9_seg    dw 0
handlers_installed db 0         ; 1 once our handlers are in place
mario_flags     dw 0            ; SPR_MIRROR when facing left
msg_no_memory   db 'Not enough memory for the frame buffer.', 13, 10, '$'

; ---------------- palette (R,G,B each 0-63) ----------------
palette:
        db  0,  0,  0           ; 0  black (transparent)
        db 63, 53, 56           ; 1  sky
        db 18, 26, 13           ; 2  ground
        db 58, 21, 30           ; 3  brick
        db 37, 51, 25           ; 4  pipe
        db 55,  9, 17           ; 5  hero
        db 27, 15, 10           ; 6  enemy
        db 63, 62, 60           ; 7  text
        db 10, 14,  9           ; 8  HUD
        db 22,  7, 13           ; 9  outline
        db 50, 58, 40           ; 10 pipe light
        db 63, 50, 15           ; 11 coin
        db 30, 41, 20           ; 12 ground top
        db 56, 38, 25           ; 13 skin
        db 63, 63, 63           ; 14 white
        db 10,  5,  3           ; 15 dark brown
        db 50, 35, 22           ; 16 tan
        db 63, 46, 52           ; 17 blush pink

; colour used for each tile code (index = tile code)
tile_colour:
        db COL_SKY              ; 0  sky
        db COL_GROUND           ; 1  ground
        db COL_BRICK            ; 2  brick
        db COL_ENEMY            ; 3  ? block (coin)
        db COL_ENEMY            ; 4  ? block (mushroom)
        db COL_OUTLINE          ; 5  empty block
        db COL_PIPE_LIGHT       ; 6  pipe top-left
        db COL_PIPE_LIGHT       ; 7  pipe top-right
        db COL_PIPE             ; 8  pipe body-left
        db COL_PIPE             ; 9  pipe body-right
        db COL_GROUND_TOP       ; 10 stair block
        db COL_SKY              ; 11 coin (the coin sprite is drawn on top)
        db COL_TEXT             ; 12 flag pole

; level map, 60 x 12, one row per line. Never changed after assembly.
original_map:
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0     ; row 0
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0     ; row 1
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,12,0,0,0,0     ; row 2
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,12,0,0,0,0     ; row 3
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,11,11,11,11,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,12,0,0,0,0     ; row 4
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,12,0,0,0,0     ; row 5
        db 0,0,0,0,0,0,0,0,4,0,3,0,0,0,0,0,0,2,2,2,0,0,0,0,0,0,3,0,0,0,0,0,0,0,4,0,2,2,2,2,0,0,0,0,0,0,3,0,0,0,0,10,0,0,0,12,0,0,0,0     ; row 6
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,11,11,11,0,0,0,0,0,6,7,0,0,0,0,0,0,0,0,11,11,0,0,0,0,0,0,0,0,10,10,0,0,0,12,0,0,0,0     ; row 7
        db 0,0,0,11,11,11,0,0,0,0,0,0,0,0,6,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,8,9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,10,10,10,0,0,0,12,0,0,0,0     ; row 8
        db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,8,9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,8,9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,10,10,10,10,0,0,0,10,0,0,0,0     ; row 9
        db 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1     ; row 10
        db 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1     ; row 11


working_map:
        times MAP_SIZE db 0

; ---------------- sprite art ----------------
; Written as text, 16 characters per row. DecodeSprites turns
; the characters into palette numbers when the program starts.
;   .=0 transparent   3=brick pink   4=pipe green  5=hero red
;   6=enemy brown     7=cream        9=outline     a=10 light green
;   b=11 gold         d=13 skin      e=14 white    f=15 dark brown
;   g=16 tan
;   h=17 blush pink  (cat: e=white fur, f=dark eyes, 5/3=bow)
sprites_start:

spr_small_stand:
        db "..99........99.."
        db ".9he9.5..5.9eh9."
        db ".9ee95533559ee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeffeeeeffee9."
        db ".9eeffeeeeffee9."
        db ".9hheee33eeehh9."
        db "..9eeeeeeeeee9.."
        db "...99eeeeee99..."
        db "..e9444444449e.."
        db ".9e9444444449e9."
        db "...9444444449..."
        db "...9444..4449..."
        db "...9ee9..9ee9..."
        db "..9eee9..9eee9.."

spr_small_run:
        db "..99........99.."
        db ".9he9.5..5.9eh9."
        db ".9ee95533559ee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeffeeeeffee9."
        db ".9eeffeeeeffee9."
        db ".9hheee33eeehh9."
        db "..9eeeeeeeeee9.."
        db "...99eeeeee99..."
        db ".ee9444444449e.."
        db "..e9444444449..."
        db "...9444444449..."
        db "...944444..449.."
        db "..9ee9.....9ee9."
        db ".9eee9......9ee9"

spr_small_jump:
        db "..99........99.."
        db ".9he9.5..5.9eh9."
        db ".9ee95533559ee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeffeeeeffee9."
        db ".9eeffeeeeffee9."
        db ".9hheee33eeehh9."
        db "..9eeeeeeeeee9.."
        db ".e.99eeeeee99.e."
        db ".ee9444444449ee."
        db "..e9444444449e.."
        db "...9444444449..."
        db "..9444....4449.."
        db ".9ee9......9ee9."
        db ".9eee9....9eee9."

spr_super_stand:
        db "..99........99.."
        db ".9he9.5..5.9eh9."
        db ".9ee95533559ee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeffeeeeffee9."
        db ".9eeffeeeeffee9."
        db ".9hheee33eeehh9."
        db "..9eeeeeeeeee9.."
        db "...99eeeeee99..."
        db "..e9444444449e.."
        db ".ee9444444449ee."
        db ".e.9444444449.e."
        db "..e9444444449e.."
        db "...9444444449..."
        db "...9444444449..."
        db "..944444444449.."
        db "..944444444449.."
        db ".94444444444449."
        db ".93333333333339."
        db "...9ee9..9ee9..."
        db "...9ee9..9ee9..."
        db "...9ee9..9ee9..."
        db "...9ee9..9ee9..."
        db "...9ee9..9ee9..."
        db "...9ee9..9ee9..."
        db "...9ee9..9ee9..."
        db "...9ee9..9ee9..."
        db "..9eee9..9eee9.."
        db "..9eee9..9eee9.."
        db ".9eeee9..9eeee9."
        db ".99999....99999."

spr_super_run:
        db "..99........99.."
        db ".9he9.5..5.9eh9."
        db ".9ee95533559ee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeffeeeeffee9."
        db ".9eeffeeeeffee9."
        db ".9hheee33eeehh9."
        db "..9eeeeeeeeee9.."
        db "...99eeeeee99..."
        db "..e9444444449e.."
        db ".ee9444444449e.."
        db "..e9444444449..."
        db "...9444444449..."
        db "...9444444449..."
        db "...9444444449..."
        db "..944444444449.."
        db "..944444444449.."
        db ".94444444444449."
        db ".93333333333339."
        db "..9ee9....9ee9.."
        db ".9ee9......9ee9."
        db ".9ee9......9ee9."
        db ".9ee9......9ee9."
        db ".9ee9......9ee9."
        db ".9ee9......9ee9."
        db ".9ee9.......9e9."
        db ".9ee9.......9e9."
        db ".9eee9......9e9."
        db ".9eee9.....9ee9."
        db ".99999....99ee9."
        db ".99999....99999."

spr_super_jump:
        db "..99........99.."
        db ".9he9.5..5.9eh9."
        db ".9ee95533559ee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeeeeeeeeeee9."
        db ".9eeffeeeeffee9."
        db ".9eeffeeeeffee9."
        db ".9hheee33eeehh9."
        db "..9eeeeeeeeee9.."
        db "...99eeeeee99..."
        db "e.e9444444449e.e"
        db ".ee9444444449ee."
        db "..e9444444449e.."
        db "...9444444449..."
        db "...9444444449..."
        db "...9444444449..."
        db "..944444444449.."
        db "..944444444449.."
        db ".94444444444449."
        db ".93333333333339."
        db "..9ee9....9ee9.."
        db ".9ee9......9ee9."
        db ".9ee9......9ee9."
        db ".9ee9......9ee9."
        db ".9ee9......9ee9."
        db ".9ee9......9ee9."
        db ".9ee9......9ee9."
        db ".9ee9......9ee9."
        db ".9eee9....9eee9."
        db ".9eee9....9eee9."
        db ".9eeee9..9eeee9."
        db ".99999....99999."

spr_goomba:
        db "................"
        db ".....666666....."
        db "...6666666666..."
        db "..666666666666.."
        db ".66666666666666."
        db ".6eee666666eee6."
        db ".6e9e666666e9e6."
        db ".66666666666666."
        db "..666666666666.."
        db "...6666666666..."
        db "....gggggggg...."
        db ".....gggggg....."
        db ".....gggggg....."
        db "....gggggggg...."
        db "...fff....fff..."
        db "..ffff....ffff.."

spr_goomba_flat:
        db "................"
        db "................"
        db "................"
        db "................"
        db "................"
        db "................"
        db "................"
        db "................"
        db "................"
        db "................"
        db "...6666666666..."
        db "..66e66666e666.."
        db ".66666666666666."
        db "..gggggggggggg.."
        db "...fff....fff..."
        db "..ffff....ffff.."

spr_koopa:
        db "......dddd......"
        db ".....dddddd....."
        db ".....dd9dddd...."
        db ".....dddddd....."
        db "......dddd......"
        db ".....444444....."
        db "....44aa4444...."
        db "...4444aa44444.."
        db "...44a444a4444.."
        db "...4444444444..."
        db "...3333333333..."
        db "....33333333...."
        db "....dd....dd...."
        db "....dd....dd...."
        db "...ffff..ffff..."
        db "...ffff..ffff..."

spr_shell:
        db "................"
        db "................"
        db "................"
        db "................"
        db "................"
        db "................"
        db "................"
        db ".....444444....."
        db "...44aa444444..."
        db "..44aaaa444444.."
        db ".4444aa44444444."
        db ".44444444444444."
        db ".44444444444444."
        db "..333333333333.."
        db "...3333333333..."
        db "....33333333...."

spr_mushroom:
        db "................"
        db ".....333333....."
        db "...3333333333..."
        db "..337733337733.."
        db ".33773333337733."
        db ".33333777733333."
        db ".33333333333333."
        db ".33333333333333."
        db "..999999999999.."
        db ".....77777777..."
        db ".....79777797..."
        db ".....77777777..."
        db ".....77777777..."
        db "......777777...."
        db "......777777...."
        db "......999999...."

spr_coin:
        db "................"
        db ".....999999....."
        db "....9bbbbbb9...."
        db "...9bbbbbbbb9..."
        db "...9bbb77bbb9..."
        db "...9bb7bbbbb9..."
        db "...9bb7bbbbb9..."
        db "...9bb7bbbbb9..."
        db "...9bbbbbbbb9..."
        db "...9bbbbbbbb9..."
        db "...9bbbbbbbb9..."
        db "...9bbbbbbbb9..."
        db "....9bbbbbb9...."
        db ".....999999....."
        db "................"
        db "................"

sprites_end:
SPRITE_BYTES    equ sprites_end - sprites_start

; ---------------- world objects: WORLD x, y, sprite, flags ----------------
; Their positions are in the level, not on the screen. DrawWorldItems converts
; each one with  screen_x = world_x - camera_x  and skips those off screen.
world_items:
        dw 300, 144, spr_goomba,   0
        dw 420, 144, spr_koopa,    0
world_items_end:
ITEM_COUNT      equ (world_items_end - world_items) / 8   ; 4 words = 8 bytes


; ============================================================================
;  CODE
; ============================================================================
main:
        ; ---- memory: shrink our block, then allocate the frame buffer ----
        mov  ah, 4Ah                    ; DOS: resize memory block (ES = our PSP)
        mov  bx, KEEP_PARAS             ; keep 64 KB for code, data and stack
        int  21h
        jc   .no_memory
        mov  ah, 48h                    ; DOS: allocate memory
        mov  bx, BUFFER_PARAS           ; 4000 paragraphs = 64,000 bytes
        int  21h
        jc   .no_memory                 ; carry set = failed
        mov  [buffer_seg], ax
        mov  [draw_seg], ax             ; all drawing goes to the buffer

        mov  ax, 0013h                  ; BIOS: set VGA Mode 13h
        int  10h
        call SetPalette
        call DecodeSprites
        call ResetMap
        call InstallHandlers            ; keyboard + timer are ours from here on
        call NewGame                    ; score 0, 3 lives, level, Mario

.frame:
        call WaitTick                   ; 1. wait for the next timer tick
        call UpdateClock                ; 6. count real seconds
        call UpdateMario                ; 2-3. read the key table, move Mario
        call UpdateMushrooms            ; 4. mushrooms walk and fall
        call UpdatePops                 ;    coin pop-ups rise
        call CheckHazards               ; 5/7. pit, flag pole, enemy contact
        call CollectItems               ; 5. coin tiles, mushrooms
        call UpdateCamera               ; 8. follow Mario (Section 5.3)
        call ClearBuffer                ; 9. wipe last frame
        call DrawMap                    ;    tiles, shifted by the camera
        call DrawWorldItems             ;    objects placed in the level
        call DrawMushrooms
        call DrawPops
        call DrawMario
        call DrawMinimap                ;    test aid: where the camera is
        call DrawPhysicsBars            ;    test aid: on ground + speed
        call DrawStatusBars             ;    test aid: score, coins, lives
        call CopyBuffer                 ; 10. ONE copy to the screen per frame
        inc  word [frame_counter]
        cmp  byte [key_table + SC_ENTER], 0
        je   .no_restart
        call NewGame                    ; Enter: a completely new game
.no_restart:
        cmp  byte [key_table + SC_ESC], 0
        je   .frame
        jmp  Shutdown                   ; the ONLY way out of the game

.no_memory:                             ; handlers are not installed yet
        mov  dx, msg_no_memory          ; still in text mode: print and leave
        mov  ah, 9
        int  21h
        mov  ax, 4C01h
        int  21h

; ----------------------------------------------------------------------------
; KeyboardHandler  (hardware interrupt INT 09h)
; Purpose : record every key press/release in key_table (1 = held, 0 = not).
;           Ignores the 0E0h prefix that arrow keys send.
; Inputs  : scan code from port 60h
; Outputs : key_table updated
; Changes : none (AX, BX preserved; ends with IRET)
; Note    : DS is unknown inside an interrupt, so variables use the CS: prefix.
; ----------------------------------------------------------------------------
KeyboardHandler:
        push ax
        push bx
        in   al, 60h                    ; AL = scan code
        cmp  al, 0E0h
        je   .done                      ; extended-key prefix: ignore it
        mov  bl, al
        and  bl, 7Fh                    ; BL = key number (bit 7 removed)
        xor  bh, bh                     ; BX = table index
        test al, 80h                    ; bit 7 set = key released
        jnz  .released
        mov  byte [cs:key_table + bx], 1
        jmp  .done
.released:
        mov  byte [cs:key_table + bx], 0
.done:
        mov  al, 20h
        out  20h, al                    ; EOI: tell the PIC we are finished
        pop  bx
        pop  ax
        iret

; ----------------------------------------------------------------------------
; TimerHandler  (hardware interrupt INT 08h, now 30 ticks per second)
; Purpose : count ticks, and call the ORIGINAL timer handler 18.2 times per
;           second so the DOS clock keeps its normal pace.
; Inputs  : none
; Outputs : tick_count + 1
; Changes : none (AX preserved)
; Note    : when chaining, the old handler sends the EOI and does the IRET.
; ----------------------------------------------------------------------------
TimerHandler:
        push ax
        inc  word [cs:tick_count]
        mov  ax, PIT_DIVISOR
        add  [cs:chain_acc], ax         ; carry out about 18.2 times a second
        jc   .chain
        mov  al, 20h
        out  20h, al                    ; no chaining this tick: we send the EOI
        pop  ax
        iret
.chain:
        pop  ax
        jmp  far [cs:old_int8_off]      ; old handler finishes with EOI + IRET

; ----------------------------------------------------------------------------
; InstallHandlers
; Purpose : save the old INT 08h/09h vectors, install ours, speed the timer
;           up to 30 ticks per second.
; Inputs  : none        Outputs : none
; Changes : none (AX, BX, DX, ES preserved)
; ----------------------------------------------------------------------------
InstallHandlers:
        push ax
        push bx
        push dx
        push es
        mov  ax, 3509h                  ; DOS: get vector 09h -> ES:BX
        int  21h
        mov  [old_int9_off], bx
        mov  [old_int9_seg], es
        mov  ax, 3508h                  ; DOS: get vector 08h -> ES:BX
        int  21h
        mov  [old_int8_off], bx
        mov  [old_int8_seg], es
        cli                             ; no interrupts while we switch over
        mov  dx, KeyboardHandler        ; DS:DX = new handler (DS = CS in a .COM)
        mov  ax, 2509h                  ; DOS: set vector 09h
        int  21h
        mov  dx, TimerHandler
        mov  ax, 2508h                  ; DOS: set vector 08h
        int  21h
        mov  al, 36h                    ; PIT channel 0, lo/hi byte, square wave
        out  43h, al
        mov  ax, PIT_DIVISOR
        out  40h, al                    ; low byte of the divisor
        mov  al, ah
        out  40h, al                    ; high byte
        mov  byte [handlers_installed], 1
        sti
        pop  es
        pop  dx
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; Shutdown   (never returns - every exit from the game jumps here)
; Purpose : put the timer rate and both vectors back, return to text mode,
;           exit to DOS.
; Inputs  : none        Outputs : none
; ----------------------------------------------------------------------------
Shutdown:
        cmp  byte [handlers_installed], 0
        je   .text_mode                 ; nothing to undo
        cli
        mov  al, 36h
        out  43h, al
        xor  ax, ax                     ; divisor 0 = 65,536 = the 18.2 Hz default
        out  40h, al
        out  40h, al
        push ds
        mov  dx, [old_int8_off]         ; read both BEFORE changing DS
        mov  ax, [old_int8_seg]
        mov  ds, ax
        mov  ax, 2508h                  ; DOS: set vector 08h = original timer
        int  21h
        pop  ds
        push ds
        mov  dx, [old_int9_off]
        mov  ax, [old_int9_seg]
        mov  ds, ax
        mov  ax, 2509h                  ; DOS: set vector 09h = original keyboard
        int  21h
        pop  ds
        mov  byte [handlers_installed], 0
        sti
.text_mode:
        mov  ax, 0003h                  ; text mode (also resets the palette)
        int  10h
        mov  ax, 4C00h                  ; DOS exit (also frees the buffer)
        int  21h

; ----------------------------------------------------------------------------
; WaitTick
; Purpose : wait until the timer handler has counted one more tick
;           (replaces any delay loop: speed is the same on every PC)
; Inputs  : none        Outputs : none
; Changes : none (AX preserved)
; ----------------------------------------------------------------------------
WaitTick:
        push ax
        mov  ax, [tick_count]           ; tick number when we arrived
.wait:
        cmp  ax, [tick_count]           ; re-read memory: the interrupt changes it
        je   .wait
        pop  ax
        ret

; ----------------------------------------------------------------------------
; UpdateClock
; Purpose : turn elapsed ticks into real seconds (30 ticks = 1 second).
;           Counts the ticks that really passed, so a slow frame loses nothing.
; Inputs  : none        Outputs : game_seconds
; Changes : none (AX, BX preserved)
; ----------------------------------------------------------------------------
UpdateClock:
        push ax
        push bx
        mov  ax, [tick_count]
        mov  bx, ax                     ; keep this reading
        sub  ax, [last_tick]            ; ticks since last frame (wrap-safe)
        mov  [last_tick], bx
        add  [sec_acc], ax              ; collect them
.more:
        cmp  word [sec_acc], TICKS_PER_SEC
        jb   .done
        sub  word [sec_acc], TICKS_PER_SEC
        inc  word [game_seconds]        ; one real second has passed
        jmp  .more
.done:
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; UpdateMario
; Purpose : Section 5.2 physics (8.8 fixed point) + Section 5.6 tile collision.
;           One axis at a time, X first, then Y:
;           accelerate/brake/friction -> move X -> ResolveX
;           -> jump, gravity -> move Y -> ResolveY
; Inputs  : key_table and the hero data     Outputs : the hero data
; Changes : none (AX, BX, CX, DX preserved)
; ----------------------------------------------------------------------------
UpdateMario:
        push ax
        push bx
        push cx
        push dx

        call HeroHeight                 ; remember where his feet were this frame
        add  ax, [mario_y]              ; (the stomp test needs "previous feet")
        mov  [prev_feet_y], ax

        ; ---------- horizontal: which way is the player pushing? ----------
        xor  bx, bx                     ; BX = direction: -1, 0 or +1
        cmp  byte [key_table + SC_RIGHT], 0
        je   .no_right
        inc  bx
        mov  word [mario_flags], 0      ; face right
.no_right:
        cmp  byte [key_table + SC_LEFT], 0
        je   .no_left
        dec  bx
        mov  word [mario_flags], SPR_MIRROR    ; face left
.no_left:
        mov  cx, MAX_WALK               ; CX = speed limit (positive)
        cmp  byte [key_table + SC_LSHIFT], 0
        je   .limit_set
        mov  cx, MAX_RUN                ; Shift raises the limit
.limit_set:
        mov  ax, [mario_vx]             ; AX = horizontal speed (8.8 signed)
        test bx, bx
        je   .friction
        jl   .go_left

        mov  dx, ACCEL                  ; ---- pushing right ----
        test ax, ax
        jns  .right_add
        mov  dx, BRAKE                  ; moving left: brake harder
.right_add:
        add  ax, dx
        cmp  ax, cx                     ; signed compare
        jle  .speed_done
        mov  ax, cx                     ; cap at the limit
        jmp  .speed_done

.go_left:
        mov  dx, ACCEL                  ; ---- pushing left ----
        test ax, ax
        jle  .left_sub
        mov  dx, BRAKE                  ; moving right: brake harder
.left_sub:
        sub  ax, dx
        neg  cx                         ; CX = -limit
        cmp  ax, cx
        jge  .speed_done
        mov  ax, cx
        jmp  .speed_done

.friction:                              ; ---- no direction key ----
        test ax, ax
        jz   .speed_done
        js   .friction_neg
        sub  ax, FRICTION               ; moving right: slow down
        jns  .speed_done
        xor  ax, ax                     ; do not slide backwards: stop at 0
        jmp  .speed_done
.friction_neg:
        add  ax, FRICTION               ; moving left: slow down
        js   .speed_done
        xor  ax, ax
.speed_done:
        mov  [mario_vx], ax

        ; ---------- move horizontally, then fix collisions on X ----------
        mov  dl, al                     ; DL = fraction part of the speed
        sar  ax, 8                      ; AX = whole part (sign kept)
        add  [mario_xf], dl             ; fractions first: may set the carry
        adc  [mario_x], ax              ; whole pixels + carry
        cmp  word [mario_x], 0          ; SIGNED: past the left end?
        jge  .left_end_ok
        mov  word [mario_x], 0
        mov  byte [mario_xf], 0
        mov  word [mario_vx], 0
.left_end_ok:
        cmp  word [mario_x], LEVEL_W_PX - SPRITE_W
        jle  .right_end_ok
        mov  word [mario_x], LEVEL_W_PX - SPRITE_W
        mov  byte [mario_xf], 0
        mov  word [mario_vx], 0
.right_end_ok:
        call ResolveX                   ; walls: never sink into a tile

        ; ---------- jump ----------
        cmp  byte [key_table + SC_SPACE], 0
        je   .space_up
        cmp  byte [space_was_down], 0
        jne  .jump_done                 ; Space still held from before: no new jump
        cmp  byte [on_ground], 0
        je   .jump_done                 ; in the air: no double jump
        mov  word [mario_vy], JUMP_START
        mov  byte [on_ground], 0
        jmp  .jump_done
.space_up:                              ; variable jump height
        cmp  word [mario_vy], JUMP_CUT  ; signed: rising faster than -2.0 ?
        jge  .jump_done
        mov  word [mario_vy], JUMP_CUT  ; cut the jump short
.jump_done:
        mov  al, [key_table + SC_SPACE]
        mov  [space_was_down], al       ; remember for next frame

        ; ---------- gravity, move vertically, then fix collisions on Y ----------
        mov  ax, [mario_vy]
        add  ax, GRAVITY
        cmp  ax, MAX_FALL
        jle  .fall_ok
        mov  ax, MAX_FALL
.fall_ok:
        mov  [mario_vy], ax
        mov  dl, al
        sar  ax, 8
        add  [mario_yf], dl
        adc  [mario_y], ax
        call ResolveY                   ; floor, ceiling, on_ground, block hits

        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; HeroHeight
; Purpose : height of Mario's body in pixels (16 small, 32 super)
; Inputs  : form        Outputs : AX = height
; Changes : AX only
; ----------------------------------------------------------------------------
HeroHeight:
        mov  ax, HERO_H_SMALL
        cmp  byte [form], FORM_SMALL
        je   .done
        mov  ax, HERO_H_SUPER
.done:
        ret

; ----------------------------------------------------------------------------
; IsSolid(px, py)                   pushed in that order
; Purpose : is the tile at this WORLD pixel solid? (codes 1..10 are solid;
;           sky, coin and flag pole are not; outside the level: see GetTile)
; Inputs  : [bp+6]=px  [bp+4]=py
; Outputs : AX = 1 solid, 0 not solid
; Changes : AX only
; ----------------------------------------------------------------------------
IsSolid:
        push bp
        mov  bp, sp
        push word [bp+6]
        push word [bp+4]
        call GetTile                    ; AX = tile code
        dec  ax                         ; code 1..10 -> 0..9
        cmp  ax, TILE_STAIR - TILE_GROUND + 1
        jae  .no                        ; unsigned: code 0 wraps to a huge number
        mov  ax, 1
        jmp  .out
.no:
        xor  ax, ax
.out:
        pop  bp
        ret  4

; ----------------------------------------------------------------------------
; SolidColumn(px)
; Purpose : is anything solid at x = px, anywhere along Mario's body height?
;           Samples the top, every 16 pixels, and the bottom pixel row, so a
;           16 or 32 pixel tall body can never skip over a tile.
; Inputs  : [bp+4]=px   (also reads mario_y and form)
; Outputs : AX = 1 solid found, 0 none
; Changes : AX only
; ----------------------------------------------------------------------------
SolidColumn:
        push bp
        mov  bp, sp
        push bx
        push cx
        push dx
        call HeroHeight
        mov  cx, ax                     ; CX = body height
        mov  bx, [mario_y]              ; BX = sample row, starts at the head
        mov  dx, bx
        add  dx, cx
        dec  dx                         ; DX = bottom pixel row of the body
.sample:
        push word [bp+4]
        push bx
        call IsSolid
        test ax, ax
        jnz  .out                       ; found one: AX = 1
        cmp  bx, dx
        jge  .out                       ; tested the bottom row: AX = 0
        add  bx, 16                     ; next sample one tile lower
        cmp  bx, dx
        jle  .sample
        mov  bx, dx                     ; past the bottom: test the last row
        jmp  .sample
.out:
        pop  dx
        pop  cx
        pop  bx
        pop  bp
        ret  2

; ----------------------------------------------------------------------------
; SolidRow(py)
; Purpose : is anything solid at pixel row py, under Mario's hitbox width?
;           (hitbox is 12 wide, so its left and right edge points are enough)
; Inputs  : [bp+4]=py
; Outputs : AX = 1 solid found, 0 none
; Changes : AX only
; ----------------------------------------------------------------------------
SolidRow:
        push bp
        mov  bp, sp
        push bx
        mov  bx, [mario_x]
        add  bx, HB_OFF                 ; BX = left edge of the hitbox
        push bx
        push word [bp+4]
        call IsSolid
        test ax, ax
        jnz  .out
        add  bx, HB_W - 1               ; BX = right edge of the hitbox
        push bx
        push word [bp+4]
        call IsSolid
.out:
        pop  bx
        pop  bp
        ret  2

; ----------------------------------------------------------------------------
; ResolveX
; Purpose : after Mario moved sideways, look at the tiles on the side he moves
;           towards. If one is solid, put him against it and stop him.
; Inputs  : mario_vx (direction), position    Outputs : mario_x, mario_vx
; Changes : none (AX, DX preserved)
; ----------------------------------------------------------------------------
ResolveX:
        push ax
        push dx
        cmp  word [mario_vx], 0
        je   .done                      ; not moving sideways
        jl   .left
        mov  dx, [mario_x]              ; ---- moving right ----
        add  dx, HB_OFF + HB_W - 1      ; DX = right edge pixel
        push dx
        call SolidColumn
        test ax, ax
        jz   .done
        shr  dx, 4
        shl  dx, 4                      ; left side of the wall tile
        sub  dx, HB_OFF + HB_W          ; right edge ends just before it
        jmp  .snap
.left:
        mov  dx, [mario_x]              ; ---- moving left ----
        add  dx, HB_OFF                 ; DX = left edge pixel
        push dx
        call SolidColumn
        test ax, ax
        jz   .done
        shr  dx, 4
        inc  dx
        shl  dx, 4                      ; right side of the wall tile
        sub  dx, HB_OFF                 ; left edge starts just after it
.snap:
        mov  [mario_x], dx
        mov  byte [mario_xf], 0
        mov  word [mario_vx], 0         ; he stops against the wall
.done:
        pop  dx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; ResolveY
; Purpose : after Mario moved vertically:
;           rising  -> if his head is inside a solid tile: put him under it,
;                      stop him and trigger the block (OnHeadHit)
;           falling -> if his feet are inside a solid tile: put him on top of
;                      it. Then test the pixel row under his feet to set
;                      on_ground (and reset the stomp chain).
;           Falling out of the map sets nothing here (CheckHazards: pit).
; Inputs  : mario_vy, position    Outputs : mario_y, mario_vy, on_ground
; Changes : none (AX, BX, CX preserved)
; ----------------------------------------------------------------------------
ResolveY:
        push ax
        push bx
        push cx
        call HeroHeight
        mov  cx, ax                     ; CX = body height
        cmp  word [mario_vy], 0
        jl   .rising

        mov  bx, [mario_y]              ; ---- falling or resting ----
        add  bx, cx
        dec  bx                         ; BX = pixel row of the feet
        push bx
        call SolidRow
        test ax, ax
        jz   .check_ground
        shr  bx, 4
        shl  bx, 4                      ; top of the tile the feet are in
        sub  bx, cx                     ; y = tile top - body height
        mov  [mario_y], bx
        mov  byte [mario_yf], 0
        mov  word [mario_vy], 0
.check_ground:
        mov  bx, [mario_y]
        add  bx, cx                     ; BX = pixel row just under the feet
        push bx
        call SolidRow
        test ax, ax
        jz   .air
        mov  byte [on_ground], 1        ; something solid is right below
        mov  byte [stomp_chain], 0      ; landing resets the stomp chain
        mov  word [mario_vy], 0         ; resting: no gravity build-up
        mov  byte [mario_yf], 0
        jmp  .done
.air:
        mov  byte [on_ground], 0
        jmp  .done

.rising:
        mov  byte [on_ground], 0
        mov  bx, [mario_y]              ; BX = pixel row of the head
        push bx
        call SolidRow
        test ax, ax
        jz   .done
        mov  ax, [mario_x]              ; the block is the tile under the
        add  ax, HB_OFF + HB_W / 2      ; horizontal CENTRE of the head
        shr  ax, 4                      ; AX = column
        push ax
        mov  ax, bx
        shr  ax, 4                      ; AX = row of the head
        push ax
        shr  bx, 4
        inc  bx
        shl  bx, 4                      ; bottom edge of the tile above him
        mov  [mario_y], bx              ; head just under the tile
        mov  byte [mario_yf], 0
        mov  word [mario_vy], 0         ; he starts falling
        call OnHeadHit                  ; (col, row) already pushed
.done:
        pop  cx
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; OnHeadHit(col, row)               pushed in that order
; Purpose : Mario's head hit the tile (col,row) from below (Section 5.9):
;           brick       small Mario: nothing.  Super Mario: tile becomes sky, +50
;           "?" coin    becomes an empty block, coin pops out (+200, coins +1)
;           "?" mushroom becomes an empty block, a mushroom appears on top
;           anything else: nothing.  All changes are made in working_map only.
; Inputs  : [bp+6]=col  [bp+4]=row
; Outputs : working_map, score, coins, mushroom table, head_timer (test lamp)
; Changes : none (AX, BX preserved)
; ----------------------------------------------------------------------------
OnHeadHit:
        push bp
        mov  bp, sp
        push ax
        push bx
        mov  byte [head_timer], 10      ; lights the test lamp
        cmp  word [bp+6], MAP_W
        jae  .out                       ; outside the map: nothing to change
        cmp  word [bp+4], MAP_H
        jae  .out
        mov  bx, [bp+4]
        mov  ax, bx
        shl  ax, 6
        shl  bx, 2
        sub  ax, bx                     ; row * 60
        add  ax, [bp+6]                 ; + column
        mov  bx, ax                     ; BX = map index of the hit tile
        mov  al, [working_map + bx]
        cmp  al, TILE_Q_COIN
        je   .coin_block
        cmp  al, TILE_Q_MUSH
        je   .mushroom_block
        cmp  al, TILE_BRICK
        jne  .out                       ; empty block, ground ...: nothing
        cmp  byte [form], FORM_SUPER
        jne  .out                       ; small Mario only bumps a brick
        mov  byte [working_map + bx], TILE_SKY   ; Super Mario breaks it
        push word 50
        call AddScore                   ; +50
        jmp  .out
.coin_block:
        mov  byte [working_map + bx], TILE_EMPTY
        call AddCoin                    ; +200 and coins + 1
        mov  ax, [bp+6]
        shl  ax, 4                      ; x of the block
        push ax
        mov  ax, [bp+4]
        dec  ax
        shl  ax, 4                      ; y of the tile above the block
        push ax
        call SpawnCoinPop               ; the little coin that jumps out
        jmp  .out
.mushroom_block:
        mov  byte [working_map + bx], TILE_EMPTY
        push word [bp+6]
        push word [bp+4]
        call SpawnMushroom
.out:
        pop  bx
        pop  ax
        pop  bp
        ret  4

; ----------------------------------------------------------------------------
; AddScore(points)
; Purpose : the ONE place where points are added (Section 5.4). 32-bit score
;           in two words with ADD / ADC, clamped to 999,999.
; Inputs  : [bp+4]=points (0..65535)
; Outputs : score_lo, score_hi
; Changes : none (AX preserved)
; ----------------------------------------------------------------------------
AddScore:
        push bp
        mov  bp, sp
        push ax
        mov  ax, [bp+4]
        add  [score_lo], ax             ; low word first ...
        adc  word [score_hi], 0         ; ... then the high word + the carry
        cmp  word [score_hi], 0Fh       ; 999,999 = 000F423Fh
        jb   .done
        ja   .clamp
        cmp  word [score_lo], 423Fh
        jbe  .done
.clamp:
        mov  word [score_hi], 0Fh
        mov  word [score_lo], 423Fh
.done:
        pop  ax
        pop  bp
        ret  2

; ----------------------------------------------------------------------------
; AddLife
; Purpose : one more life, never more than 99
; Inputs  : none        Outputs : lives        Changes : none
; ----------------------------------------------------------------------------
AddLife:
        cmp  byte [lives], MAX_LIVES
        jae  .done
        inc  byte [lives]
.done:
        ret

; ----------------------------------------------------------------------------
; AddCoin
; Purpose : a coin was collected: +200 points, coins + 1. At 100 coins the
;           counter returns to 0 and Mario gets a life (no points for that).
; Inputs  : none        Outputs : score, coins, lives        Changes : none
; ----------------------------------------------------------------------------
AddCoin:
        push word 200
        call AddScore
        inc  byte [coins]
        cmp  byte [coins], 100
        jb   .done
        mov  byte [coins], 0
        call AddLife
.done:
        ret

; ----------------------------------------------------------------------------
; SpawnCoinPop(x, y)                pushed in that order
; Purpose : start the little coin animation that rises out of a "?" block
;           (WORLD position; it rises 2 pixels per frame for 16 frames)
; Inputs  : [bp+6]=x  [bp+4]=y        Outputs : pops table
; Changes : none (BX, CX preserved)
; ----------------------------------------------------------------------------
SpawnCoinPop:
        push bp
        mov  bp, sp
        push bx
        push cx
        mov  bx, pops
        mov  cx, POP_MAX
.find:
        cmp  word [bx+4], 0             ; timer 0 = free slot
        je   .found
        add  bx, POP_REC
        loop .find
        jmp  .out                       ; all busy: skip the animation
.found:
        mov  cx, [bp+6]
        mov  [bx], cx                   ; x
        mov  cx, [bp+4]
        mov  [bx+2], cx                 ; y
        mov  word [bx+4], POP_FRAMES    ; timer
.out:
        pop  cx
        pop  bx
        pop  bp
        ret  4

; ----------------------------------------------------------------------------
; UpdatePops
; Purpose : move every active coin pop-up up by 2 pixels, count its timer down
; Inputs  : none        Outputs : pops table        Changes : none
; ----------------------------------------------------------------------------
UpdatePops:
        push bx
        push cx
        mov  bx, pops
        mov  cx, POP_MAX
.next:
        cmp  word [bx+4], 0
        je   .skip
        sub  word [bx+2], 2             ; rise
        dec  word [bx+4]
.skip:
        add  bx, POP_REC
        loop .next
        pop  cx
        pop  bx
        ret

; ----------------------------------------------------------------------------
; DrawPops
; Purpose : draw the active coin pop-ups (screen_x = world_x - camera_x)
; Inputs  : none        Outputs : none        Changes : none
; ----------------------------------------------------------------------------
DrawPops:
        push ax
        push bx
        push cx
        mov  bx, pops
        mov  cx, POP_MAX
.next:
        cmp  word [bx+4], 0
        je   .skip
        mov  ax, [bx]
        sub  ax, [camera_x]             ; screen x
        cmp  ax, -SPRITE_W
        jle  .skip
        cmp  ax, SCREEN_W
        jge  .skip
        push ax
        push word [bx+2]
        push word spr_coin
        push word 0
        call DrawSprite
.skip:
        add  bx, POP_REC
        loop .next
        pop  cx
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; SpawnMushroom(col, row)           pushed in that order
; Purpose : put a mushroom on top of the "?" block at (col,row). It starts
;           moving to the right. If all 4 slots are busy nothing happens.
; Inputs  : [bp+6]=col  [bp+4]=row        Outputs : mushroom table
; Changes : none (AX, BX, CX preserved)
; ----------------------------------------------------------------------------
SpawnMushroom:
        push bp
        mov  bp, sp
        push ax
        push bx
        push cx
        mov  bx, mushrooms
        mov  cx, MUSH_MAX
.find:
        cmp  word [bx+M_ACTIVE], 0
        je   .found
        add  bx, MUSH_REC
        loop .find
        jmp  .out                       ; table full
.found:
        mov  word [bx+M_ACTIVE], 1
        mov  ax, [bp+6]
        shl  ax, 4
        mov  [bx+M_X], ax               ; same column as the block
        mov  ax, [bp+4]
        dec  ax
        shl  ax, 4
        mov  [bx+M_Y], ax               ; the tile row above the block
        mov  word [bx+M_YF], 0
        mov  word [bx+M_VY], 0
        mov  word [bx+M_DIR], 1         ; moving right
.out:
        pop  cx
        pop  bx
        pop  ax
        pop  bp
        ret  4

; ----------------------------------------------------------------------------
; UpdateMushrooms
; Purpose : update every active mushroom (Section 5.9)
; Inputs  : none        Outputs : mushroom table        Changes : none
; ----------------------------------------------------------------------------
UpdateMushrooms:
        push bx
        push cx
        mov  bx, mushrooms
        mov  cx, MUSH_MAX
.next:
        push bx
        call UpdateOneMushroom
        add  bx, MUSH_REC
        loop .next
        pop  cx
        pop  bx
        ret

; ----------------------------------------------------------------------------
; UpdateOneMushroom(ptr)
; Purpose : one mushroom: walk 1 pixel per frame, turn around at walls,
;           gravity, land on solid tiles, disappear in a pit or when it is far
;           to the left of the screen.
; Inputs  : [bp+4]=address of the record
; Outputs : the record        Changes : none (AX, BX, CX, DX preserved)
; ----------------------------------------------------------------------------
UpdateOneMushroom:
        push bp
        mov  bp, sp
        push ax
        push bx
        push cx
        push dx
        mov  bx, [bp+4]
        cmp  word [bx+M_ACTIVE], 0
        jne  .alive                     ; .out is too far for ONE short jump,
        jmp  .out                       ; so: jump over a JMP (JMP reaches anywhere)
.alive:
        mov  ax, [bx+M_DIR]             ; ---- walk (+1 right / -1 left) ----
        add  [bx+M_X], ax
        mov  cx, [bx+M_X]               ; CX = x of the leading edge
        test ax, ax
        jl   .edge_ready
        add  cx, 15                     ; moving right: right edge
.edge_ready:
        push cx
        push word [bx+M_Y]              ; top of the body
        call IsSolid
        test ax, ax
        jnz  .hit_wall
        mov  dx, [bx+M_Y]
        add  dx, 15                     ; bottom of the body
        push cx
        push dx
        call IsSolid
        test ax, ax
        jz   .no_wall
.hit_wall:
        mov  ax, [bx+M_DIR]
        sub  [bx+M_X], ax               ; undo the step
        neg  word [bx+M_DIR]            ; and turn around
.no_wall:

        mov  ax, [bx+M_VY]              ; ---- gravity and fall ----
        add  ax, GRAVITY
        cmp  ax, MAX_FALL
        jle  .fall_ok
        mov  ax, MAX_FALL
.fall_ok:
        mov  [bx+M_VY], ax
        mov  dl, al
        sar  ax, 8
        add  [bx+M_YF], dl              ; fractions first, then whole pixels
        adc  [bx+M_Y], ax
        mov  cx, [bx+M_Y]
        add  cx, 15                     ; CX = pixel row of its feet
        push word [bx+M_X]
        push cx
        call IsSolid
        test ax, ax
        jnz  .land
        mov  ax, [bx+M_X]
        add  ax, 15
        push ax
        push cx
        call IsSolid
        test ax, ax
        jz   .no_land
.land:
        shr  cx, 4
        shl  cx, 4                      ; top of the tile its feet are in
        sub  cx, 16
        mov  [bx+M_Y], cx               ; stand on it
        mov  byte [bx+M_YF], 0
        mov  word [bx+M_VY], 0
.no_land:

        cmp  word [bx+M_Y], PIT_Y       ; ---- fell into a pit ----
        jl   .not_in_pit
        mov  word [bx+M_ACTIVE], 0
        jmp  .out
.not_in_pit:
        mov  ax, [bx+M_X]               ; ---- far to the left of the screen ----
        sub  ax, [camera_x]
        cmp  ax, -32
        jge  .out
        mov  word [bx+M_ACTIVE], 0
.out:
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        pop  bp
        ret  2

; ----------------------------------------------------------------------------
; GrowMario
; Purpose : Small -> Super (HP 2). His FEET stay where they are, so the top of
;           the taller sprite moves up: y_top = y_feet - height (16 higher).
; Inputs  : none        Outputs : form, hp, mario_y        Changes : none
; ----------------------------------------------------------------------------
GrowMario:
        mov  byte [form], FORM_SUPER
        mov  byte [hp], 2
        sub  word [mario_y], HERO_H_SUPER - HERO_H_SMALL
        ret

; ----------------------------------------------------------------------------
; CollectCoins
; Purpose : every coin tile that Mario's body overlaps is collected:
;           tile becomes sky, +200, coins + 1 (AddCoin)
; Inputs  : mario position, form        Outputs : working_map, score, coins
; Changes : none (all registers preserved)
; ----------------------------------------------------------------------------
CollectCoins:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        call HeroHeight
        add  ax, [mario_y]
        dec  ax                         ; AX = bottom pixel row of the body
        test ax, ax
        js   .out                       ; completely above the map
        shr  ax, 4
        cmp  ax, MAP_H
        jb   .last_row_ok
        mov  ax, MAP_H - 1
.last_row_ok:
        mov  dx, ax                     ; DX = last map row touched
        mov  ax, [mario_y]
        test ax, ax
        jns  .first_row_ok
        xor  ax, ax
.first_row_ok:
        shr  ax, 4
        mov  bx, ax                     ; BX = first map row touched
        cmp  bx, dx
        ja   .out                       ; below the map (falling into a pit)
        mov  si, [mario_x]
        add  si, HB_OFF                 ; left edge of the hitbox
        mov  cx, si
        add  cx, HB_W - 1               ; right edge
        shr  si, 4                      ; SI = first column
        shr  cx, 4                      ; CX = last column
.row_loop:
        mov  di, si                     ; DI = column, restarts every row
.col_loop:
        mov  ax, bx
        shl  ax, 6
        push bx
        shl  bx, 2
        sub  ax, bx                     ; row * 60
        pop  bx
        add  ax, di                     ; + column = map index
        push bx
        mov  bx, ax
        cmp  byte [working_map + bx], TILE_COIN
        jne  .no_coin
        mov  byte [working_map + bx], TILE_SKY
        call AddCoin
.no_coin:
        pop  bx
        inc  di
        cmp  di, cx
        jbe  .col_loop
        inc  bx
        cmp  bx, dx
        jbe  .row_loop
.out:
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; CollectItems
; Purpose : step 5 of the frame order for items: coin tiles, and mushrooms.
;           A mushroom that overlaps Mario: +1000, and Small becomes Super
;           (if he is already Super, only the points).
; Inputs  : none        Outputs : score, coins, form, mushroom table
; Changes : none (AX, BX, CX preserved)
; ----------------------------------------------------------------------------
CollectItems:
        push ax
        push bx
        push cx
        call CollectCoins
        mov  bx, mushrooms
        mov  cx, MUSH_MAX
.next:
        cmp  word [bx+M_ACTIVE], 0
        je   .skip
        mov  ax, [mario_x]
        add  ax, HB_OFF
        push ax                         ; Mario's hitbox: x
        push word [mario_y]             ;                 y
        push word HB_W                  ;                 w
        call HeroHeight
        push ax                         ;                 h
        push word [bx+M_X]              ; mushroom: x
        push word [bx+M_Y]              ;           y
        push word 16                    ;           w
        push word 16                    ;           h
        call RectOverlap
        test ax, ax
        jz   .skip
        mov  word [bx+M_ACTIVE], 0      ; collected
        push word 1000
        call AddScore
        cmp  byte [form], FORM_SMALL
        jne  .skip                      ; already Super: points only
        call GrowMario
.skip:
        add  bx, MUSH_REC
        loop .next
        pop  cx
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; DrawMushrooms
; Purpose : draw every active mushroom that is on the screen
; Inputs  : none        Outputs : none        Changes : none
; ----------------------------------------------------------------------------
DrawMushrooms:
        push ax
        push bx
        push cx
        mov  bx, mushrooms
        mov  cx, MUSH_MAX
.next:
        cmp  word [bx+M_ACTIVE], 0
        je   .skip
        mov  ax, [bx+M_X]
        sub  ax, [camera_x]             ; screen x
        cmp  ax, -SPRITE_W
        jle  .skip
        cmp  ax, SCREEN_W
        jge  .skip
        push ax
        push word [bx+M_Y]
        push word spr_mushroom
        push word 0
        call DrawSprite
.skip:
        add  bx, MUSH_REC
        loop .next
        pop  cx
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; ClearEntities
; Purpose : remove all mushrooms and coin pop-ups (they are stored together)
; Inputs  : none        Outputs : tables set to 0
; Changes : none (AX, CX, DI, ES preserved)
; ----------------------------------------------------------------------------
ClearEntities:
        push ax
        push cx
        push di
        push es
        push cs
        pop  es                         ; ES = our own segment (not the buffer!)
        xor  ax, ax
        mov  di, entities_start
        mov  cx, (entities_end - entities_start) / 2
        cld
        rep  stosw
        pop  es
        pop  di
        pop  cx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; ResetLevel
; Purpose : level back to its start (used after a death): map restored from
;           the original, mushrooms and pop-ups removed, Mario at the start
;           as Small Mario. Score and coins are KEPT.
; Inputs  : none        Outputs : many        Changes : none
; ----------------------------------------------------------------------------
ResetLevel:
        call ResetMap
        call ClearEntities
        call ResetHero
        ret

; ----------------------------------------------------------------------------
; NewGame
; Purpose : everything from scratch: score 0, coins 0, 3 lives, then the level
; Inputs  : none        Outputs : many        Changes : none
; ----------------------------------------------------------------------------
NewGame:
        mov  word [score_lo], 0
        mov  word [score_hi], 0
        mov  byte [coins], 0
        mov  byte [lives], START_LIVES
        call ResetLevel
        ret

; ----------------------------------------------------------------------------
; RectOverlap(ax, ay, aw, ah, bx, by, bw, bh)   pushed in that order
; Purpose : do rectangle A and rectangle B overlap? (touching edges do not)
; Inputs  : [bp+18]=ax [bp+16]=ay [bp+14]=aw [bp+12]=ah
;           [bp+10]=bx [bp+8]=by  [bp+6]=bw  [bp+4]=bh   (signed words)
; Outputs : AX = 1 overlap, 0 none
; Changes : AX only
; ----------------------------------------------------------------------------
RectOverlap:
        push bp
        mov  bp, sp
        mov  ax, [bp+18]
        add  ax, [bp+14]                ; right edge of A
        cmp  ax, [bp+10]
        jle  .no                        ; A ends before B starts
        mov  ax, [bp+10]
        add  ax, [bp+6]                 ; right edge of B
        cmp  ax, [bp+18]
        jle  .no                        ; B ends before A starts
        mov  ax, [bp+16]
        add  ax, [bp+12]                ; bottom of A
        cmp  ax, [bp+8]
        jle  .no
        mov  ax, [bp+8]
        add  ax, [bp+4]                 ; bottom of B
        cmp  ax, [bp+16]
        jle  .no
        mov  ax, 1
        jmp  .out
.no:
        xor  ax, ax
.out:
        pop  bp
        ret  16

; ----------------------------------------------------------------------------
; ClassifyContact(prev_feet, enemy_y, enemy_h)   pushed in that order
; Purpose : Mario overlaps an enemy: stomp or hurt? (Section 5.6)
;           Stomp = Mario is moving down AND in the previous frame his feet
;           were above the upper half of the enemy.
; Inputs  : [bp+8]=prev_feet  [bp+6]=enemy top y  [bp+4]=enemy height
;           (and mario_vy)
; Outputs : AX = 1 stomp, 0 hurt
; Changes : AX only
; ----------------------------------------------------------------------------
ClassifyContact:
        push bp
        mov  bp, sp
        cmp  word [mario_vy], 0
        jle  .hurt                      ; not moving down: cannot be a stomp
        mov  ax, [bp+4]
        shr  ax, 1                      ; half the enemy height
        add  ax, [bp+6]                 ; AX = y of the enemy's middle
        cmp  [bp+8], ax
        jg   .hurt                      ; feet were already below the middle
        mov  ax, 1
        jmp  .out
.hurt:
        xor  ax, ax
.out:
        pop  bp
        ret  6

; ----------------------------------------------------------------------------
; TileIsFlag(px, py)
; Purpose : is the tile at this world pixel the flag pole?
; Inputs  : [bp+6]=px  [bp+4]=py        Outputs : AX = 1 flag, 0 not
; Changes : AX only
; ----------------------------------------------------------------------------
TileIsFlag:
        push bp
        mov  bp, sp
        push word [bp+6]
        push word [bp+4]
        call GetTile
        cmp  ax, TILE_FLAG
        jne  .no
        mov  ax, 1
        jmp  .out
.no:
        xor  ax, ax
.out:
        pop  bp
        ret  4

; ----------------------------------------------------------------------------
; ProbeFlagColumn(px)
; Purpose : is there flag pole at x = px at Mario's head, middle or feet?
; Inputs  : [bp+4]=px        Outputs : AX = 1 yes, 0 no
; Changes : AX only
; ----------------------------------------------------------------------------
ProbeFlagColumn:
        push bp
        mov  bp, sp
        push bx
        push cx
        call HeroHeight
        dec  ax
        mov  cx, ax                     ; CX = height - 1
        mov  bx, [mario_y]              ; BX = head row
        push word [bp+4]
        push bx
        call TileIsFlag
        test ax, ax
        jnz  .out
        mov  ax, cx
        shr  ax, 1
        add  ax, bx                     ; middle row
        push word [bp+4]
        push ax
        call TileIsFlag
        test ax, ax
        jnz  .out
        add  bx, cx                     ; bottom row
        push word [bp+4]
        push bx
        call TileIsFlag                 ; its result is the answer
.out:
        pop  cx
        pop  bx
        pop  bp
        ret  2

; ----------------------------------------------------------------------------
; ContactWithTarget(ptr)
; Purpose : test Mario against one entry (x, y, w, h) of hit_targets:
;           overlap? then stomp (bounce up, chain + 1) or hurt (test lamp).
;           For 12 frames after a stomp, contact is ignored (like the kick
;           grace time) so the bounce cannot count as a hit.
; Inputs  : [bp+4]=address of the (x, y, w, h) record
; Outputs : stomp_timer / hurt_timer, mario_vy, stomp_chain
; Changes : none (AX, BX preserved)
; ----------------------------------------------------------------------------
ContactWithTarget:
        push bp
        mov  bp, sp
        push ax
        push bx
        mov  bx, [bp+4]
        mov  ax, [mario_x]
        add  ax, HB_OFF
        push ax                         ; hero hitbox: x
        push word [mario_y]             ;               y
        push word HB_W                  ;               w
        call HeroHeight
        push ax                         ;               h
        push word [bx]                  ; target: x
        push word [bx+2]                ;         y
        push word [bx+4]                ;         w
        push word [bx+6]                ;         h
        call RectOverlap
        test ax, ax
        jz   .out
        cmp  byte [stomp_timer], 0
        jne  .out                       ; just bounced: ignore
        push word [prev_feet_y]
        push word [bx+2]
        push word [bx+6]
        call ClassifyContact
        test ax, ax
        jz   .hurt
        mov  word [mario_vy], STOMP_BOUNCE      ; defeated: bounce up
        mov  byte [stomp_timer], 12
        inc  byte [stomp_chain]
        jmp  .out
.hurt:
        mov  byte [hurt_timer], 12      ; (real damage comes in Module 11)
.out:
        pop  bx
        pop  ax
        pop  bp
        ret  2

; ----------------------------------------------------------------------------
; CheckHazards
; Purpose : once per frame after Mario moved:
;           - count down the test-lamp timers
;           - pit: top of Mario at y >= 192 -> respawn (Module 15 will do the
;             real death sequence)
;           - flag pole touched? remember the row of his feet for scoring
;           - contact with the test enemies (stomp or hurt)
; Inputs  : the hero data     Outputs : lamps/timers, flag_touched, flag_row
; Changes : none (AX, BX, CX preserved)
; ----------------------------------------------------------------------------
CheckHazards:
        push ax
        push bx
        push cx
        cmp  byte [head_timer], 0
        je   .t1
        dec  byte [head_timer]
.t1:
        cmp  byte [stomp_timer], 0
        je   .t2
        dec  byte [stomp_timer]
.t2:
        cmp  byte [hurt_timer], 0
        je   .t3
        dec  byte [hurt_timer]
.t3:
        cmp  word [mario_y], PIT_Y      ; SIGNED: fell below the map?
        jl   .no_pit
        call ResetLevel                 ; test: map, mushrooms, Mario back to the start
        jmp  .done
.no_pit:
        cmp  byte [flag_touched], 0
        jne  .contacts                  ; already touched
        mov  ax, [mario_x]
        add  ax, HB_OFF
        push ax
        call ProbeFlagColumn            ; left edge of the hitbox
        test ax, ax
        jnz  .flag_hit
        mov  ax, [mario_x]
        add  ax, HB_OFF + HB_W - 1
        push ax
        call ProbeFlagColumn            ; right edge of the hitbox
        test ax, ax
        jz   .contacts
.flag_hit:
        mov  byte [flag_touched], 1
        call HeroHeight
        add  ax, [mario_y]
        dec  ax                         ; pixel row of his feet
        shr  ax, 4                      ; map row (2..8 gives the points)
        mov  [flag_row], al
.contacts:
        mov  bx, hit_targets
        mov  cx, TARGET_COUNT
.next_target:
        push bx
        call ContactWithTarget
        add  bx, 8                      ; next record (4 words)
        loop .next_target
.done:
        pop  cx
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; UpdateCamera
; Purpose : the camera rule of Section 5.3, once per frame after Mario moved:
;           1 screen_x = mario_x - camera_x
;           2 if screen_x > 160, wanted camera = mario_x - 160
;           3 limit it to 640 (level width - screen width)
;           4 camera never decreases
;           5 left wall: Mario cannot be left of the camera
; Inputs  : mario_x, camera_x    Outputs : camera_x, mario_x (left wall)
; Changes : none (AX, BX preserved)
; ----------------------------------------------------------------------------
UpdateCamera:
        push ax
        push bx
        mov  ax, [mario_x]
        mov  bx, ax
        sub  bx, [camera_x]             ; BX = Mario's screen x
        cmp  bx, CAMERA_FOLLOW          ; signed compare
        jle  .no_follow                 ; at or left of the middle: camera stays
        sub  ax, CAMERA_FOLLOW          ; AX = wanted camera = mario_x - 160
        cmp  ax, CAMERA_MAX
        jbe  .limit_ok
        mov  ax, CAMERA_MAX             ; end of level: stop scrolling
.limit_ok:
        cmp  ax, [camera_x]
        jbe  .no_follow                 ; never scroll back to the left
        mov  [camera_x], ax
.no_follow:
        mov  ax, [camera_x]
        cmp  [mario_x], ax
        jae  .done                      ; Mario is inside the screen
        mov  [mario_x], ax              ; invisible wall on the left
        mov  byte [mario_xf], 0
        mov  word [mario_vx], 0         ; and his horizontal speed becomes 0
.done:
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; DrawMario
; Purpose : draw Mario at screen_x = world_x - camera_x. Pose: jumping sprite
;           in the air, running sprite (alternating every 8 frames) while he
;           moves, standing sprite otherwise. Super Mario uses the 16 x 32
;           sprites (SPR_TALL); mario_y is the TOP of the body, so when he
;           grows his feet stay where they were.
; Inputs  : none        Outputs : none
; Changes : none (AX, BX, CX preserved)
; ----------------------------------------------------------------------------
DrawMario:
        push ax
        push bx
        push cx
        mov  bx, 4                      ; pose offset in the table: 4 = jumping
        cmp  byte [on_ground], 0
        je   .pose_set
        xor  bx, bx                     ; 0 = standing
        cmp  word [mario_vx], 0
        je   .pose_set
        test word [frame_counter], 8
        jz   .pose_set
        mov  bx, 2                      ; 2 = running
.pose_set:
        mov  ax, [mario_flags]          ; AX = flags (mirror when facing left)
        cmp  byte [form], FORM_SUPER
        je   .super
        mov  cx, [small_poses + bx]     ; CX = address of the small sprite
        jmp  .draw
.super:
        or   ax, SPR_TALL               ; 16 x 32
        mov  cx, [super_poses + bx]
.draw:
        mov  bx, [mario_x]
        sub  bx, [camera_x]             ; world x -> screen x
        push bx                         ; x
        push word [mario_y]             ; y (top)
        push cx                         ; sprite address
        push ax                         ; flags
        call DrawSprite
        pop  cx
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; DrawMinimap
; Purpose : (test aid) a strip across the top: the whole level scaled to 1/4
;           (240 px), a gold box = the part the camera shows, a red mark = Mario
; Inputs  : none        Outputs : none
; Changes : none (AX preserved)
; ----------------------------------------------------------------------------
DrawMinimap:
        push ax
        push word 40                    ; the level track
        push word 3
        push word LEVEL_W_PX / 4
        push word 4
        push word COL_OUTLINE
        call FillRect
        mov  ax, [camera_x]
        shr  ax, 2                      ; scale 1/4
        add  ax, 40
        push ax                         ; the camera window (320 / 4 = 80 wide)
        push word 3
        push word SCREEN_W / 4
        push word 4
        push word COL_COIN
        call FillRect
        mov  ax, [mario_x]
        shr  ax, 2
        add  ax, 40
        push ax                         ; Mario's mark
        push word 1
        push word 4
        push word 8
        push word COL_HERO
        call FillRect
        pop  ax
        ret

; ----------------------------------------------------------------------------
; DrawLamp(y, colour, lit)          pushed in that order
; Purpose : (test aid) a 12 x 12 lamp at x = 8: coloured when lit, dark if not
; Inputs  : [bp+8]=y  [bp+6]=colour when lit  [bp+4]=lit (0 = dark)
; Outputs : none        Changes : none (AX preserved)
; ----------------------------------------------------------------------------
DrawLamp:
        push bp
        mov  bp, sp
        push ax
        mov  ax, COL_OUTLINE
        cmp  word [bp+4], 0
        je   .dark
        mov  ax, [bp+6]
.dark:
        push word 8
        push word [bp+8]
        push word 12
        push word 12
        push ax
        call FillRect
        pop  ax
        pop  bp
        ret  6

; ----------------------------------------------------------------------------
; DrawPhysicsBars
; Purpose : (test aid) five lamps down the left side, and a speed bar:
;           1 on ground   2 head hit   3 stomp   4 hurt   5 flag touched
;           bar length = |vx| / 8 pixels
; Inputs  : none        Outputs : none
; Changes : none (AX preserved)
; ----------------------------------------------------------------------------
DrawPhysicsBars:
        push ax
        push word 2                     ; lamp 1: on the ground
        push word COL_GROUND_TOP
        xor  ax, ax
        mov  al, [on_ground]
        push ax
        call DrawLamp
        push word 16                    ; lamp 2: head hit a block
        push word COL_COIN
        xor  ax, ax
        mov  al, [head_timer]
        push ax
        call DrawLamp
        push word 30                    ; lamp 3: stomped an enemy
        push word COL_PIPE_LIGHT
        xor  ax, ax
        mov  al, [stomp_timer]
        push ax
        call DrawLamp
        push word 44                    ; lamp 4: hurt by an enemy
        push word COL_HERO
        xor  ax, ax
        mov  al, [hurt_timer]
        push ax
        call DrawLamp
        push word 58                    ; lamp 5: flag pole touched
        push word COL_TEXT
        xor  ax, ax
        mov  al, [flag_touched]
        push ax
        call DrawLamp
        mov  ax, [mario_vx]
        test ax, ax
        jns  .positive
        neg  ax                         ; |vx|
.positive:
        shr  ax, 3                      ; 2.5 px/frame (0280h) -> 80 pixels
        push word 40
        push word 11
        push ax
        push word 4
        push word COL_COIN
        call FillRect                   ; width 0 draws nothing
        pop  ax
        ret

; ----------------------------------------------------------------------------
; DrawStatusBars
; Purpose : (test aid until the HUD exists in Module 13)
;           top bar    score / 50 pixels (max 240)
;           2nd bar    coins, 1 pixel each
;           3rd bar    lives, 4 pixels each
;           lamp 6     lit while Mario is Super
; Inputs  : none        Outputs : none
; Changes : none (AX, CX, DX preserved)
; ----------------------------------------------------------------------------
DrawStatusBars:
        push ax
        push cx
        push dx
        mov  dx, [score_hi]
        mov  ax, [score_lo]
        mov  cx, 50
        div  cx                         ; AX = score / 50 (always fits: <= 19999)
        cmp  ax, 240
        jbe  .score_ok
        mov  ax, 240
.score_ok:
        push word 40
        push word 17
        push ax
        push word 4
        push word COL_COIN
        call FillRect
        xor  ax, ax
        mov  al, [coins]
        push word 40
        push word 23
        push ax
        push word 4
        push word COL_TEXT
        call FillRect
        xor  ax, ax
        mov  al, [lives]
        shl  ax, 2
        cmp  ax, 240
        jbe  .lives_ok
        mov  ax, 240
.lives_ok:
        push word 40
        push word 29
        push ax
        push word 4
        push word COL_HERO
        call FillRect
        push word 72                    ; lamp 6: Super Mario
        push word COL_PIPE
        xor  ax, ax
        mov  al, [form]
        push ax
        call DrawLamp
        pop  dx
        pop  cx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; ClearBuffer
; Purpose : fill the whole frame buffer with colour 0 using one block store
; Inputs  : none        Outputs : none
; Changes : none (AX, CX, DI, ES preserved)
; ----------------------------------------------------------------------------
ClearBuffer:
        push ax
        push cx
        push di
        push es
        mov  es, [draw_seg]             ; ES:DI = start of the buffer
        xor  di, di
        xor  ax, ax                     ; colour 0 in both bytes of the word
        mov  cx, BUFFER_WORDS           ; 32,000 words = 64,000 bytes
        cld
        rep  stosw
        pop  es
        pop  di
        pop  cx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; CopyBuffer
; Purpose : copy the finished frame buffer to video memory with one block move
; Inputs  : none        Outputs : none
; Changes : none (AX, CX, SI, DI, DS, ES preserved)
; Note    : DS points at the buffer during the copy, so no variable may be
;           read between "mov ds" and "rep movsw".
; ----------------------------------------------------------------------------
CopyBuffer:
        push ax
        push cx
        push si
        push di
        push ds
        push es
        mov  ax, VIDEO_SEG
        mov  es, ax                     ; destination = screen
        mov  ax, [buffer_seg]           ; read the variable BEFORE changing DS
        mov  ds, ax                     ; source = frame buffer
        xor  si, si
        xor  di, di
        mov  cx, BUFFER_WORDS
        cld
        rep  movsw
        pop  es
        pop  ds                         ; our variables are reachable again
        pop  di
        pop  si
        pop  cx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; DecodeSprites
; Purpose : turn the sprite text characters into palette numbers, in place.
;           '.' -> 0, '0'-'9' -> 0-9, 'a'-'h' -> 10-17
; Inputs  : none
; Outputs : none (sprites_start..sprites_end now hold numbers)
; Changes : none (AX, CX, SI preserved). Runs only once (sprites_ready flag).
; ----------------------------------------------------------------------------
DecodeSprites:
        push ax
        push cx
        push si
        cmp  byte [sprites_ready], 0
        jne  .done                      ; already decoded: do nothing
        mov  si, sprites_start
        mov  cx, SPRITE_BYTES
.next:
        mov  al, [si]                   ; AL = one text character
        cmp  al, '.'
        je   .transparent
        cmp  al, 'a'
        jb   .digit                     ; below 'a' -> it is '0'..'9'
        sub  al, 'a' - 10               ; 'a' -> 10, 'b' -> 11 ...
        jmp  .store
.digit:
        sub  al, '0'                    ; '5' -> 5
        jmp  .store
.transparent:
        xor  al, al                     ; '.' -> 0
.store:
        mov  [si], al                   ; overwrite the text with the number
        inc  si
        loop .next
        mov  byte [sprites_ready], 1
.done:
        pop  si
        pop  cx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; DrawSprite(x, y, address, flags)  pushed in that order
; Purpose : draw a 16-wide sprite at (x,y); colour 0 is transparent.
;           flags: SPR_MIRROR flip, SPR_BLINK even frames only, SPR_TALL 32 rows
;           Clips on all four screen edges (off-screen pixels are skipped).
; Inputs  : [bp+10]=x  [bp+8]=y  [bp+6]=sprite address  [bp+4]=flags
; Outputs : none
; Locals  : [bp-2]=current screen y  [bp-4]=rows left  [bp-6]=mirror (0/1)
; Changes : none (all registers preserved)
; ----------------------------------------------------------------------------
DrawSprite:
        push bp
        mov  bp, sp
        sub  sp, 6                      ; room for 3 local words
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push es

        mov  ax, [bp+4]                 ; AX = flags
        test ax, SPR_BLINK
        jz   .blink_ok
        test word [frame_counter], 1
        jnz  .exit                      ; odd frame: draw nothing
.blink_ok:
        mov  word [bp-6], 0             ; mirror = 0
        test ax, SPR_MIRROR
        jz   .mirror_set
        mov  word [bp-6], 1
.mirror_set:
        mov  word [bp-4], SPRITE_H      ; rows = 16
        test ax, SPR_TALL
        jz   .height_set
        mov  word [bp-4], SPRITE_H * 2  ; rows = 32
.height_set:
        mov  ax, [bp+8]
        mov  [bp-2], ax                 ; current screen y = y
        mov  si, [bp+6]                 ; SI = first pixel of the sprite
        mov  es, [draw_seg]             ; ES = where we draw

.row_loop:
        mov  ax, [bp-2]                 ; AX = screen y of this row
        cmp  ax, SCREEN_H               ; unsigned: also catches negatives
        jae  .next_row                  ; row off-screen: skip whole row
        mov  di, ax
        mov  bx, ax
        shl  di, 8                      ; y * 256
        shl  bx, 6                      ; y * 64
        add  di, bx                     ; DI = y * 320 = start of screen line
        xor  cx, cx                     ; CX = column 0..15
.pixel_loop:
        mov  dx, [bp+10]
        add  dx, cx                     ; DX = screen x of this pixel
        cmp  dx, SCREEN_W               ; unsigned: catches left and right
        jae  .next_pixel                ; off-screen: skip this pixel only
        mov  bx, cx                     ; BX = column to read
        cmp  word [bp-6], 0
        je   .read
        mov  bx, SPRITE_W - 1
        sub  bx, cx                     ; mirrored: read from the right end
.read:
        mov  al, [si + bx]              ; AL = sprite pixel colour
        test al, al
        jz   .next_pixel                ; 0 = transparent: do not draw
        mov  bx, di
        add  bx, dx                     ; BX = line start + x
        mov  [es:bx], al                ; plot the pixel
.next_pixel:
        inc  cx
        cmp  cx, SPRITE_W
        jb   .pixel_loop
.next_row:
        add  si, SPRITE_W               ; ALWAYS move to the next sprite row
        inc  word [bp-2]                ; next screen line
        dec  word [bp-4]
        jnz  .row_loop
.exit:
        pop  es
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        mov  sp, bp                     ; drop the locals
        pop  bp
        ret  8

; ----------------------------------------------------------------------------
; DrawWorldItems
; Purpose : draw every object of world_items that is on the screen:
;           screen_x = world_x - camera_x, drawn only if -16 < screen_x < 320
; Inputs  : none        Outputs : none
; Changes : none (AX, BX, CX preserved)
; ----------------------------------------------------------------------------
DrawWorldItems:
        push ax
        push bx
        push cx
        mov  bx, world_items            ; BX walks the table
        mov  cx, ITEM_COUNT
.next:
        mov  ax, [bx]                   ; world x
        sub  ax, [camera_x]             ; AX = screen x (may be negative)
        cmp  ax, -SPRITE_W
        jle  .skip                      ; completely off the left side
        cmp  ax, SCREEN_W
        jge  .skip                      ; completely off the right side
        push ax                         ; x on screen
        push word [bx+2]                ; y
        push word [bx+4]                ; sprite address
        push word [bx+6]                ; flags
        call DrawSprite
.skip:
        add  bx, 8                      ; next object (4 words)
        loop .next
        pop  cx
        pop  bx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; SetPalette
; Purpose : copy the palette table into the VGA DAC
; Inputs  : none
; Outputs : none
; Changes : none (all registers preserved)
; ----------------------------------------------------------------------------
SetPalette:
        push ax
        push cx
        push dx
        push si
        cld                             ; SI moves forward
        mov  si, palette                ; source = palette table
        mov  dx, 3C8h                   ; DAC index port
        xor  al, al                     ; start at colour 0
        out  dx, al
        inc  dx                         ; DX = 3C9h, DAC data port
        mov  cx, PAL_COUNT * 3          ; 3 bytes (R,G,B) per colour
        rep  outsb                      ; send [DS:SI] to port DX, CX times
        pop  si
        pop  dx
        pop  cx
        pop  ax
        ret

; ----------------------------------------------------------------------------
; FillRect(x, y, w, h, colour)      pushed in that order
; Purpose : fill a rectangle of pixels in the draw segment. CLIPS on all four
;           screen edges, so x may be negative (scrolled tiles) or past 320.
; Inputs  : [bp+12]=x  [bp+10]=y  [bp+8]=w  [bp+6]=h  [bp+4]=colour  (signed)
; Outputs : none
; Changes : none (all registers preserved)
; ----------------------------------------------------------------------------
FillRect:
        push bp
        mov  bp, sp
        push ax
        push bx
        push cx
        push dx
        push di
        push es
        mov  es, [draw_seg]             ; ES = where we draw (screen or buffer)
        mov  ax, [bp+12]                ; AX = x
        mov  cx, [bp+8]                 ; CX = width
        test ax, ax
        jns  .left_ok
        add  cx, ax                     ; x < 0: cut the part left of the screen
        xor  ax, ax                     ; start at x = 0
.left_ok:
        mov  bx, ax
        add  bx, cx                     ; BX = right edge
        cmp  bx, SCREEN_W
        jle  .right_ok
        mov  cx, SCREEN_W
        sub  cx, ax                     ; cut the part right of the screen
.right_ok:
        cmp  cx, 0                      ; SIGNED: nothing left to draw?
        jle  .done
        mov  bx, [bp+10]                ; BX = y
        mov  dx, [bp+6]                 ; DX = height
        test bx, bx
        jns  .top_ok
        add  dx, bx                     ; y < 0: cut the part above the screen
        xor  bx, bx
.top_ok:
        mov  di, bx
        add  di, dx                     ; DI = bottom edge
        cmp  di, SCREEN_H
        jle  .bottom_ok
        mov  dx, SCREEN_H
        sub  dx, bx                     ; cut the part below the screen
.bottom_ok:
        cmp  dx, 0
        jle  .done
        mov  di, bx
        shl  di, 8                      ; y * 256
        shl  bx, 6                      ; y * 64
        add  di, bx                     ; y * 320
        add  di, ax                     ; + x  -> DI = pixel offset
        mov  al, [bp+4]                 ; AL = colour number
        cld
.line:
        push cx                         ; rep stosb uses CX up
        push di                         ; remember start of this line
        rep  stosb                      ; write CX pixels
        pop  di
        pop  cx
        add  di, SCREEN_W               ; move down one pixel line
        dec  dx
        jnz  .line
.done:
        pop  es
        pop  di
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        pop  bp
        ret  10

; ----------------------------------------------------------------------------
; DrawTile(x, y, code)              pushed in that order
; Purpose : paint one 16 x 16 tile using the colour of its tile code
; Inputs  : [bp+8]=screen x  [bp+6]=screen y  [bp+4]=tile code
; Outputs : none
; Changes : none (all registers preserved)
; ----------------------------------------------------------------------------
DrawTile:
        push bp
        mov  bp, sp
        push ax
        push si
        mov  si, [bp+4]                 ; SI = tile code
        cmp  si, TILE_COUNT
        jb   .known
        xor  si, si                     ; unknown code -> draw as sky
.known:
        mov  al, [tile_colour + si]     ; table lookup: code -> colour
        xor  ah, ah
        push word [bp+8]                ; x
        push word [bp+6]                ; y
        push word TILE_SIZE             ; w
        push word TILE_SIZE             ; h
        push ax                         ; colour
        call FillRect
        pop  si
        pop  ax
        pop  bp
        ret  6

; ----------------------------------------------------------------------------
; GetTile(px, py)                   pushed in that order
; Purpose : pixel position -> tile code from working_map
; Inputs  : [bp+6]=px  [bp+4]=py  (world pixels)
; Outputs : AX = tile code
; Changes : AX only
; Rule    : column outside 0..59 -> TILE_GROUND (invisible wall)
;           row outside 0..11    -> TILE_SKY    (Mario may fall into pits)
; ----------------------------------------------------------------------------
GetTile:
        push bp
        mov  bp, sp
        push bx
        push cx
        push dx
        push si
        mov  ax, [bp+6]                 ; AX = px
        mov  bx, [bp+4]                 ; BX = py
        shr  ax, 4                      ; AX = column
        shr  bx, 4                      ; BX = row
        cmp  ax, MAP_W                  ; unsigned: also catches negatives
        jae  .solid
        cmp  bx, MAP_H
        jae  .sky
        mov  si, ax                     ; SI = column
        mov  ax, bx                     ; AX = row
        mov  cx, MAP_W
        mul  cx                         ; DX:AX = row * 60 (DX saved above)
        add  si, ax                     ; SI = row*60 + column
        mov  al, [working_map + si]     ; read the tile code
        xor  ah, ah
        jmp  .done
.solid:
        mov  ax, TILE_GROUND
        jmp  .done
.sky:
        mov  ax, TILE_SKY
.done:
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  bp
        ret  4

; ----------------------------------------------------------------------------
; DrawMap
; Purpose : draw the visible part of the level, shifted by the camera.
;           first column = camera_x / 16, pixel offset = camera_x mod 16,
;           21 columns (20 + one partial), tile x = i*16 - offset.
; Inputs  : camera_x (reads working_map)    Outputs : none
; Locals  : [bp-2] = first map column
; Changes : none (DrawTile preserves registers, so counters survive calls)
; ----------------------------------------------------------------------------
DrawMap:
        push bp
        mov  bp, sp
        sub  sp, 2
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov  ax, [camera_x]
        mov  di, ax
        and  di, 15                     ; DI = camera_x mod 16 (pixel offset)
        shr  ax, 4
        mov  [bp-2], ax                 ; first column = camera_x / 16
        xor  dx, dx                     ; DX = row
.row_loop:
        mov  ax, dx
        mov  bx, ax
        shl  ax, 6                      ; row * 64
        shl  bx, 2                      ; row * 4
        sub  ax, bx                     ; row * 60
        add  ax, [bp-2]                 ; + first column
        mov  si, ax                     ; SI = map index of the leftmost tile
        xor  cx, cx                     ; CX = column on screen, reloaded per row
.col_loop:
        mov  ax, [bp-2]
        add  ax, cx                     ; AX = map column
        cmp  ax, MAP_W
        jae  .next_col                  ; past the end of the level: skip
        mov  al, [working_map + si]     ; AL = tile code
        xor  ah, ah
        mov  bx, cx
        shl  bx, 4                      ; i * 16
        sub  bx, di                     ; - offset  (negative for column 0)
        push bx                         ; x
        mov  bx, dx
        shl  bx, 4
        push bx                         ; y = row * 16
        push ax                         ; tile code
        call DrawTile
        cmp  ax, TILE_COIN              ; AX still holds the tile code
        jne  .next_col
        mov  bx, cx
        shl  bx, 4
        sub  bx, di
        push bx                         ; x
        mov  bx, dx
        shl  bx, 4
        push bx                         ; y
        push word spr_coin
        push word 0
        call DrawSprite                 ; the coin picture on the sky tile
.next_col:
        inc  si
        inc  cx
        cmp  cx, SCREEN_COLS + 1
        jb   .col_loop
        inc  dx
        cmp  dx, MAP_H
        jb   .row_loop
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        mov  sp, bp                     ; drop the local
        pop  bp
        ret

; ----------------------------------------------------------------------------
; ResetMap
; Purpose : copy original_map over working_map with one block move
; Inputs  : none
; Outputs : none
; Changes : none (DS, ES, SI, DI, CX, AX restored)
; ----------------------------------------------------------------------------
ResetMap:
        push ax
        push cx
        push si
        push di
        push ds
        push es
        push cs
        pop  ds                         ; DS = code/data segment
        push cs
        pop  es                         ; ES = same (not video!)
        cld
        mov  si, original_map           ; source
        mov  di, working_map            ; destination
        mov  cx, MAP_SIZE               ; 720 bytes
        rep  movsb
        pop  es
        pop  ds
        pop  di
        pop  si
        pop  cx
        pop  ax
        ret
; ----------------------------------------------------------------------------
; ResetHero
; Purpose : Mario at the start as Small Mario with no speed, standing,
;           camera at 0, test flags cleared
; Inputs  : none        Outputs : the hero data and camera_x
; Changes : none
; ----------------------------------------------------------------------------
ResetHero:
        mov  word [camera_x], 0
        mov  word [mario_x], MARIO_START_X
        mov  byte [mario_xf], 0
        mov  word [mario_y], MARIO_START_Y
        mov  byte [mario_yf], 0
        mov  word [mario_vx], 0
        mov  word [mario_vy], 0
        mov  byte [on_ground], 1
        mov  byte [form], FORM_SMALL    ; after a death he is always Small
        mov  byte [hp], 1
        mov  word [invuln_timer], 0
        mov  byte [stomp_chain], 0
        mov  word [mario_flags], 0
        mov  byte [space_was_down], 0
        mov  byte [head_timer], 0
        mov  byte [stomp_timer], 0
        mov  byte [hurt_timer], 0
        mov  byte [flag_touched], 0
        mov  byte [flag_row], 0
        ret