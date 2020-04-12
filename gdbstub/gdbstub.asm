; vim:set ts=8 sw=8:
cpu 8086
org 100h

section .text
            jmp start

; if non-zero, dump all packets sent/received
%define GDB_TRACE 0

; if non-zero, display a marker when GDB is active
%define SHOW_MARKER 1

; if non-zero, allow this scancode to break to GDB
%define BREAK 0 ;29h ; `/~

COM_BASE    equ 03f8h ; COM1
DATA        equ 0
IER         equ 1
FIFO        equ 2
LCR         equ 3
MCR         equ 4
LSR         equ 5
MSR         equ 6
SR          equ 7

; sizeof(gdb_regs) = 64
struc           gdb_regs
gdb_eax:        resd    1               ; 0
gdb_ecx:        resd    1               ; 4
gdb_edx:        resd    1               ; 8
gdb_ebx:        resd    1               ; 12
gdb_esp:        resd    1               ; 16
gdb_ebp:        resd    1               ; 20
gdb_esi:        resd    1               ; 24
gdb_edi:        resd    1               ; 28
gdb_eip:        resd    1               ; 32
gdb_efl         resd    1               ; 36
gdb_cs          resd    1               ; 40
gdb_ss          resd    1               ; 44
gdb_ds          resd    1               ; 48
gdb_es          resd    1               ; 52
gdb_fs          resd    1               ; 56
gdb_gs          resd    1               ; 60
endstruc

; zf=0 if char available
com_check_char:
        mov dx,COM_BASE+LSR
        in  al,dx
        and al,1
        ret

; wait for byte, returned in al
; destroys: dx
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
        and al,0xdf                     ; 'a' -> 'A'
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
; cf=1 error
; destroys: bh, dx
com_read_byte:
        call com_read

        call conv_nibble
        jc   get_byte_err
        mov  bh,al
        shl  bh,1
        shl  bh,1
        shl  bh,1
        shl  bh,1

        call com_read
        call conv_nibble
        jc   get_byte_err

        add  al,bh
        clc
        ret

get_byte_err:
        stc
        ret

; reads packet to es:di, max of BUFSIZE will be read
; returns: carry=1 on failure, al=1: buffer size exhaused, al=2: checksum error
;          es:di = filled buffer, zero-terminated (length in cx)
gdb_getpacket:
        call    com_read
        cmp     al,'$'
        jne     gdb_getpacket

        xor     ah,ah                   ; checksum
        xor     cx,cx
gdb_loop:
        call    com_read
        cmp     al,'$'                  ; reset on $ received
        je      gdb_getpacket
        cmp     al,'#'
        je      gdb_loop_done
        add     ah,al                   ; checksum
        stosb
        inc     cx
        cmp     cx,BUFSIZE-1
        jl      gdb_loop

        ; buffer size exhaused - reject
        mov     al,1
        stc
        ret

gdb_cksum_err:
        mov     al,'-'          ; checksum error
        call    com_write

        mov     al,2
        stc
        ret

gdb_loop_done:
        xor     al,al
        stosb
        inc     cx

        ; get checksum
        call    com_read_byte
        jc      gdb_cksum_err
        cmp     al,ah
        jne     gdb_cksum_err

        mov     al,'+'          ; transfer okay
        call    com_write

        sub     di,cx           ; orig buffer start
        ret

; in: bl = nibble to convert; out: al = ascii char
; destroys: al, bh, si, dx
nibble2ascii:
        mov     si,hextab
        xor     bh,bh
        mov     al,[si+bx]
        ret

; bl = nibble to write; will be written as 1 hex char
; destroys: al, bh, si, dx
com_write_nibble:
        call    nibble2ascii
        jmp     com_write

; al = byte to print; will be written as 2 hex chars
; destroys: al, bx, si, dx
com_write_byte:
        mov     bl,al
        push    bx
        shr     bl,1
        shr     bl,1
        shr     bl,1
        shr     bl,1
        call    com_write_nibble
        pop     bx
        and     bl,15
        jmp     com_write_nibble

; atoi: ds:si = asciiz hex string
; out: bx:dx = value, al=last char read, si updated
atoi:
        xor     ah,ah
        xor     bx,bx
        xor     dx,dx
atoi_loop:
        lodsb

        or      al,al
        jz      atoi_done
        call    conv_nibble
        jc      atoi_done

        shl     bx,1
        shl     dx,1
        adc     bx,0

        shl     bx,1
        shl     dx,1
        adc     bx,0

        shl     bx,1
        shl     dx,1
        adc     bx,0

        shl     bx,1
        shl     dx,1
        adc     bx,0

        add     dx,ax
        jmp     atoi_loop

atoi_done:
        ret

; sends packet in ds:si
; destroys: ax, bx, si, dx, bp
gdb_putpacket:
%if GDB_TRACE
        push    si
        push    si
        mov     si,msg_write_prefix
        call    print_str
        pop     si
        call    print_str
        mov     si,msg_write_postfix
        call    print_str
        pop     si
%endif

        mov     bp,si
gdb_putpacket_retry:

        mov     al,'$'
        call    com_write

        xor     bl,bl
        mov     si,bp
gdb_putpacket_loop:
        lodsb
        or      al,al
        jz      gdb_putpacket_end
        add     bl,al
        call    com_write
        jmp     gdb_putpacket_loop

gdb_putpacket_end:
        push    bx
        mov     al,'#'
        call    com_write
        pop     ax                      ; checksum byte in al
        call    com_write_byte

        ; wait for positive acknowlegment
        call    com_read
        cmp     al,'+'
        jne     gdb_putpacket_retry
        ret

setup_com:
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
        ret

print_str:
        mov ah,0eh
prt_lp:
        lodsb
        or      al,al
        jz      prt_done
        int 10h
        jmp     prt_lp
prt_done:
        ret

; convert byte to ascii and stores in buffer
; in: al=byte, es:di=buffer
; out: updated di
; destroys: bx
conv_store_byte:
        mov     bl,al
        push    si
        push    bx
        shr     bl,1
        shr     bl,1
        shr     bl,1
        shr     bl,1
        call    nibble2ascii
        stosb
        pop     bx
        and     bl,15
        call    nibble2ascii
        pop     si
        stosb
        ret

; entrypoint for GDB interaction
gdb_enter:
gdb_enter_loop:
        ; reads packet to es:di, max of BUFSIZE will be read
        mov     di,buf
        call    gdb_getpacket

%if GDB_TRACE
        mov     si,msg_read_prefix
        call    print_str

        mov     si,di
        call    print_str

        mov     si,msg_read_postfix
        call    print_str
%endif

        ; fetch and decode command byte
        ;
        ; need:
        ;   [ok] g / G = for register access
        ;   m / M = for memory access
        ;   [ok] c = continue
        ;   [ok] s = step
        ; optional:
        ;   q = general query
        ;   Q = general set
        ;
        mov     si,di
        lodsb
        cmp     al,'v'
        je      gdb_v_or_q
        cmp     al,'q'
        je      gdb_v_or_q
        cmp     al,'g'
        je      gdb_g
        cmp     al,'m'
        je      gdb_m
        cmp     al,'s'
        je      gdb_s
        cmp     al,'c'
        je      gdb_c

        mov     si,notsup
        call    gdb_putpacket
        jmp     gdb_done

gdb_v_or_q:
        mov     si,empty
        call    gdb_putpacket
        jmp     gdb_done

gdb_g:
        ; g = read registers
        mov     si,regs
        mov     di,buf
        mov     cx,gdb_regs_size
gdb_g_loop:
        lodsb
        call    conv_store_byte
        loop    gdb_g_loop
        ; zero-terminate
        xor     al,al
        stosb

        mov     si,buf
        call    gdb_putpacket
        jmp     gdb_done

gdb_s:
        ; for step, we need to enable the trap flag
        or      word [regs+gdb_efl],100h        ; TF
        jmp     gdb_ok

gdb_c:
        ; for continue, ensure the trap flag is disabled
        and     word [regs+gdb_efl],0feffh      ; TF

gdb_ok:
        mov     si,reply_ok
        jmp     gdb_putpacket

gdb_m:
        ; m<addr>,<len> = read memory
        call    atoi
        mov     bp,dx
        mov     cl,12
        shl     bx,cl               ; bx:bp = addr (seg/off)

        push    bx
        call    atoi
        mov     cx,dx               ; cx = len
        pop     bx

        mov     di,buf
gdb_m_loop:
        push    ds
        mov     ds,bx
        mov     al,[ds:bp]
        pop     ds
        inc     bp

        push    bx
        call    conv_store_byte
        pop     bx
        loop    gdb_m_loop

        ; zero terminate
        xor     al,al
        stosb

        mov     si,buf
        call    gdb_putpacket
        jmp     gdb_done

gdb_done:
        jmp     gdb_enter_loop

old_sp  dw      0
old_ss  dw      0

%if BREAK
new_irq1:
        ; don't nest; chain if we are already active
        cmp     byte [cs:gdb_active],0
        jne     irq1_chain

        push    ax
        in      al,60h
        cmp     al,BREAK
        je      break_hit
irq1_pop_ax_chain:
        pop     ax
irq1_chain:
        db      0eah        ; jmp far
old_irq1:   dd  0

break_hit:
        ; check if control is down
        push    es
        xor     ax,ax
        mov     es,ax
        mov     al,[es:417h]    ; keyboard: status flags 1
        pop     es
        and     al,4            ; either control pressed?
        jz      irq1_pop_ax_chain

        ; wait until key released
        in      al,60h
        cmp     al,80h+BREAK
        jne     break_hit

        ; ack IRQ
        mov     al,20h
        out     20h,al
        pop     ax

        jmp     new_int3
        iret
%endif

new_int1:
        jmp     new_int3
        db      "GDB"
new_int3:
        cli
%if BREAK
        inc     byte [cs:gdb_active]
%endif
        mov     [cs:old_sp],sp
        mov     [cs:old_ss],ss

        ; store registers (frees up ax/ds/es)
        mov     [cs:regs+gdb_eax],ax
        mov     [cs:regs+gdb_ds],ds
        mov     [cs:regs+gdb_es],es

        ; switch to our segments; don't switch to ss yet
        mov     ax,cs
        mov     ds,ax

        ; store remaining registers
        mov     [regs+gdb_ecx],cx
        mov     [regs+gdb_edx],dx
        mov     [regs+gdb_ebx],bx
        mov     [regs+gdb_ebp],bp
        mov     [regs+gdb_esi],si
        mov     [regs+gdb_edi],di

%if SHOW_MARKER
        mov     ax,[marker_seg]
        mov     es,ax
        mov     di,[marker_off]
        mov     ax,4e47h            ; 'G'
        stosw
%endif
        mov     ax,cs
        mov     es,ax

        ; store saved ss:sp now that we have regs to spare
        mov     ax,[cs:old_sp]
        mov     [cs:regs+gdb_esp],ax
        mov     ax,[cs:old_ss]
        mov     [cs:regs+gdb_ss],ax

        ; copy things from stackframe
        pop     ax
        mov     [cs:regs+gdb_eip],ax
        pop     ax
        mov     [cs:regs+gdb_cs],ax
        pop     ax
        mov     [cs:regs+gdb_efl],ax

        ; switch stacks
        mov     ax,cs
        mov     ss,ax
        mov     sp,int_stack+INT_STACKSIZE

        ; inform e
        mov     si,reply_stopped
        call    gdb_putpacket

        ; enter gdb loop
        call    gdb_enter

%if SHOW_MARKER
        mov     ax,[marker_seg]
        mov     es,ax
        mov     di,[marker_off]
        mov     ax,0720h            ; ' '
        stosw
%endif

        ; transfer register ss:sp to saved ss:sp
        mov     sp,[regs+gdb_esp]
        mov     [old_sp],sp
        mov     ax,[regs+gdb_ss]
        mov     ss,ax

        ; overwrite original cs/ip/eflags with these from registers
        add     sp,6
        mov     ax,[cs:regs+gdb_efl]
        push    ax
        mov     ax,[cs:regs+gdb_cs]
        push    ax
        mov     ax,[cs:regs+gdb_eip]
        push    ax

        ; restore registers
        mov     ax,[regs+gdb_eax]
        mov     bx,[regs+gdb_ebx]
        mov     cx,[regs+gdb_ecx]
        mov     dx,[regs+gdb_edx]
        mov     bp,[regs+gdb_ebp]
        mov     si,[regs+gdb_esi]
        mov     di,[regs+gdb_edi]
        mov     es,[regs+gdb_es]
        mov     ds,[regs+gdb_ds]
%if BREAK
        dec     byte [cs:gdb_active]
%endif
        iret

old_int1    dd  0
old_int3    dd  0

hextab:     db "0123456789ABCDEF"
%if GDB_TRACE
msg_read_prefix:    db  "read <",0
msg_read_postfix:   db  ">",10,13,0
msg_write_prefix:   db  "write <",0
msg_write_postfix   equ msg_read_postfix
%endif
%if SHOW_MARKER
marker_seg:         dw 0b800h
marker_off:         dw (78*2)
%endif
%if BREAK
gdb_active: db  0
%endif

INT_STACKSIZE equ  128
BUFSIZE equ     200
notsup: db      "E notsup",0
reply_stopped:  db "S05",0  ; 5 = debug signal
reply_ok: db    "OK",0
empty:  db      0
regs:   times   gdb_regs_size db 0
int_stack: times INT_STACKSIZE db 0
buf:    times BUFSIZE db 0

res_end equ $

; below is not resident

start:
        mov     ax,3501h            ; get int vector: 1
        int     21h

        ; check if the int 1 vector contains our magic
        mov     si,bx
        mov     di,new_int1
        mov     cx,new_int3-new_int1
        rep     cmpsb
        je      uninstall

        ; not installed; save vectors
        mov     [old_int1],bx
        mov     [old_int1+2],es

        mov     ax,3503h            ; get int vector: 3
        int     21h
        mov     [old_int3],bx
        mov     [old_int3+2],es

        mov     ax,2501h            ; set int vector: 1
        mov     dx,new_int1
        int     21h

        mov     ax,2503h            ; set int vector: 3
        mov     dx,new_int3
        int     21h

%if BREAK
        mov     ax,3509h            ; get int vector: irq1
        int     21h
        mov     [old_irq1],bx
        mov     [old_irq1+2],es

        mov     ax,2509h            ; set int vector: irq1
        mov     dx,new_irq1
        int     21h
%endif

        ; all done
        call    setup_com
        mov     ah,9
        mov     dx,msg_installed
        int     21h

        mov     ah,49h              ; free memory
        mov     es,[cs:2ch]         ; env
        int     21h

        mov     ax,3100h            ; dos: tsr
        mov     dx,res_end
        shr     dx,1
        shr     dx,1
        shr     dx,1
        shr     dx,1
        inc     dx
        int     21h

uninstall:
        ; restore int1 / int3
        mov     dx,[es:old_int1]
        mov     ax,[es:old_int1+2]
        mov     ds,ax
        mov     ax,2501h            ; set int vector: 1
        int     21h

        mov     dx,[es:old_int3]
        mov     ax,[es:old_int3+2]
        mov     ds,ax
        mov     ax,2503h            ; set int vector: 3
        int     21h

%if BREAK
        mov     dx,[es:old_irq1]
        mov     ax,[es:old_irq1+2]
        mov     ds,ax
        mov     ax,2509h            ; set int vector: irq1
        int     21h
%endif

        mov     ah,49h              ; free memory
        int     21h

        push    cs
        pop     ds

        mov     ah,9
        mov     dx,msg_uninstalled
        int     21h

        int     20h

msg_uninstalled:    db "un"
msg_installed:      db "installed GDB debug stub",10,13,"$"
