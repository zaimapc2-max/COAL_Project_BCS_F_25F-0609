; ============================================================================
;  MARIO.ASM  -  Super Mario Engine, DAY 2 reference build
;  Modules covered: 2 (video mode, palette, FillRect) and 3 (map, tiles)
;  Build:  nasm -f bin mario.asm -o MARIO.COM
;  Run  :  inside DOSBox, type MARIO
;  Test :  1st key = draw level, 2nd key = brick (col 8,row 6) turned to sky,
;          3rd key = ResetMap restores it, 4th key = exit to DOS.
; ============================================================================
        cpu 186                         ; allows OUTSB and PUSH imm
        bits 16
        org 100h

        jmp  main                       ; data goes after this jump

; ---------------- constants ----------------
VIDEO_SEG       equ 0A000h              ; VGA Mode 13h video segment
SCREEN_W        equ 320                 ; pixels per screen row
TILE_SIZE       equ 16                  ; tile is 16 x 16 pixels
SCREEN_COLS     equ 20                  ; tile columns visible on screen
MAP_W           equ 60                  ; level width in tiles
MAP_H           equ 12                  ; level height in tiles
MAP_SIZE        equ MAP_W * MAP_H       ; 720 bytes

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

COL_SKY         equ 1
COL_GROUND      equ 2
COL_BRICK       equ 3
COL_PIPE        equ 4
COL_HERO        equ 5
COL_ENEMY       equ 6
COL_TEXT        equ 7
COL_HUD         equ 8
COL_OUTLINE     equ 9
COL_PIPE_LIGHT  equ 10
COL_COIN        equ 11
COL_GROUND_TOP  equ 12
PAL_COUNT       equ 13

; ---------------- data ----------------
; palette: R,G,B per entry, each 0-63 (6-bit DAC)
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

; colour used for each tile code (index = tile code). Placeholder solid colours;
; real 16x16 bitmaps replace this on Day 3.
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

; results of the GetTile self-test (look at them in the DOSBox debugger)
test_brick      dw 0            ; expect 4  (? mushroom block at col 8,row 6)
test_pipe       dw 0            ; expect 6  (pipe top-left at col 14,row 8)
test_pit        dw 0            ; expect 0  (pit at col 22,row 10)
test_outside    dw 0            ; expect 1  (left of the level -> solid)

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


; working copy the game reads and changes. Filled by ResetMap at startup.
working_map:
        times MAP_SIZE db 0

; ============================================================================
;  CODE
; ============================================================================
main:
        mov  ax, 0013h                  ; BIOS: set VGA Mode 13h
        int  10h
        call SetPalette                 ; must come AFTER the mode switch
        call ResetMap                   ; working_map = original_map
        call DrawMap

        ; ---- GetTile self-test (pixel positions -> tile codes) ----
        push word 8*16                  ; px, pushed first
        push word 6*16                  ; py, pushed last
        call GetTile
        mov  [test_brick], ax
        push word 14*16
        push word 8*16
        call GetTile
        mov  [test_pipe], ax
        push word 22*16
        push word 10*16
        call GetTile
        mov  [test_pit], ax
        push word 0FFFFh                ; -1 = left of the level
        push word 0
        call GetTile
        mov  [test_outside], ax

        xor  ah, ah                     ; wait for a key
        int  16h

        mov  byte [working_map + 6*MAP_W + 8], TILE_SKY   ; remove the ? block
        call DrawMap
        xor  ah, ah
        int  16h

        call ResetMap                   ; original copied back
        call DrawMap
        xor  ah, ah
        int  16h

        mov  ax, 0003h                  ; back to text mode (resets palette)
        int  10h
        mov  ax, 4C00h                  ; DOS exit
        int  21h

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
        mov  ax, VIDEO_SEG
        mov  es, ax                     ; ES = video memory
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