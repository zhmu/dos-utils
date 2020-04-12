; vim:set ts=8 sw=8 noet:

; sda = #01687 interrup.g
sda_curdta  equ 0ch ; current DTA (disk transfer address)
sda_fn1	    equ 9eh
sda_sdb	    equ 19eh ; search data block (#01626)
sda_dsattr  equ	24dh ; directory search attributes
sda_oa_mode equ 24eh
sda_eopen_act	equ 2ddh    ; extended open action code (01770)
sda_eopen_attr	equ 2dfh    ; extended open attribute (01769)
sda_eopen_fmode	equ 2e1h    ; extended open file mode (AX=6c00h)

; 01626, interrupt.g
struc	    sdb
sdb_drive   resb    1	    ; 0
sdb_templ   resb    11	    ; 1
sdb_sattr   resb    1	    ; c
sdb_entry   resw    1	    ; d
endstruc

; redirect callbacks
f_md:
	; make directory; sda.fn1 contains the full path

	; obtain sda.fn1 and normalize
	les	si,[sda]
	lea	si,[si+sda_fn1]
	call	normalize_path
	jnc	f_error_with_code

	; resolve the path up until the new piece
	mov	dx,temp_fh
	call	nfs3_resolve_normalized
	jnc	f_error_with_code

	; now create the directory itself
	call	nfs3_mkdir
	cmc
	ret

; copies sda.fn1 filename piece to SFT
; input: ds:si = sda.fn1, es:di = output sft
copy_fn1_sft:
	; look for the last path component and put it in the SFT - we do
	; this before doing anything else as we'll replace the name inplace
	; later
	xor	bx,bx
.f_find_last:
	lodsb
	or	al,al
	jz	.f_find_last_end

	cmp	al,'\'
	jnz	.f_find_last

	mov	bx,si			; bx = last slash + 1
	jmp	.f_find_last

.f_find_last_end:
	; ds:bx = last path piece, es:di = sft
	add	di,20h			; es:di = sft.fcb

	; clear it out
	push	di
	mov	cx,11
	mov	al,' '
	rep	stosb
	pop	di

	; XXX this assumes the path piece is 8.3 max
	; now convert ASCIIZ-based filename in ds:bx to FCB-based in es:di
	mov	si,bx
	mov	cx,di
.r_fill_fcb:
	lodsb
	or	al,al
	jz	.r_fill_done
	cmp	al,'.'
	jne	.r_fill_copy

	mov	di,cx
	add	di,9			; go to extension piece
	jmp	.r_fill_fcb

.r_fill_copy:
	stosb
	jmp	.r_fill_fcb

.r_fill_done:
	ret

; 16 (open existing file), 17 (create/trunc file) and 2e (extended open file)
; all share sda.fn1 = filename, es:di = sft
;
; input: g_action = action bitfield (01770)
;        g_attr = file create attribute (01769)
;
g_action    db 0
g_attr	    db 0
g_openmode  db 0

generic_open_create:
	; obtain sda.fn1
	lds	si,[sda]
	lea	si,[si+sda_fn1]

%if DEBUG_REDIR_OPENCREATE
	mov	ax,0e00h + 'G'
	int	10h
	mov	al,'{'
	int	10h
	push	si
.p_loop:
	lodsb
	or	al,al
	jz	.p_done
	int	10h
	jmp	.p_loop

.p_done:
	pop	si
	mov	al,','
	int	10h
%endif

	push	di
	call	copy_fn1_sft

	; set ds=cs, es:si = sda.fn1
	pushm	es, cs
	pop	ds			; stack now contains di:es (sft to fill)
	les	si,[sda]
	lea	si,[si+sda_fn1]

	; normalize it
	call	normalize_path
	jnc	.fail_pop

	; resolve until the last piece
	mov	dx,temp_fh
	call	nfs3_resolve_normalized
	jnc	.fail_pop

	; TODO: find slot here so we don't accidently change something when out of handles

	; copy temp_fh to temp_fh2 - this is our base for create/trunc operations
	mov	ax,di
	pushm	es, ds
	pop	es
	mov	si,temp_fh
	mov	di,temp_fh2
	mov	cx,FH3SIZE+1
	rep	movsb
	pop	es

	mov	di,ax
	; di = final path piece - look the final piece up
	push	di
	mov	dx,temp_fh
	call	nfs3_lookup
	pop	di
	jc	.resolve_ok

%if DEBUG_REDIR_OPENCREATE
	; put '*' to show it does not yet exist
	mov	ax,0e00h + '*'
	int	10h
%endif

	; does not exist; supposed to?
	mov	al,[g_action]
	and	al,0f0h
	jz	.fail_not_exist
	cmp	al,010h
	je	.create

	; unknown action

.fail_not_exist:
	mov	al,2			; file not found
.fail_pop:
	popm	es, di
.fail:
%if DEBUG_REDIR_OPENCREATE
	push	ax
	mov	ax,0e00h + '-'
	int	10h
	pop	ax
%endif
	stc
	ret

.resolve_ok:
	; ok, this exists. supposed to?
	mov	al,[g_action]
	and	al,15
	cmp	al,1
	je	.open_it
	cmp	al,2
	jne	.fail_not_exist

.create:
	; need to replace the file
%if DEBUG_REDIR_OPENCREATE
	mov	ax,0e00h + 'T'		; truncating
	int	10h
%endif
	; copy temp_fh2 back to temp_fh - it could have been overwritten by a
	; successful lookup
	pushm	es, di, ds
	pop	es
	mov	si,temp_fh2
	mov	di,temp_fh
	mov	cx,FH3SIZE+1
	rep	movsb
	popm	di, es

	xor	bx,bx			; truncate
	mov	dx,temp_fh
	call	nfs3_create
	jnc	.fail_pop

.open_it:
	; XXX maybe use ACCESS before we continue?

	; now find a slot for the directory handle - we can't stash it in
	; the SFT because there isn't space :-(
	call	find_available_slot
	jnc	.fail_pop

	; copy filehandle to the slot in ds:di
	push	ds
	pop	es
	mov	si,temp_fh
	mov	cx,FH3SIZE+1
	rep	movsb

	; now we can fill out the SFT
	popm	es, di				; es:di = sft

	xor	dh,dh
	mov	dl,[g_openmode]
	mov	[es:di+2],dx			; open mode
	mov	[es:di+4],al			; file attr
	mov	[es:di+0bh],bx			; starting cluster -> slot

	; obtain the file stats
	mov	si,temp_fh
	push	di
	call	nfs3_getattr
	mov	bx,di				; bx = date
	pop	di
	jnc	.fail				; XXX fix error code

	mov	[es:di+11h],ax			; file size lo
	mov	[es:di+13h],dx			; file size hi
	;mov	cx,0821h			; 1:1:1
	mov	[es:di+0dh],cx			; file time
	;mov	bx,0221h			; 1-1-1981
	mov	[es:di+0fh],bx			; file date

	mov	ax,8040h
	or	al,[drive_no]
	mov	[es:di+5],ax			; device info
	xor	ax,ax
	mov	[es:di+7],ax			; drive header ptr hi
	mov	[es:di+9],ax			; drive header ptr lo
	xor	ax,ax
	xor	ax,ax
	mov	[es:di+15h],ax			; current offset lo
	mov	[es:di+17h],ax			; current offset hi

	; all is okay
%if DEBUG_REDIR_OPENCREATE
	mov	ax,0e00h + '+'
	int	10h
%endif
	clc
	ret

; copies sda.sda_oamode to g_openmode
copy_sda_oa_mode:
	push	es
	les	si,[sda]
	mov	al,[es:si+sda_oa_mode]		; open/access mode
	and	al,07fh
	mov	[g_openmode],al
	pop	es
	ret

; 16 - open existing file
f_open:
	xor	al,al
	mov	[g_attr],al
	call	copy_sda_oa_mode

	mov	al,01h				; open if exists
set_gaction_and_go:
	mov	[g_action],al
	jmp	generic_open_create

; 17 - CREATE/TRUNCATE FILE
f_create:
	mov	[g_attr],al
	call	copy_sda_oa_mode

	mov	al,012h			; truncate regardless
	jmp	set_gaction_and_go

; 1E - extended open file
f_eopen:
	mov	[g_attr],al

	; copy sda.sda_eopen_fmode, retrieve sda.sda_eopen_act
	push	es
	les	si,[sda]
	mov	al,[es:si+sda_eopen_fmode]
	mov	[g_openmode],al
	mov	al,[es:si+sda_eopen_act]
	pop	es

%if DEBUG_REDIR_OPENCREATE
	push	ax
	mov	bl,al
	mov	ax,0e00h + '<'
	int	10h
	mov	al,bl
	call	printhex
	mov	al,'>'
	int	10h
	pop	ax
%endif
	jmp	set_gaction_and_go

f_close:
	; we use the starting cluster as slot number in our handle
	; table, so obtain it and clear the handle
	mov	bx,[es:di+0bh]
	call	slot_to_ptr

	; zero the first byte; this is the length and what we use
	; to determine the validness
	xor	al,al
	mov	[ds:si],al

	clc
	ret

f_read:
	; on entry: es:di = sft, cx = count of bytes to read
%if DEBUG_REDIR_READ
	mov	ax,0e00h + '{'
	int	10h
	mov	al,'R'
	int	10h
	mov	ax,[ss:bp+sf_cx]	; bx = bytes to read
	call	printhex_word
	mov	ax,0e00h + '@'
	int	10h
	mov	ax,[es:di+17h]
	call	printhex_word
	mov	ax,[es:di+15h]
	call	printhex_word
	mov	ax,0e00h + ','
	int	10h
%endif

	; look up handle to ds:si
	mov	bx,[es:di+0bh]
	call	slot_to_ptr

	mov	bx,[ss:bp+sf_cx]	; bx = bytes to read
	xor	ax,ax
	mov	[ss:bp+sf_cx],ax	; number of bytes read

read_loop:
	; grab offset from sft in dx:ax
	mov	ax,[es:di+15h]
	mov	dx,[es:di+17h]

	pushm	es, di, bx, si

	; load disk transfer address from sda
	les	di,[sda]
	les	di,[es:di+sda_curdta]
	add	di,[ss:bp+sf_cx]
	jnc	read_no_seg_incr

	; handle overflow (can this happen?)
	int3
	push	ax
	mov	ax,es
	add	ax,1000h
	mov	es,ax
	pop	ax

read_no_seg_incr:
	mov	cx,bx			; bytes to read
	cmp	cx,1024
	jbe	read_size_ok

	mov	cx,1024

read_size_ok:
	call	nfs3_read
	mov	dl,bl		; eof flag
	popm	si, bx, di, es
	jnc	read_error

	; advance file pointer
	add	[es:di+15h],cx
	adc	word [es:di+17h],0

	add	[ss:bp+sf_cx],cx

	; check eof
	or	dl,dl
	jnz	read_eof

	sub	bx,cx
	jnz	read_loop

read_eof:
	; all set

%if DEBUG_REDIR_READ
	mov	ax,0e00h + '+'
	int	10h
	mov	ax,[ss:bp+sf_cx]	; bx = bytes to read
	call	printhex_word
	mov	ax,0e00h + '}'
	int	10h
%endif
	clc
	ret

read_error:
%if DEBUG_REDIR_READ
	push	ax
	mov	ax,0e00h + '-'
	int	10h
	mov	ax,[ss:bp+sf_cx]	; bx = bytes to read
	call	printhex_word
	mov	ax,0e00h + '}'
	int	10h
	pop	ax
%endif
	mov	word [ss:bp+sf_ax],ax
	stc
	ret

; 09 - write
f_write:
	; on entry: es:di = sft, cx = count of bytes to write
%if DEBUG_REDIR_WRITE
	mov	ax,0e00h + '{'
	int	10h
	mov	al,'W'
	int	10h
	mov	ax,[ss:bp+sf_cx]	; ax = bytes to write
	call	printhex_word
	mov	ax,0e00h + '@'
	int	10h
	mov	ax,[es:di+17h]
	call	printhex_word
	mov	ax,[es:di+15h]
	call	printhex_word
	mov	ax,0e00h + ','
	int	10h
%endif

	; look up handle to ds:si
	mov	bx,[es:di+0bh]
	call	slot_to_ptr

	mov	bx,[ss:bp+sf_cx]	; bx = bytes to write
	xor	ax,ax
	mov	[ss:bp+sf_cx],ax	; number of bytes written

write_loop:
	; grab offset from sft in dx:ax
	mov	ax,[es:di+15h]
	mov	dx,[es:di+17h]

	pushm	es, di, bx, si

	; load disk transfer address from sda
	les	di,[sda]
	les	di,[es:di+sda_curdta]
	add	di,[ss:bp+sf_cx]
	jnc	write_no_seg_incr

	; handle overflow (can this happen?)
	int3
	push	ax
	mov	ax,es
	add	ax,1000h
	mov	es,ax
	pop	ax

write_no_seg_incr:
	mov	cx,bx			; bytes to write
	cmp	cx,1024
	jbe	write_size_ok

	mov	cx,1024

write_size_ok:
	call	nfs3_write
	popm	si, bx, di, es
	jnc	write_error

	; advance file pointer
	add	[es:di+15h],cx
	adc	word [es:di+17h],0

	add	[ss:bp+sf_cx],cx

	sub	bx,cx
	jnz	write_loop

	; all done

%if DEBUG_REDIR_WRITE
	mov	ax,0e00h + '+'
	int	10h
	mov	ax,[ss:bp+sf_cx]	; bx = bytes to write
	call	printhex_word
	mov	ax,0e00h + '}'
	int	10h
%endif
	clc
	ret

write_error:
%if DEBUG_REDIR_WRITE
	push	ax
	mov	ax,0e00h + '-'
	int	10h
	mov	ax,[ss:bp+sf_cx]	; bytes to write
	call	printhex_word
	mov	ax,0e00h + '}'
	int	10h
	pop	ax
%endif
	mov	word [ss:bp+sf_ax],ax
	stc
	ret

f_chdir:
	; obtain sda.fn1, should be in format X:\...
	les	si,[sda]
	lea	si,[si+sda_fn1]

	; check if this is the root; we do not need to look anything
	; up if this is the case
	mov	al,[es:si+3]
	or	al,al
	jnz	f_chdir_notroot

	les	di,[drive_cds]
	add	di,3	; skip ?:\
	xor	al,al
	stosb
	ret

f_chdir_notroot:
	; normalize the path
	call	normalize_path
	jnc	f_error_with_code

	; resolve the full path
	inc	cx
	mov	dx,temp_fh
	pushm	si, cx
	call	nfs3_resolve_normalized
	popm	cx, si
	jnc	f_chdir_remap_error

	; obtain the file stats
	pushm	si, cx
	mov	si,temp_fh
	call	nfs3_getattr
	popm	cx, si
	jnc	f_error_with_code

	cmp	bx,2		    ; dir?
	je	chdir_type_ok

	mov	al,3		    ; path not found
	jmp	f_error_with_code

f_chdir_remap_error:
	cmp	al,2
	jne	f_chdir_remap_notfile
	inc	al		    ; path not found
f_chdir_remap_notfile:
	jmp	f_error_with_code

chdir_type_ok:
	; XXX ensure that this is an actual directory!
	push	es
	pop	ds
	les	di,[cs:drive_cds]
	; ds:si = normalized fn1, es:di = cds

	add	di,3	; skip ?:\
	mov	bx,cx

chdir_copy_loop:
	lodsb
	or	al,al
	jz	chdir_copy_piece_done

	stosb
	jmp	chdir_copy_loop

chdir_copy_piece_done:
	mov	al,'\'
	stosb
	loop	chdir_copy_loop

chdir_copy_done:
	; remove the final backslash
	dec	di
	xor	al,al
	stosb

	push	cs
	pop	ds
	ret

f_gattr:
	; obtain sda.fn1 and normalize
	les	si,[sda]
	lea	si,[si+sda_fn1]
	call	normalize_path
	jnc	f_error_with_code

	; resolve the path including the new piece
	inc	cx
	mov	dx,temp_fh
	call	nfs3_resolve_normalized
	jnc	f_error_with_code

	mov	si,dx
	call	nfs3_getattr

	cmp	bx,1				; NFS3REG ?
	je	f_gattr_file
	cmp	bx,2				; NFS3DIR ?
	je	f_gattr_dir

	mov	bx,4				; system attribute
	jmp	f_gattr_ok

f_gattr_file:
	xor	bx,bx
	jmp	f_gattr_ok

f_gattr_dir:
	mov	bx,10h				; directory attribute

f_gattr_ok:
	mov	word [ss:bp+sf_ax],bx	; attributes
	mov	word [ss:bp+sf_bx],dx	; size, hi
	mov	word [ss:bp+sf_di],ax	; size, lo
	mov	word [ss:bp+sf_cx],cx	; time
	mov	word [ss:bp+sf_dx],di	; date

	clc
	ret

f_ffirst:
	; sda.fn1
	; sda.sdb
	; sda.curr_dta
	; sda.srch_attr

	; fetch search_attr to al, and copy over to sdb
	les	si,[sda]
	mov	al,[es:si+sda_dsattr]		; search_attr
	lea	di,[si+sda_sdb+sdb_sattr]
	stosb

	push	ds
	pop	es			; cs=ds=es

	test	al,8			; vol label?
	jnz	ff_no_files             ; yes, reject for now

	; obtain sda.fn1 and normalize
	les	si,[sda]
	lea	si,[si+sda_fn1]
	call	normalize_path
	jnc	f_error_with_code

	; resolve the path up until the final piece, which is the
	; wildcard
	mov	dx,temp_fh
	call	nfs3_resolve_normalized
	jnc	f_error_with_code

	; es:di = final path piece (wildcard) - copy it into the SDB search template field
	push	es
	pop	ds
	mov	si,di			; ds:si = final path piece (wildcard)

	les	di,[cs:sda]
	lea	di,[di+sda_sdb+sdb_templ]	; es:di = sdb search template
	lea	bx,[di+8]			; extension part
	mov	cx,11

	; first clear
	pushm	di, cx
	mov	al, ' '
	rep	stosb
	popm	cx, di

	; copy
sdb_copy:
	lodsb
	cmp	al,'.'
	je	sdb_copy_dot
	stosb
	loop	sdb_copy
	jmp	sdb_copy_done

sdb_copy_dot:
	mov	di,bx
	mov	cx,3
	jmp	sdb_copy
sdb_copy_done:

	; TODO if there is no wildcard, we can just do a lookup

	; obtain a directory slot; this is used to store the
	; directory iteration status
	pushm	cs, cs
	popm	ds, es
	call	get_dir_slot		; bx=index, si=slot

	; stash the handle in the search data block
	push	es
	les	di,[sda]
	lea	di,[di+sda_sdb]		; es:si = search data block (g/#01626)
	mov	[es:di+sdb_entry],bx	; store handle
	pop	es

	; copy the file handle to the dir slot
	push	si
	mov	di,si
	mov	si,temp_fh
	mov	cx,FH3SIZE+1
	rep	movsb
	pop	si

f_do_readdir:
	xor	al,al
	mov	[f_find_flag],al

	mov	di,f_find_callback
	call	nfs3_readdir

	mov	al,[f_find_flag]
	or	al,al
	jz	ff_no_files

	; file found and returned
	clc
	ret

ff_no_files:
	mov	ax,18		; no more files
	mov	word [ss:bp+sf_ax],ax
	stc
	ret

; TODO I think this is used to stop after reporting the first file?
f_find_flag	db	0

f_fnext:
	; get search handle
	les	di,[sda]
	lea	di,[di+sda_sdb]		; es:si = search data block (g/#01626)
	mov	bx,[es:di+sdb_entry]	; fetch handle

	push	ds
	pop	es
	call	dir_slot_to_ptr

	jmp	f_do_readdir

f_find_callback:
	mov	al,[f_find_flag]
	or	al,al
	jz	f_find_callback_first

	; we are in the second stage - stop iteration now so we get the
	; correct cookie value
	stc
	ret

f_find_callback_first:
	; compute length; the flen field contains padding bytes
	mov	ax,[readdir_flen]
	cmp	ax,11
	jg	f_find_callback_skip	; no, skip

	; is the type sane?
	mov	ax,[readdir_type]
	cmp	ax,1
	je	f_find_callback_typeok
	cmp	ax,2
	jne	f_find_callback_skip	; not file/dir

f_find_callback_typeok:
%if DEBUG_REDIR_DIRLIST
	mov	cx,[readdir_len]
	mov	si,[readdir_fname]
	mov	ax,0e00h+'{'
	int	10h
rd_loop:
	lodsb
	or	al,al
	jz	rd_loop_x
	int	10h
	jmp 	rd_loop
rd_loop_x:

	mov	ax,0e00h+'}'
	int	10h
%endif
	; type is fine
	push	es


	les	di,[sda]
	lea	di,[di+sda_sdb+sdb_sattr]		; es:si = findfirst data block (g/#01626)
	mov	bl,[es:di]		; search_attr

	les	di,[sda]
	mov	bl,[es:di+sda_dsattr]	; search_attr
	lea	di,[di+sda_curdta]	; es:si = DTA
	les	di,[es:di]

	; initialize DTA
	mov	al,[drive_no]
	or	al,080h			; remote drive
	stosb
	add	di,11			; skip filename
	mov	al,bl
	stosb				; search attr
	add	di,2			; 0dh - keep handle (sdb_entry)
	mov	ax,0ffffh
	stosw				; 0fh - cluster number of dir
	xor	ax,ax
	stosw				; reserved 1
	stosw				; reserved 2

	; copy filename of entry we found
	pushm	di, bp
	call	convert_fname_to_msdos
	popm	bp, di
	jnc	f_find_callback_pop_es_skip

	; verify whether the filename (in es:di) matches the wildcard
	lds	si,[cs:sda]
	lea	si,[ds:si+sda_sdb+sdb_templ]	; ds:si = sdb search template
	push	di

	call	compare_fname_template
	pop	di

	push	cs
	pop	ds
	jnc	f_find_callback_pop_es_skip

	; update attribute
	add	di,11

	mov	al,10h			; attr: dir

	mov	dx,[readdir_type]
	cmp	dx,2			; dir?
	je	f_find_callback_copy_done_isdir

	xor	al,al			; attr:  none

f_find_callback_copy_done_isdir:
	stosb
	add	di,10			; skip reserved
	xor	ax,ax
	stosw				; time
	stosw				; date
	stosw				; cluster
	mov	ax,word [readdir_len]
	stosw
	mov	ax,word [readdir_len+2]
	stosw
	pop	es

%if DEBUG_REDIR_DIRLIST
	mov	ax,0e00h+'+'
	int     10h
%endif

	; increment state
	inc	byte [f_find_flag]
	stc
	ret

f_find_callback_pop_es_skip:
%if DEBUG_REDIR_DIRLIST
	mov	ax,0e00h+'-'
	int     10h
%endif
	pop	es

f_find_callback_skip:
	; keep going
	clc
	ret

; compares filename in es:di with wildcard in ds:si
; returns: carry=1 on match
compare_fname_template:
	mov	cx,11
cmp_loop:
	lodsb
	cmp	al,'?'
	je	cmp_wildcard

	mov	ah,[es:di]
	cmp	ah,al
	jne	cmp_not_eq

cmp_wildcard:
	inc	di
	loop	cmp_loop

	stc
	ret

cmp_not_eq:
	clc
	ret

; converts [readdir_len] byte filename in [readdir_fname] to MS-DOS 8.3 format in es:di
; returns: carry=1 on success
convert_fname_to_msdos:

	; clear out filename pieces
	push	di
	mov	cx,11
	mov	al,' '
	rep	stosb
	pop	di

	mov	si,[readdir_fname]
	mov	cx,[readdir_flen]

	; determine '.' position and count
	xor	ah,ah		    ; dot count
	xor	bp,bp		    ; last dot position
	pushm	cx, si
convert_fname_to_msdos_dotloop:
	lodsb
	cmp	al,'.'
	jne	cv_nondot

	mov	bp,si
	dec	bp
	inc	ah

cv_nondot:
	loop	convert_fname_to_msdos_dotloop
	popm	si, cx

	mov	al,'.'		; for stosb later
	cmp	ah,2
	jg	cv_reject	; reject >2 dots
	jne	cv_not_2dot

	; only scenario we'll accept two dots is if that is all we have
	cmp	cx,2
	jne	cv_reject

	; exactly two dots
	stosb
cv_1_dot:
	stosb
	stc
	ret

cv_not_2dot:
	cmp	ah,1
	jne	cv_no_dot

	cmp	cx,1
	je	cv_1_dot

	; just a single dot; do we have at most 8 chars before?
	mov	bx,bp
	sub	bx,si
	cmp	bx,8
	jg	cv_reject

	; do we have at most 3 chars after the dot?
	mov	dx,si
	add	dx,cx
	dec	dx
	sub	dx,bp
	cmp	dx,3
	jg	cv_reject

	; bx chars before the dot; dx chars after the dot
	push	di
	mov	cx,bx
	call	cv_piece
	pop	di
	inc	si ; skip dot
	add     di,8
	mov	cx,dx
	call	cv_piece
	jmp	cv_accept

cv_no_dot:
	; no dots whatsoever
	cmp	cx,8
	jg	cv_reject

	call	cv_piece
cv_accept:
	stc
	ret

cv_reject:
	clc
	ret

; converts cx bytes from ds:si -> es:di
cv_piece:
	lodsb
	call	verify_char
	jnc	cv_reject
	stosb
	loop	cv_piece
	ret


f_rd:
f_commit:
f_lock:
f_unlock:
f_sattr:
f_rename:
f_delete:
f_seek:
	mov     ax,0e3fh ; ?
	int     10h
	mov	ax,5 ; perm denied

f_error_with_code:
	mov	word [ss:bp+sf_ax],ax
	stc
	ret

f_info:
	mov	al,1
	mov	bx,1024
	mov	cx,512
	mov	dx,1234

	mov	word [ss:bp+sf_ax],ax
	mov	word [ss:bp+sf_bx],bx
	mov	word [ss:bp+sf_cx],cx
	mov	word [ss:bp+sf_dx],dx
	clc
	ret

; offsets within stack frame
sf_ax		equ	0ch
sf_bx		equ	0ah
sf_cx		equ	08h
sf_dx		equ	06h
sf_si		equ	04h
sf_di		equ	02h
sf_flags	equ	012h
sf_extra	equ	014h

funcmap:
	; bit 15=0: check CDS pointer in SDA
	; bit 15=1: check es:di SFT entry
	dw	0000h+f_rd	; 01 - remove dir
	dw	0000h
	dw	0000h+f_md	; 03 - make dir
	dw	0000h
	dw	0000h+f_chdir	; 05 - chdir
	dw	8000h+f_close	; 06 - close remote file
	dw	8000h+f_commit	; 07 - commit remote file
	dw	8000h+f_read	; 08 - read
	dw	8000h+f_write	; 09 - write
	dw	8000h+f_lock	; 0a - lock
	dw	8000h+f_unlock	; 0b - unlock
	dw	0000h+f_info	; 0c - disk info
	dw	0000h
	dw	0000h+f_sattr	; 0e - set attributes
	dw	0000h+f_gattr	; 0f - get attributes
	dw	0000h
	dw	0000h+f_rename	; 11 - rename
	dw	0000h
	dw	0000h+f_delete	; 13 - delete file
	dw	0000h
	dw	0000h
	dw	0000h+f_open	; 16 - open existing file
	dw	0000h+f_create	; 17 - create/truncate file
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h+f_ffirst	; 1b - find first matching file
	dw	0000h+f_fnext	; 1c - find next matching file
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h
	dw	8000h+f_seek	; 21 - seek from end of file
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h
	dw	0000h+f_eopen	; 2e - extended open
funcmap_end	equ $

int_2f:	; XXX we don't save flags here, as we expect the redirector
	; won't care about them either
	cmp	ax,11feh
	je	inst_check

	cmp	ah,11h		; redirector?
	jne	chain_2f	; no - ignore call

	or	al,al		; skip identify (XXX should we?)
	jz	chain_2f

	; XXX wonder if interrupts are enabled when we get here?
	;mov	cs:[saved_ss],ss
	;mov	cs:[saved_sp],sp
	;mov	sp,cs
	;mov	ss,sp
	;mov	sp,redir_stack	; ss:sp = cs:redir_stack

	; store everything
	pushm	ax, bx, cx, dx, si, di, bp
	mov	bp,sp		; bp = stored regs
	push	ds
	push	es
	push	cs
	pop	ds		; ds = cs

%if REDIR_DEBUG_CALLS
	pushm	ax, bx
	push	ax
	mov	ax,0e00h+'('
	int	10h
	pop	ax
	call	printhex
	mov	ax,0e00h+')'
	int	10h
	popm	bx, ax
%endif

	; calculate function offset
	xor	ah,ah
	dec	al		; skip identify
	shl	ax,1
	add	ax,funcmap
	cmp	ax,funcmap_end	; in range?
	jl	handle_func

	; not in range - give up
chain_2f_with_restore:
	pop	es
	pop	ds
	popm	bp, di, si, dx, cx, bx, ax

	; XXX hope interrupts are disabled here!
	;mov	sp,cs:[saved_ss]
	;mov	ss,sp
	;mov	sp,cs:[saved_sp]

chain_2f:
	db	0eah
old_2f	dd	0

inst_check:
	cmp	bx,5052h
	jne	chain_2f
	cmp	cx,5357h
	jne	chain_2f

	mov	ax,cs
	mov	dh,0feh
	mov	dl,[drive_no]
	iret

handle_func:
	mov	bx,ax
	and     bx,7fffh		; clear top bit
	mov	bx,word [bx]		; bx = stored func
	or	bx,bx
	jz	chain_2f_with_restore	; chain (no need to check more)

	push	cs
	pop	ds

	; determine if the call is for us
	test	bx,8000h	; bit 15 = 0 ?
	jz	check_cds	;  --> check cds
	and	bx,7fffh	; clear bit 15

	; need to check es:di here
	mov	al,[es:di+5]	; dev_info, lo byte
	and	al,1fh		; get drive
	cmp	al,[drive_no]	; our drive?
	jne	chain_2f_with_restore	; no, bail

	; our drive matches, can continue
	jmp	invoke_func

check_cds:
	; grab the current cds pointer from the sda
	pushm	es, si
	les	si,[sda]
	mov	ax,[es:si+282h]		; current cds, offs
	mov	dx,[es:si+284h]		; current cds, seg
	popm	si, es

	cmp	ax,word [drive_cds]
	jne	chain_2f_with_restore
	cmp	dx,word [drive_cds+2]
	jne	chain_2f_with_restore

	; our cds matches, we can continue

invoke_func:
	; clear carry of caller - we can then just use cf
	; as return value to see if we need to fail or not
	and	byte [ss:bp+sf_flags],0feh

	; grab word from stack, some functions need that
	mov	ax,word [ss:bp+sf_extra]

	; invoke our function
	call	bx
	jnc	no_error

	; set cf and copy ax over to caller stack
	or	byte [ss:bp+sf_flags],1
	mov	word [ss:bp+sf_ax],ax

no_error:
	pop	es
	pop	ds
	popm	bp, di, si, dx, cx, bx, ax
	iret

;saved_ss	dw	0
;saved_sp	dw	0

	;db	512 dup (?)
;redir_stack	db 0
