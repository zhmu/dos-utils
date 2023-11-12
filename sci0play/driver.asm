                    extern _driver_entry: dword
                    extern _patch_res: byte
                    extern _sound_res: byte

DPatchReq           equ 0
DInit               equ 2
DTerminate          equ 4
DLoadSound          equ 6
DService            equ 8
DSetVolume          equ 10
DStopSound          equ 14

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

                    ; ax = patch, cx = num voices
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

public d_init_
d_init_             proc
                    push    si
                    mov     si,offset _patch_res

                    push    bp
                    mov     bp,DInit
                    call    _driver_entry
                    pop     bp

                    ; ax = 0ffffh on error; by adding 1, we get 0 on failure or
                    ; non-zero on success (we don't care about freeing the memory)
                    inc     ax

                    pop     si
                    ret
d_init_             endp

invoke_drv          macro   num
                    push    si
                    mov     si,offset _sound_res        ; ds:si = sound resource

                    push    bp
                    mov     bp,num
                    call    _driver_entry
                    pop     bp

                    pop     si
                    endm

public d_terminate_
d_terminate_        proc
                    invoke_drv DTerminate
                    ret
d_terminate_        endp

public d_service_
d_service_          proc
                    invoke_drv DService
                    ret
d_service_          endp

public d_load_sound_
d_load_sound_       proc
                    invoke_drv DLoadSound
                    ret
d_load_sound_       endp

public d_set_volume
d_set_volume_       proc
                    invoke_drv DSetVolume
                    ret
d_set_volume_       endp

public d_stop_sound_
d_stop_sound_       proc
                    invoke_drv DStopSound
                    ret
d_stop_sound_       endp

_text               ends
                    end
