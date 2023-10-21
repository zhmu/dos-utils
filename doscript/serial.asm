                extrn _com_port: word
                extrn _com_irq: word

                extern _com_buffer: byte
                extern _com_buf_read_ptr: byte
                extern _com_buf_write_ptr: byte

dgroup          group       _bss

_bss            segment public byte 'bss'
_bss            ends

_text           segment public byte 'code'
                assume cs:_text, ds:dgroup

; must be a power of 2
BUFFER_SIZE     equ     64
BUFFER_MASK     equ     BUFFER_SIZE-1

serial_irq          proc
                    push    ds
                    push    ax
                    push    bx
                    push    dx
                    push    di

                    int 3

                    mov     ax,seg DGROUP
                    mov     ds,ax

                    xor     bh,bh
                    mov     bl,_com_buf_write_ptr
                    mov     di,offset _com_buffer       ; [di+bx] points to char to store

                    mov     dx,_com_port
serial_irq_check_chars:
                    push    dx
                    add     dx,5            ; LSR
                    in      al,dx
                    pop     dx
                    test    al,1
                    jz      serial_irq_nochar

                    ; receive char, store
                    in      al,dx           ; data
                    mov     [di+bx],al

                    ; advance buffer
                    inc     bl
                    and     bl,BUFFER_MASK
                    jmp     serial_irq_check_chars

serial_irq_nochar:
                    mov     _com_buf_write_ptr,bl

                    pop     di
                    pop     dx
                    pop     bx
                    pop     ax
                    pop     ds
                    db      0eah            ; jmp far
serial_irq_prev     dw      0, 0
serial_irq          endp

public serial_init_irqs_
serial_init_irqs_   proc    near

                    int 3

                    push    ds
                    push    es
                    push    bx
                    push    dx

                    mov     ax,seg DGROUP
                    mov     ds,ax

                    ; get old irq handler
                    mov     ax,_com_irq
                    push    ax
                    add     ax,3508h            ; dos: get interrupt vector (+8)
                    int     21h
                    mov     word ptr cs:serial_irq_prev,bx
                    mov     word ptr cs:serial_irq_prev+2,es

                    ; set new irq handler
                    pop     ax
                    add     ax,2508h            ; dos: set interrupt vector (+8)
                    push    cs
                    pop     ds
                    mov     dx,offset serial_irq
                    int     21h

                    pop     bx
                    pop     dx
                    pop     es
                    pop     ds
                    ret
serial_init_irqs_   endp

public serial_cleanup_irqs_
serial_cleanup_irqs_ proc
                    push    bx
                    mov     bx,_com_irq

                    push    dx
                    mov     dx,word ptr cs:serial_irq_prev
                    mov     ax,word ptr cs:serial_irq_prev+2
                    push    ds
                    mov     ds,ax

                    mov     ax,bx
                    add     ax,2508h            ; dos: set interrupt vector (+8)
                    int     21h

                    pop     ds
                    pop     dx
                    pop     bx
                    ret
serial_cleanup_irqs_ endp

_text               ends
                    end
