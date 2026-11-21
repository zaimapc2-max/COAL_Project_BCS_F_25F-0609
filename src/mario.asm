; ============================================================================
;  MARIO.ASM  -  Super Mario Engine, DAY 3 reference build
;  Modules covered: 2 (video, palette, FillRect), 3 (map, tiles),
;                   4 (sprites: decode, DrawSprite, mirror, clip, blink)
;  Build:  nasm -f bin mario.asm -o MARIO.COM
;  Test :  any key = redraw (blink sprite toggles), Esc = exit to DOS
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
        mov  ax, 0013h                  ; BIOS: set VGA Mode 13h
        int  10h
        call SetPalette                 ; must come AFTER the mode switch
        call DecodeSprites              ; sprite text -> palette numbers
        call ResetMap                   ; working_map = original_map
.frame:
        call DrawMap                    ; background first
        call DrawScene                  ; sprites on top
        xor  ah, ah                     ; wait for a key
        int  16h
        cmp  al, 1Bh                    ; Esc?
        je   .quit
        inc  word [frame_counter]       ; next frame (toggles the blink sprite)
        jmp  .frame
.quit:
        mov  ax, 0003h                  ; back to text mode (resets palette)
        int  10h
        mov  ax, 4C00h                  ; DOS exit
        int  21h

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