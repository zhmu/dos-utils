    cpu 8086
    org 0h

    section .text
                jmp start

%define SHOW_CHS 1

    RELOC_SEG   equ 1000h
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

    CMD_IDENTIFY equ 0ech

    msg_hello:    db "IDE ",0
    msg_id_pre:   db "- <",0
    msg_id_post:  db "> C/H/S ",0
    msg_ide_err:  db "error",0
    msg_key:      db "Key...",0
%if SHOW_CHS
    hextab:       db "0123456789ABCDEF"
%endif

    ; prints asciiz message in ds:si
    print_msg:
                mov ah,0eh
    print1:     lodsb
                or  al,al
                jz  print_done
                int 10h
                jmp print1
    print_done: ret

    ; waits until BUSY=0 and DRQ=1
    wait_ide:
                xor     cx,cx
                mov     dx,IDE_BASE+STATUS
                ; first wait until BSY goes lo
    wait_not_bsy1:
                in      al,dx
                and     al,080h         ; BSY
                jz      wait_ok
                loop    wait_not_bsy1

    ide_error:
                mov si,msg_ide_err
                call print_msg
                jmp floppy_loop

    wait_ok:
                ; then wait until DRQ/ERR go hi
                xor     cx,cx
    wait_data1:
                in      al,dx
                and     al,9            ; DRQ, ERR
                jnz     drq_ok
                loop    wait_data1
                jmp     ide_error

    drq_ok:     and     al,1            ; check ERR
                jnz     ide_error
                ret

    ; es:di = identify data
    do_identify:
                ; select disk 0
                mov dx,IDE_BASE+DEV_HEAD
                mov al,0a0h
                out dx,al
                xor al,al
                mov dx,IDE_BASE+SECTOR_CNT
                out dx,al
                inc dx                  ; mov dx,IDE_BASE+SECTOR_NUM
                out dx,al
                inc dx                  ; mov dx,IDE_BASE+CYL_LO
                out dx,al
                inc dx                  ; mov dx,IDE_BASE+CYL_HI
                out dx,al
                inc dx
                inc dx                  ; mov dx,IDE_BASE+COMMAND
                mov al,CMD_IDENTIFY
                out dx,al

                call    wait_ide

                ; fetch data
                mov     cx,256
                mov     dx,IDE_BASE+DATA
    llz:        in      ax,dx
                stosw
                loop    llz
                ret

    start:      ; relocate to 1000:0
                xor ax,ax
                mov ds,ax
                mov ax,RELOC_SEG
                mov es,ax
                mov si,7c00h
                xor di,di
                mov cx,256
                rep movsw
                jmp word RELOC_SEG:entry

    entry:      mov ax,cs
                mov ds,ax
                mov es,ax

                mov si,msg_hello
                call print_msg

                mov di,200h
                call do_identify

                mov si,msg_id_pre
                call print_msg

                mov bx,200h
                lea si,[bx+27*2] ; model number

                ; swap lo/hi byte of model number
                push si
                mov di,si
                mov cx,19
    swap_loop:  lodsw
                xchg ah,al
                stosw
                loop swap_loop

                ; cut off trailing spaces
                dec di ; initially, last byte
    clear_loop:
                mov al,[di]
                cmp al,20h
                jne clear_done
                ; this byte is 20h; walk backwards
                dec di
                jmp clear_loop

    clear_done:
                ; next byte must be cleared
                inc di
                xor al,al
                stosb
                pop si ; original model string
                call print_msg

                mov bp,[bx+1*2] ; cyl
                mov cx,[bx+3*2] ; heads
                mov dx,[bx+6*2] ; spt

%if SHOW_CHS
                mov si,msg_id_post
                call print_msg
                mov ax,bp
                call print_word ; destroys ax/bx
                mov ax,0e2fh
                push ax ; store print '/'
                int 10h
                mov ax,cx
                call print_word
                pop ax ; restore print '/'
                int 10h
                mov ax,dx
                call print_word
                mov ax,0e0ah
                int 10h
                mov al,0dh
                int 10h
%endif

                xor ax,ax
                mov ds,ax
                mov bx,104h         ; ds:bx = int 41 vector

                mov ax,40h
                mov es,ax
                mov di,0b0h         ; es:di = disk params buffer

                mov [bx],di         ; off
                mov [bx+2],ax       ; seg

                mov ax,bp           ; 490
                stosw               ; #cyl
                mov ax,cx           ; 8
                stosb               ; #heads
                ; 0 / writecomp / 0 / control byte / 0 / 0 / 0 / landing zone
                xor ax,ax
                mov cx,11
                rep stosb
                mov al,dl           ; 32
                stosw               ; sectors per track / 0

                ; reset hdd to ensure the new chs info is read
                xor ax,ax
                mov dl,80h
                int 13h

                xor ax,ax
                mov es,ax
                mov ax,cs
                mov ds,ax

                mov al,[es:417h]    ; keyboard status
                and al,3            ; either shift active?
                jnz floppy_loop     ; yes, skip harddisk boot

                mov si,part_tab
                mov al,[si]
                cmp al,80h
                jne floppy_loop

                ; read partition sector
                mov ax,0201h
                mov bx,7c00h        ; es:bx = dest
                mov cx,[si+2]       ; cyl lo/sector
                mov dh,[si+1]      ; head
                mov dl,80h
                int 13h
                jnc read_ok

    floppy_loop:
                mov si,msg_key
                call print_msg
                xor ah,ah
                int 16h

                mov bp,5            ; 5 retries

    fdd_loop:
                xor ax,ax           ; reset disk
                mov es,ax
                int 13h

                mov ax,0201h
                mov bx,7c00h
                mov cx,0001h        ; cyl 0, sec 1
                mov dx,0000h        ; drive 0 head 0
                int 13h
                jnc read_ok

                dec bp
                jns fdd_loop

                jmp floppy_loop

    read_ok:
                xor ax,ax
                mov ds,ax
                mov es,ax
                jmp word 0h:7c00h

%if SHOW_CHS
    ; bl = nibble to print
    ; destroys: ax, bx, si
    print_nib:
                mov si,hextab
                xor bh,bh
                mov al,[si+bx]
                mov ah,0eh
                int 10h
                ret

    ; al = byte to print
    ; destroys: ax, bx, si
    print_byte:
                mov bl,al
                push bx
                shr bl,1
                shr bl,1
                shr bl,1
                shr bl,1
                call print_nib
                pop bx
                and bl,15
                jmp print_nib

    ; ax = word to print
    ; destroys: ax, bx, si
    print_word:
                push ax
                xchg ah,al
                call print_byte
                pop ax
                jmp print_byte
%endif

                times 446-($-$$) db 0

    part_tab:
                times 64 db 0

                times 510-($-$$) db 0
                db 055h, 0aah
