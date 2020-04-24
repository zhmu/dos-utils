cpu 286
org 100h

section .text
            jmp start

IDE_BASE    equ 01f0h
DATA        equ 0
ERROR       equ 1
DEV_CONTROL equ 2
SECTOR_CNT  equ 2
SECTOR_NUM  equ 3
CYL_LO      equ 4
CYL_HI      equ 5
DEV_HEAD    equ 6
STATUS      equ 7
COMMAND     equ 7
ALT_BASE    equ 03f4h
ALT_STATUS  equ 2

CMD_IDENTIFY equ 0ech
CMD_READ    equ 20h     ; 28-bit pio
CMD_WRITE   equ 30h     ; 28-bit pio

tiny_wait:
            mov dx,ALT_BASE+ALT_STATUS
            in al,dx
            in al,dx
            in al,dx
            in al,dx
            ret

huge_wait:
            mov cx,1000
            mov dx,ALT_BASE+ALT_STATUS
w:
            in al,dx
            loop w
            ret

; out: cf=1 on error, cf=0 ok
wait_not_bsy:
            xor     cx,cx
            mov     dx,IDE_BASE+STATUS
wait_not_bsy1:
            in      al,dx
            and     al,080h         ; BSY
            jz      wait_not_bsy2
            loop    wait_not_bsy1

            stc
            ret

wait_not_bsy2:
            clc
            ret

; out: cf=1 on error (timeout/disk error), cf=0 ok
wait_drq:
            mov     dx,IDE_BASE+STATUS
            xor     cx,cx
wait_data1:
            in      al,dx
            and     al,9            ; DRQ, ERR
            or      al,al
            jnz     wait_data2
            loop    wait_data1

            stc
            ret

wait_data2:
            clc
            ret


reset:

            ; reset channel
            mov dx,IDE_BASE+DEV_HEAD
            mov al,0a0h
            out dx,al
            call    tiny_wait
            mov dx,IDE_BASE+DEV_CONTROL
            mov al,6                    ; nIEN | SRST
            out dx,al
            call    tiny_wait
            xor al,al
            out dx,al
            call    tiny_wait
            mov     dx,IDE_BASE+ERROR
            in      al,dx
            ret

do_read:
            mov dx,IDE_BASE+DEV_HEAD
            mov al,0a0h                         ; select disk 0
            out dx,al
            mov al,1
            mov dx,IDE_BASE+SECTOR_CNT          ; 1 sector
            out dx,al
            mov dx,IDE_BASE+SECTOR_NUM
            mov al,1                            ; sector 0
            out dx,al
            xor al,al
            mov dx,IDE_BASE+CYL_HI
            out dx,al
            mov dx,IDE_BASE+CYL_LO
            out dx,al                           ; cyl 0
            mov dx,IDE_BASE+COMMAND
            mov al,CMD_READ
            out dx,al

            call    wait_not_bsy
            jc      error

            call    wait_drq
            jc      error

            mov     di,buf
            mov     cx,256
            mov     dx,IDE_BASE+DATA
do_read1:   in      ax,dx
            stosw
            loop    do_read1
            ret

; buffer in buf, 512 bytes
do_write:
            mov dx,IDE_BASE+DEV_HEAD
            mov al,0a0h                         ; select disk 0
            out dx,al
            mov al,1
            mov dx,IDE_BASE+SECTOR_CNT          ; 1 sector
            out dx,al
            mov dx,IDE_BASE+SECTOR_NUM          ; sector 1
            mov al,1
            out dx,al
            xor al,al
            mov dx,IDE_BASE+CYL_HI              ; cyl 0
            out dx,al
            mov dx,IDE_BASE+CYL_LO
            out dx,al
            mov dx,IDE_BASE+COMMAND
            mov al,CMD_WRITE
            out dx,al

            call    wait_not_bsy
            jc      error

            call    wait_drq
            jc      error

            mov     si,buf
            mov     cx,256
            mov     dx,IDE_BASE+DATA
do_write1:  lodsw
            out     dx,ax
            loop    do_write1
            ret

start:      push cs
            push cs
            pop  ds
            pop  es

            call reset

            call  do_read

            ; copy partition table
            mov si,buf+1beh
            mov di,part_tab
            mov cx,32
            rep movsw

            ;mov si,buf
            ;int 3
            ;int 20h

            mov ax,3d00h
            mov dx,boot_fname
            int  21h
            jnc   bf_ok

file_krak:
            mov   ah,9
            mov   dx,err_f
            int   21h
            int   20h

err_f:      db    "File error$"

bf_ok:      mov   bx,ax
            mov   ah,3fh
            mov   dx,buf
            mov   cx,200h
            int   21h
            jc    file_krak

            mov   ah,3eh
            int   21h

            ; restore partition table
            mov si,part_tab
            mov di,buf+1beh
            mov cx,32
            rep movsw

            mov si,buf
            call do_write
            int 20h

            ; select disk 0
            mov dx,IDE_BASE+DEV_HEAD
            mov al,0a0h
            out dx,al
            xor al,al
            mov dx,IDE_BASE+SECTOR_CNT
            out dx,al
            mov dx,IDE_BASE+SECTOR_NUM
            out dx,al
            mov dx,IDE_BASE+CYL_HI
            out dx,al
            mov dx,IDE_BASE+CYL_LO
            out dx,al
            mov dx,IDE_BASE+COMMAND
            mov al,CMD_IDENTIFY
            out dx,al
            ;call    tiny_wait

            call    wait_not_bsy
            jc      error

            call    wait_drq
            jc      error

ok2:
            ; fetch data
            mov     di,buf
            mov     cx,256
            mov     dx,IDE_BASE+DATA
llz:        in      ax,dx
            stosw
            loop    llz

            mov     si,buf
            mov     di,buf
            mov     cx,256

ffx:        lodsw
            xchg    ah,al
            stosw
            loop    ffx

            mov     di,buf
            int     3
            mov     ax,0e42h ; 'B'
            int     10h

            int     20h

error:
            mov     ax,0e45h ; 'E'
            int     10h
	        int 20h

boot_fname:
            db      "boots.bin",0

part_tab:   times   64 db 0
buf         equ     $
