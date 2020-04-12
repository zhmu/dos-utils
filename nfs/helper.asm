; vim:set ts=8 sw=8 noet:

; converts dos-based fully-qualified filename to zero-terminated chunks
; entry: es:si -> fq path (updated), cx = number of path pieces
; exit:  carry=1 on success, si = new offset
;        carry=0 on failure, al = dos error code
; i.e. 'D:\FOO\BAR' --> 'D:\foo\bar', si = offset of 'foo\bar', cx=1
normalize_path:
	xor	cx,cx

	; we expect the first three chars to be ?:\ with our drive
	db	26h	; es:
	lodsb
	sub	al,'@'
	cmp	al,[drive_no]
	jz	np_drive_ok

	; drive not ours; reject
np_error:
	clc
	mov	al,15	; invalid drive
	ret

np_drive_ok:
	db	26h	; es:
	lodsb
	cmp	al,':'
	jne	np_error

	db	26h	; es:
	lodsb
	cmp	al,'\'
	jne	np_error

	; okay, prefix is okay - start changing stuff
	mov	bx,si
	mov	di,si

norm_1:
	db	26h	; es:
	lodsb
	or	al,al
	je	norm_end
	cmp	al,'\'
	jne	norm_2

	; separator here; means extra piece
	inc	cx

norm_2:
	call	normalize_char
	stosb
	jmp	norm_1

norm_end:
	stc
	mov	si,bx
	ret

normalize_char:
%if NFS_CASE==1
	cmp	al,'a'
	jl	norm_skip_ch
	cmp	al,'z'
	jg	norm_skip_ch

	; upper the char
	and	al,0dfh
%elif NFS_CASE==2
	cmp	al,'A'
	jl	norm_skip_ch
	cmp	al,'Z'
	jg	norm_skip_ch

	; lowercase the char
	or	al,20h
%endif
norm_skip_ch:
	ret

; check if char in al is fine
; returns: carry=1 if so, carry=0 otherwise
verify_char:
%if NFS_CASE==1
	cmp	al,'a'
	jl	verify_skip_ch
	cmp	al,'z'
	jg	verify_skip_ch

	; not ok
	clc
	ret
%elif NFS_CASE==2
	cmp	al,'A'
	jl	verify_skip_ch
	cmp	al,'Z'
	jg	verify_skip_ch

	; not ok
	clc
	ret
%endif
verify_skip_ch:
	; ok
	stc
	ret

; finds an available handle slot
; returns: carry=1 -> success, bx=index, di=address of slot
;          carry=0 -> failure, al = dos error code
find_available_slot:
	xor	bx,bx
	mov	cx,NUM_HANDLE_SLOTS
	mov	di,handle_slots

find_loop:
	mov	al,[ds:di]
	or	al,al
	jnz	find_loop_2

	; this one is unused!
	stc
	ret

find_loop_2:
	add	di,FH3SIZE+1
	inc	bx
	loop	find_loop

	mov	al,4		    ; too many open files
	clc
	ret

; obtain a directory handle slot
; returns: bx=index, si=address of slot
; this overwrites the oldest entry if none were found
; assumes: cs=ds=es
get_dir_slot:
	xor	bh,bh
	mov	bl,[next_dir_slot]

	; next_dir_dir = (next_dir_slot + 1) % NUM_DIR_SLOTS
	mov	dl,bl
	inc	dl
	cmp	dl,NUM_DIR_SLOTS
	jne	get_dir_slot_2

	xor	dl,dl

get_dir_slot_2:
	mov	[next_dir_slot],dl
	call	dir_slot_to_ptr

	; clear the directory slot
	mov	cx,DIR_SLOT_SIZE
	mov	di,si
	xor	al,al
	rep	stosb
	ret

; retrieves the offset of handle slot
; entry: bx = slot number to look up
; output: ds:si = handle data
slot_to_ptr:
	mov	ax,FH3SIZE+1
	mul	bx
	mov	bx,ax

	lea	si,[bx+handle_slots]
	ret

; retrieves the offset of dir handle slot
; entry: bx = slot number to look up
; output: ds:si = handle data
dir_slot_to_ptr:
	mov	ax,DIR_SLOT_SIZE
	mul	bx
	add	ax,dir_slots
	mov	si,ax
	ret

; converts unix timestamp in dx:ax to fat timestamp in ax
; TODO
unixtime_to_fat:
	xor	ax,ax
	ret
