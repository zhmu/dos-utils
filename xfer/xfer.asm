cpu 8086
org 100h

section .text
            jmp start

COM_BASE    equ 03f8h
DATA        equ 0
IER         equ 1
FIFO        equ 2
LCR         equ 3
MCR         equ 4
LSR         equ 5
MSR         equ 6
SR          equ 7

; zf=0 if char available
com_check_char:
            mov dx,COM_BASE+LSR
            in  al,dx
            and al,1
            ret

; wait for byte, returned in al
com_read:
            call com_check_char
            jz   com_read

            mov dx,COM_BASE+DATA
            in al,dx
            ret

; sends byte in al
com_write:
            push ax
w:
            mov dx,COM_BASE+LSR
            in al,dx
            and al,020h
            jz w

            pop ax
            mov dx,COM_BASE+DATA
            out dx,al
            ret

; in al='0..9', 'A-F', out: cf=0 on ok, al=0..f
conv_nibble:
            cmp al,'9'
            jg  conv_nibble_not_num
            cmp al,'0'
            jl  conv_nibble_err
            sub al,'0'
            clc
            ret

conv_nibble_not_num:
            cmp al,'F'
            jg  conv_nibble_err
            cmp al,'A'
            jl  conv_nibble_err
            sub al,'A'-10
            clc
            ret

conv_nibble_err:
            stc
            ret

; cf=0 ok, al=byte
; cf=1 , al=0, error, al=1 end of transfer
get_byte:
            call com_read
            cmp  al,'#'
            je   get_byte_eot

            call conv_nibble
            jc   get_byte_err
            mov  bh,al
            shl  bh,1
            shl  bh,1
            shl  bh,1
            shl  bh,1

            call com_read
            cmp  al,'#'
            je   get_byte_eot
            call conv_nibble
            jc   get_byte_err

            xor  ah,ah
            add  al,bh
            clc
            ret

get_byte_eot:
            mov al,1
            stc
            ret
get_byte_err:
            xor al,al
            stc
            ret

start:      ; zero-terminate commandline arg
            mov si,80h
            xor ah,ah
            lodsb
            cmp ax,2
            jge start2

            mov dx,msg_no_arg
            jmp die

start2:
            mov bx,ax            ; length
            mov byte [si+bx],0   ; zero terminate

            ; wire for 9600/8n1, no interrupts
            xor al,al
            mov dx,COM_BASE+IER
            out dx,al

            mov dx,COM_BASE+LCR
            mov al,080h
            out dx,al

            mov dx,COM_BASE+DATA
            mov al,12
            out dx,al

            mov dx,COM_BASE+IER
            mov al,0
            out dx,al

            mov dx,COM_BASE+LCR
            mov al,3
            out dx,al

            mov dx,COM_BASE+FIFO
            mov al,0c7h
            out dx,al

            mov bp,2000

handshake_loop:
            cmp  bp,2000
            jne  ack_no_send

            ; send '+' to show we are online
            mov al,'+'
            call com_write

            xor bp,bp

ack_no_send:
            inc  bp

            ; wait for acknowledgement
            call com_check_char
            jnz  ack_got_char

            mov  ah,1
            int  16h
            jz   handshake_loop

            xor  ah,ah
            int  16h

            mov  dx,msg_aborted
            jmp  die

ack_got_char:
            call com_read

            ; ack
            cmp  al,'!'
            jnz  handshake_loop

            ; handshake done
            mov  di,buf
            mov  bp,0ffffh

data_loop:  call get_byte
            jnc  data_ok

            cmp  al,1
            jz   data_done
            jmp  data_error

data_ok:
            ; got byte in ax
            stosb
            add  bp,ax
            not  bp

            jmp  data_loop

data_error:
            mov dx,msg_data_err
            jmp die

checksum_error:
            mov dx,msg_checksum_err
            jmp die

data_done:
            call get_byte
            jc   data_error
            mov  ch,al
            call get_byte
            jc   data_error
            mov  cl,al

            cmp  cx,bp
            jne  checksum_error

            mov  ah,3ch
            mov  dx,82h ; commandline arg (skip space)
            xor  cx,cx
            int  21h
            jnc  fil_ok

file_err:
            mov dx,msg_fil_err
            jmp die

fil_ok:     mov bx,ax
            mov ah,40h
            mov dx,buf
            mov cx,di
            sub cx,buf
            int 21h
            jc file_err

            mov ah,3eh
            int 21h
            int 20h

die:        mov ah,9
            int 21h
            int 20h

msg_data_err:
            db 'Data error$'

msg_fil_err:
            db 'File error$'

msg_aborted:
            db 'Aborted$'
msg_checksum_err:
            db 'Checksum error$'
msg_no_arg:
            db 'Need argument for file$'

buf         equ $
