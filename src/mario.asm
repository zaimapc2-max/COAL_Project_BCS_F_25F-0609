; ==========================================================
; mario.asm - Day 1: Mode 13h, custom palette, PutPixel,
;             FillRect, colour test screen
; Build: nasm -f bin mario.asm -o mario.com
; ==========================================================
org 100h
        jmp start

; ---------------- constants ----------------
SCREEN_W        equ 320
SCREEN_H        equ 200
VIDEO_SEG       equ 0A000h

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
PAL_COUNT       equ 13          ; number of palette entries

; ---------------- data ----------------
; palette table: R, G, B per entry, each 0-63 (6-bit DAC)
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

; ---------------- main ----------------
start:
        mov ax, 0013h           ; set video mode 13h
        int 10h

        push palette            ; address of colour table
        push PAL_COUNT          ; number of colours
        call SetPalette         ; must come AFTER the mode switch

        ; --- border: four thin rectangles, 2 pixels thick ---
        push 0                  ; top edge
        push 0
        push 320
        push 2
        push COL_OUTLINE
        call FillRect

        push 0                  ; bottom edge
        push 198
        push 320
        push 2
        push COL_OUTLINE
        call FillRect

        push 0                  ; left edge
        push 0
        push 2
        push 200
        push COL_OUTLINE
        call FillRect

        push 318                ; right edge
        push 0
        push 2
        push 200
        push COL_OUTLINE
        call FillRect

        ; --- PutPixel test: four corners + centre ---
        push 0                  ; x
        push 0                  ; y
        push COL_TEXT           ; colour
        call PutPixel           ; top-left

        push 319
        push 0
        push COL_TEXT
        call PutPixel           ; top-right

        push 0
        push 199
        push COL_TEXT
        call PutPixel           ; bottom-left

        push 319
        push 199
        push COL_TEXT
        call PutPixel           ; bottom-right

        push 160
        push 100
        push COL_TEXT
        call PutPixel           ; centre

        ; --- colour test: 8 boxes, each 32 wide and 40 high ---
        push 8                  ; x
        push 80                 ; y
        push 32                 ; width
        push 40                 ; height
        push COL_SKY            ; colour
        call FillRect

        push 48
        push 80
        push 32
        push 40
        push COL_GROUND
        call FillRect

        push 88
        push 80
        push 32
        push 40
        push COL_BRICK
        call FillRect

        push 128
        push 80
        push 32
        push 40
        push COL_PIPE
        call FillRect

        push 168
        push 80
        push 32
        push 40
        push COL_HERO
        call FillRect

        push 208
        push 80
        push 32
        push 40
        push COL_ENEMY
        call FillRect

        push 248
        push 80
        push 32
        push 40
        push COL_TEXT
        call FillRect

        push 288
        push 80
        push 24
        push 40
        push COL_HUD
        call FillRect

        ; --- second row: the spare colours ---
        push 8
        push 130
        push 32
        push 30
        push COL_OUTLINE
        call FillRect

        push 48
        push 130
        push 32
        push 30
        push COL_PIPE_LIGHT
        call FillRect

        push 88
        push 130
        push 32
        push 30
        push COL_COIN
        call FillRect

        push 128
        push 130
        push 32
        push 30
        push COL_GROUND_TOP
        call FillRect

        mov ah, 00h             ; BIOS: wait for a key
        int 16h

exit:
        mov ax, 0003h           ; back to text mode
        int 10h
        mov ax, 4C00h           ; DOS: exit with code 0
        int 21h

; ----------------------------------------------------------
; SetPalette
; Purpose : loads colours into the VGA palette, from index 0
; Inputs  : [bp+6]=address of RGB table, [bp+4]=colour count
; Output  : none
; Changes : none (AX, CX, DX, SI saved and restored)
; ----------------------------------------------------------
SetPalette:
        push bp
        mov bp, sp
        push ax
        push cx
        push dx
        push si

        mov si, [bp+6]          ; SI -> table
        mov cx, [bp+4]          ; CX = colour count
        mov ax, cx
        shl ax, 1               ; AX = count * 2
        add cx, ax              ; CX = count * 3 bytes
        mov dx, 3C8h            ; palette write-index port
        xor al, al
        out dx, al              ; start at colour 0
        inc dx                  ; DX = 3C9h, palette data port
        cld
        rep outsb               ; send CX bytes from DS:SI to port

        pop si
        pop dx
        pop cx
        pop ax
        pop bp
        ret 4                   ; 2 args * 2 bytes

; ----------------------------------------------------------
; PutPixel
; Purpose : draws one pixel in Mode 13h
; Inputs  : [bp+8]=x, [bp+6]=y, [bp+4]=colour (low byte used)
; Output  : none
; Changes : none (AX, BX, DI, ES saved and restored)
; ----------------------------------------------------------
PutPixel:
        push bp
        mov bp, sp
        push ax
        push bx
        push di
        push es

        mov ax, VIDEO_SEG
        mov es, ax              ; ES -> video memory
        mov bx, [bp+6]          ; BX = y
        mov di, bx              ; DI = y
        shl bx, 8               ; BX = y * 256
        shl di, 6               ; DI = y * 64
        add di, bx              ; DI = y * 320
        add di, [bp+8]          ; DI = y * 320 + x
        mov ax, [bp+4]          ; AL = colour
        mov [es:di], al         ; plot the pixel

        pop es
        pop di
        pop bx
        pop ax
        pop bp
        ret 6                   ; 3 args * 2 bytes

; ----------------------------------------------------------
; FillRect
; Purpose : fills a solid rectangle in Mode 13h
; Inputs  : [bp+12]=x, [bp+10]=y, [bp+8]=width,
;           [bp+6]=height, [bp+4]=colour
; Output  : none
; Changes : none (AX, BX, CX, DX, DI, ES saved and restored)
; ----------------------------------------------------------
FillRect:
        push bp
        mov bp, sp
        push ax
        push bx
        push cx
        push dx
        push di
        push es

        mov ax, VIDEO_SEG
        mov es, ax
        mov bx, [bp+10]         ; BX = y
        mov di, bx
        shl bx, 8
        shl di, 6
        add di, bx              ; DI = y * 320
        add di, [bp+12]         ; DI = start offset
        mov ax, [bp+4]          ; AL = colour
        mov dx, [bp+6]          ; DX = rows left
        mov bx, SCREEN_W
        sub bx, [bp+8]          ; BX = 320 - width (row skip)
        cld                     ; stosb moves DI forward
        cmp dx, 0
        je .done                ; height 0: draw nothing
.row:
        mov cx, [bp+8]          ; CX = width
        rep stosb               ; fill one row
        add di, bx              ; jump to start of next row
        dec dx
        jnz .row
.done:
        pop es
        pop di
        pop dx
        pop cx
        pop bx
        pop ax
        pop bp
        ret 10                  ; 5 args * 2 bytes