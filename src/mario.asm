; ============================================================================
;  MARIO.ASM  -  Super Mario Engine, DAY 5 reference build
;  Modules covered: 2 (video, palette, FillRect), 3 (map, tiles),
;                   4 (sprites), 5 (frame buffer),
;  
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
sprite_x        dw -16          ; x of the walking test sprite (signed)
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
walker_flags    dw 0            ; SPR_MIRROR when facing left
lamp_keys       db SC_RIGHT, SC_LSHIFT, SC_SPACE   ; keys shown by the lamps
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
        db COL_COIN             ; 11 coin
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

; ---------------- test scene: x, y, sprite, flags ----------------
scene_table:
        dw  16,  20, spr_small_stand, 0
        dw  40,  20, spr_small_run,   0
        dw  64,  20, spr_small_jump,  0
        dw  88,  20, spr_small_run,   SPR_MIRROR
        dw 128,  20, spr_goomba,      0
        dw 152,  20, spr_goomba_flat, 0
        dw 176,  20, spr_koopa,       0
        dw 200,  20, spr_shell,       0
        dw 224,  20, spr_mushroom,    0
        dw 248,  20, spr_coin,        0
        dw 280,  20, spr_small_stand, SPR_BLINK
        dw  16,  70, spr_super_stand, SPR_TALL
        dw  48,  70, spr_super_run,   SPR_TALL
        dw  80,  70, spr_super_jump,  SPR_TALL
        dw 112,  70, spr_super_run,   SPR_TALL + SPR_MIRROR
        dw  -8, 130, spr_small_stand, 0         ; clipped on the left
        dw 312, 130, spr_small_stand, 0         ; clipped on the right
        dw 150,  -8, spr_small_stand, 0         ; clipped on the top
        dw 200, 192, spr_small_stand, 0         ; clipped on the bottom
        dw 250, 176, spr_super_stand, SPR_TALL  ; tall, clipped bottom
scene_end:
SCENE_COUNT     equ (scene_end - scene_table) / 8   ; 4 words = 8 bytes per row


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

.frame:
        call WaitTick                   ; 1. wait for the next timer tick
        call UpdateClock                ; 6. count real seconds
        call UpdateWalker               ; 2-3. read the key table, move
        call ClearBuffer                ; 9. wipe last frame
        call DrawMap
        call DrawScene
        call DrawWalker
        call DrawTestWidgets            ;    key lamps + seconds bar
        call CopyBuffer                 ; 10. ONE copy to the screen per frame
        inc  word [frame_counter]
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
; UpdateWalker
; Purpose : move the test sprite from the key table:
;           Left/Right move it, Left Shift doubles the speed, and the sprite
;           faces the last direction pressed. Clamped to the screen.
; Inputs  : none (reads key_table)    Outputs : sprite_x, walker_flags
; Changes : none (AX preserved)
; ----------------------------------------------------------------------------
UpdateWalker:
        push ax
        mov  ax, 2                      ; walk speed (pixels per frame)
        cmp  byte [key_table + SC_LSHIFT], 0
        je   .speed_set
        mov  ax, 4                      ; run speed
.speed_set:
        cmp  byte [key_table + SC_RIGHT], 0
        je   .not_right
        add  [sprite_x], ax
        mov  word [walker_flags], 0     ; face right
.not_right:
        cmp  byte [key_table + SC_LEFT], 0
        je   .not_left
        sub  [sprite_x], ax
        mov  word [walker_flags], SPR_MIRROR   ; face left
.not_left:
        cmp  word [sprite_x], 0         ; signed clamp: stay on the screen
        jge  .left_ok
        mov  word [sprite_x], 0
.left_ok:
        cmp  word [sprite_x], SCREEN_W - SPRITE_W
        jle  .right_ok
        mov  word [sprite_x], SCREEN_W - SPRITE_W
.right_ok:
        pop  ax
        ret

; ----------------------------------------------------------------------------
; DrawWalker
; Purpose : draw the test sprite; running pose (alternating every 8 frames)
;           while a direction key is held, standing pose otherwise
; Inputs  : none        Outputs : none
; Changes : none (AX preserved)
; ----------------------------------------------------------------------------
DrawWalker:
        push ax
        mov  ax, spr_small_stand        ; default: standing
        cmp  byte [key_table + SC_LEFT], 0
        jne  .moving
        cmp  byte [key_table + SC_RIGHT], 0
        je   .pose_set
.moving:
        test word [frame_counter], 8
        jz   .pose_set
        mov  ax, spr_small_run          ; swap pose every 8 frames
.pose_set:
        push word [sprite_x]            ; x
        push word 44                    ; y (a free lane between the rows)
        push ax                         ; sprite address
        push word [walker_flags]        ; mirror when facing left
        call DrawSprite
        pop  ax
        ret

; ----------------------------------------------------------------------------
; DrawTestWidgets
; Purpose : (test aid) three lamps for Right / Left Shift / Space, lit while
;           held, and a bar that grows by one block per real second (max 30)
; Inputs  : none        Outputs : none
; Changes : none (AX, BX, CX, SI preserved)
; ----------------------------------------------------------------------------
DrawTestWidgets:
        push ax
        push bx
        push cx
        push si
        xor  bx, bx                     ; BX = lamp number 0..2
.lamp:
        mov  al, [lamp_keys + bx]       ; scan code this lamp watches
        xor  ah, ah
        mov  si, ax
        mov  ax, COL_OUTLINE            ; dark = not held
        cmp  byte [key_table + si], 0
        je   .draw_lamp
        mov  ax, COL_COIN               ; gold = held
.draw_lamp:
        mov  cx, bx
        shl  cx, 4                      ; lamp number * 16
        add  cx, 8                      ; x = 8, 24, 40
        push cx
        push word 2                     ; y
        push word 12                    ; w
        push word 12                    ; h
        push ax                         ; colour
        call FillRect
        inc  bx
        cmp  bx, 3
        jb   .lamp

        mov  cx, [game_seconds]         ; seconds bar
        cmp  cx, 30
        jbe  .bar_size_ok
        mov  cx, 30                     ; cap at 30 blocks
.bar_size_ok:
        test cx, cx
        jz   .done
        mov  bx, 64                     ; x of the first block
.bar:
        push bx
        push word 2
        push word 6
        push word 12
        push word COL_GROUND_TOP
        call FillRect
        add  bx, 8
        loop .bar                       ; FillRect keeps CX safe
.done:
        pop  si
        pop  cx
        pop  bx
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
; DrawScene
; Purpose : draw every sprite listed in scene_table (x, y, address, flags)
; Inputs  : none
; Outputs : none
; Changes : none (AX, BX, CX preserved; DrawSprite keeps CX safe)
; ----------------------------------------------------------------------------
DrawScene:
        push bx
        push cx
        mov  bx, scene_table            ; BX walks the table
        mov  cx, SCENE_COUNT            ; how many rows
.next:
        push word [bx]                  ; x
        push word [bx+2]                ; y
        push word [bx+4]                ; sprite address
        push word [bx+6]                ; flags
        call DrawSprite
        add  bx, 8                      ; next row (4 words)
        loop .next
        pop  cx
        pop  bx
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
; Purpose : fill a rectangle of pixels in video memory (no clipping yet)
; Inputs  : [bp+12]=x  [bp+10]=y  [bp+8]=w  [bp+6]=h  [bp+4]=colour
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
        mov  bx, [bp+10]                ; BX = y
        mov  di, bx
        shl  di, 8                      ; y * 256
        shl  bx, 6                      ; y * 64
        add  di, bx                     ; y * 320
        add  di, [bp+12]                ; + x  -> DI = pixel offset
        mov  al, [bp+4]                 ; AL = colour number
        mov  dx, [bp+6]                 ; DX = lines left
        test dx, dx
        jz   .done                      ; height 0: nothing to draw
        cld
.line:
        mov  cx, [bp+8]                 ; CX = width
        push di                         ; remember start of this line
        rep  stosb                      ; write CX pixels
        pop  di
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
; Purpose : draw the 20 x 12 visible tiles (window starts at column 0 today)
; Inputs  : none (reads working_map)
; Outputs : none
; Changes : none (DrawTile preserves registers, so counters survive calls)
; ----------------------------------------------------------------------------
DrawMap:
        push ax
        push bx
        push cx
        push dx
        push si
        xor  dx, dx                     ; DX = row
.row_loop:
        xor  cx, cx                     ; CX = column, reloaded every row
.col_loop:
        mov  ax, dx                     ; AX = row
        mov  bx, MAP_W
        push dx                         ; MUL destroys DX, so save the row
        mul  bx                         ; AX = row * 60
        pop  dx
        add  ax, cx                     ; + column
        mov  si, ax
        mov  al, [working_map + si]     ; AL = tile code
        xor  ah, ah
        mov  bx, cx
        shl  bx, 4                      ; x = column * 16
        push bx
        mov  bx, dx
        shl  bx, 4                      ; y = row * 16
        push bx
        push ax                         ; tile code
        call DrawTile
        inc  cx
        cmp  cx, SCREEN_COLS
        jb   .col_loop
        inc  dx
        cmp  dx, MAP_H
        jb   .row_loop
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
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