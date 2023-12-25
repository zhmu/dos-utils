                    extern _driver_entry: dword

DPatchReq           equ 0
DInit               equ 1
DTerminate          equ 2
DService            equ 3
DNoteOff            equ 4
DNoteOn             equ 5
DPolyAfterTch       equ 6
DController         equ 7
DProgramChange      equ 8
DChannelAfterTch    equ 9
DPitchBend          equ 10
DSetReverb          equ 11
DSetMasterVolume    equ 12
DSoundOn            equ 13
DSamplePlay         equ 14
DSampleEnd          equ 15
DSampleInfo         equ 16
DAskDriver          equ 17

dgroup              group       _bss

_bss                segment public byte 'bss'
_bss                ends

_text               segment public byte 'code'
                    assume cs:_text, ds:dgroup, es:dgroup

; dx:ax = DRIVER_INFO*
public driver_info_
driver_info_        proc
                    push    es
                    push    di
                    push    cx
                    push    bx

                    mov     es,dx
                    mov     di,ax               ; es:di = DRIVER_INFO*

                    ; obtain driver signature in dx:bx, driver type in al
                    push    ds
                    push    si
                    lds     si,_driver_entry
                    add     si,4
                    lodsw
                    mov     dx,ax
                    lodsw
                    mov     bx,ax
                    lodsb
                    pop     si
                    pop     ds

                    ; verify driver signature
                    xor     cx,cx               ; default to error
                    cmp     dx,4321h
                    jne     driver_info_ret
                    cmp     bx,8765h
                    jne     driver_info_ret
                    cmp     al,1                ; audio driver
                    jne     driver_info_ret

                    ; driver looks sane, request patch/voice count
                    push    bp
                    mov     bp,DPatchReq
                    call    _driver_entry
                    pop     bp

                    ; ax = patch number
                    ; cl = num voices, ch = device id (used in sound.xxx headers!)
                    ; note that for sci1+, ah = driver flags, al = patch number
                    stosw
                    mov     ax,cx
                    stosw

                    ; success
                    mov     cx,1

driver_info_ret:    mov     ax,cx
                    pop     bx
                    pop     cx
                    pop     di
                    pop     es
                    ret
driver_info_        endp

; dx:ax = patch data, returns ah = hiChnl, al = loChl, or 0 on error
public d_init_
d_init_             proc
                    push    cx
                    push    es

                    mov     es,dx           ; es:ax = patch data

                    push    bp
                    mov     bp,DInit
                    call    _driver_entry
                    pop     bp

                    ; ax = 0ffffh on error
                    cmp     ax,0ffffh
                    je      d_init_failed

                    ; ax = last byte of driver memory to keep (we ignore this)
                    ; set al = loChl, ah = hiChnl instead
                    mov     ax,cx
                    jmp     d_init_ret

d_init_failed:
                    xor     ax,ax
d_init_ret:

                    pop     es
                    pop     cx
                    ret
d_init_             endp

public d_terminate_
d_terminate_        proc
                    push    bx
                    push    cx
                    push    dx
                    push    bp
                    mov     bp,DTerminate
                    call    _driver_entry
                    pop     bp
                    pop     dx
                    pop     cx
                    pop     bx
                    ret
d_terminate_        endp

; watcom c calling convention: ax, dx, bx, cx

; 0 arguments
call_driver_0       macro fn
                    push    bx
                    push    cx
                    push    dx
                    push    bp

                    mov     bp,fn
                    call    _driver_entry
                    pop     bp
                    pop     dx
                    pop     cx
                    pop     bx
                    endm

; 1 argument: cl
call_driver_1       macro fn
                    push    bx
                    push    cx
                    push    dx
                    push    bp

                    mov     cl,al

                    mov     bp,fn
                    call    _driver_entry
                    pop     bp
                    pop     dx
                    pop     cx
                    pop     bx
                    endm

; 2 arguments: al, cl
call_driver_2       macro fn
                    push    bx
                    push    cx
                    push    dx
                    push    bp

                    mov     cl,dl

                    mov     bp,fn
                    call    _driver_entry
                    pop     bp
                    pop     dx
                    pop     cx
                    pop     bx
                    endm

; 3 arguments: al, ch and cl (was: ax, dx, bx)
call_driver_3       macro fn
                    push    bx
                    push    cx
                    push    dx
                    push    bp

                    ; the driver uses al, ch, and cl for the arguments..
                    mov     ch,dl
                    mov     cl,bl

                    mov     bp,fn
                    call    _driver_entry
                    pop     bp
                    pop     dx
                    pop     cx
                    pop     bx
                    endm

; D_Service(void)
public d_service_
d_service_          proc
                    call_driver_0 DService
                    ret
d_service_          endp

public d_note_on_
d_note_on_          proc
                    ; al = channel, ch = note, cl = velocity
                    call_driver_3 DNoteOn
                    ret
d_note_on_          endp

public d_note_off_
d_note_off_         proc
                    ; al = channel, ch = note, cl = velocity
                    call_driver_3 DNoteOff
                    ret
d_note_off_         endp

public d_poly_after_
d_poly_after_       proc
                    ; al = channel, ch = key, cl = pressure
                    call_driver_3 DPolyAfterTch
                    ret
d_poly_after_       endp

public d_controller_
d_controller_       proc
                    ; al = channel, ch = control number, cl = value
                    call_driver_3 DController
                    ret
d_controller_       endp

public d_program_change_
d_program_change_   proc
                    ; al = channel, cl = patch number
                    call_driver_2 DProgramChange
                    ret
d_program_change_   endp

public d_chnl_after_
d_chnl_after_       proc
                    ; al = channel, cl = pressure
                    call_driver_2 DChannelAfterTch
                    ret
d_chnl_after_       endp

public d_pitch_bend_
d_pitch_bend_       proc
                    call_driver_3 DPitchBend
                    ret
d_pitch_bend_       endp

public d_set_reverb_
d_set_reverb_       proc
                    ; cl = new reverb (0FFh to query)
                    call_driver_1 DSetReverb
                    ret
d_set_reverb_       endp

public d_set_volume_
d_set_volume_       proc
                    ; cl = new volume (0FFh to query)
                    call_driver_1 DSetMasterVolume
                    ret
d_set_volume_       endp

public d_sound_on_
d_sound_on_         proc
                    ; cl = play switch
                    call_driver_1 DSoundOn
                    ret
d_sound_on_         endp

_text               ends
                    end
