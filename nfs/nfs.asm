; vim:set ts=8 sw=8 noet:

RESTEXT		segment word public 'CODE'

include defines.inc
include macro.inc
include settings.inc

extern rpc_store_fh3: proc
extern rpc_call: proc
extern rpc_store_string: proc
extern rpc_load_fh3: proc
extern xmitbuf: proc
extern readdir_flen: word
extern readdir_fname: byte
extern readdir_len: dword
extern readdir_type: word
extern readdir_time: word
extern readdir_date: word
extern mount_fh: byte

public nfs3_write
public nfs3_lookup
public nfs3_create
public nfs3_resolve_normalized
public nfs3_getattr
public nfs3_mkdir
public nfs3_readdir
public nfs3_read

NFS3_DOS_GENERIC_ERROR equ 25 ; seek error
NFS3_DOS_NONSPECIFIC_ERROR equ 21 ; drive not ready

; nfs3_readdir:
; input: ds:si = dirslot pointer, cs:di = callback function
; output: carry=1 on success, carry=0 on failure, al = dos error code
; when the callback is invoked, the readdir_... files are filled out
; iteration is stopped when carry=1 on callback return
nfs3_readdir:
; TODO why does this save es:bp ????
	pushm	es, bp, di, si
	push    ds
	pop	es

	; make packet
	xor	bp,bp
	mov	di,offset xmitbuf+OFFSET_RPCARGS_NFS	; es:di = buffer

	; store directory handle - note: fh3 size is not guaranteed
	; so we need to calculate the offset to the cookie ourselves
	push	si
	call	rpc_store_fh3
	pop	si
	add	si,FH3SIZE+1

	; cookie
	mov	cx,COOKIE_SIZE
	rep	movsb

	; cookieverf
	mov	cx,COOKIEV_SIZE
	rep	movsb

	; dircount
	xor	ax,ax
	stosw
	mov	ax,2	; XXX this is just guesswork (512)
	stosw

	; maxcount
	xor	ax,ax
	stosw
	mov	ax,1024 ; avoid fragmentation ; pktbuf_len-OFFSET_UDPDATA	; skip udp/ip overhead
	xchg	ah,al
	stosw

	mov	bx,2		; service: nfs
	mov	ax,17		; procedure: readdirplus
	add	bp,(COOKIE_SIZE+COOKIEV_SIZE+8)
	call	rpc_call
	popm	di, bx, bp, es	; di = dirslot ptr, bx = callback
	jc	nfs3_readdir_ok

nfs3_readdir_fail:
	mov	al,NFS3_DOS_GENERIC_ERROR
nfs3_readdir_return_err:
	popm	si, di
	clc
	ret

nfs3_readdir_ok:
	pushm	bx, di ; save when we need to resubmit the call

	; we must have at least 4 bytes
	cmp	cx,4
	jl	nfs3_readdir_fail

	; grab status word
	lodsw
	or	ax,ax
	jnz	nfs3_readdir_fail
	lodsw
	or	ax,ax
	jz	nfs3_readdir_noerr

	xchg	ah,al
	call	nfs3_map_error
	jmp	nfs3_readdir_return_err

nfs3_readdir_noerr:

	; TODO check cx

	; see if there are directory attributes
	lodsw
	or	ax,ax
	jnz	nfs3_readdir_fail
	lodsw
	or	ax,ax
	jz	nfs3_readdir_skip_fa

	; file attributes are present; we just ignore them
	cmp	cx,84
	jl	nfs3_readdir_fail

	add	si,84
	sub	cx,84

nfs3_readdir_skip_fa:
	; cookie verf is here; we must store it
	pushm	cx, di
	add	di,FH3SIZE+1+COOKIE_SIZE
	mov	cx,COOKIEV_SIZE
	rep	movsb
	popm	di, cx

nfs3_readdir_loop:
	; check flag whether there are more entries
	lodsw
	mov	dx,ax
	lodsw
	or	dx,ax
	jz	nfs3_readdir_eod

	; now we are parsing entryplus3 - fileid
	cmp	cx,8
	jl	nfs3_readdir_fail
	add	si,8
	sub	cx,8			; skip fileid

	; filename
	lodsw
	or	ax,ax
	jnz	nfs3_readdir_fail	; filename >255; this is likely a bug
	lodsw
	xchg	ah,al
	mov	word ptr [readdir_flen],ax	; store length
	mov	word ptr [readdir_fname],si	; store name

	xor	dx,dx
	mov	word ptr [readdir_len],dx
	mov	word ptr [readdir_len+2],dx

	mov	dx,ax
	add	si,ax			; skip name

	; deal with padding - we must remain 4 byte aligned
	and	dx,3
	jz	nfs3_readir_nopad

	; skip padding bytes
	mov	ax,4
	sub	ax,dx
	add	si,ax

nfs3_readir_nopad:
	; copy cookie over to handle; so we continue from this entry
	; onwards next time
	pushm	di, cx
	add	di,FH3SIZE+1
	mov	cx,COOKIE_SIZE
	rep	movsb
	popm	cx, di
	; TODO fix length

	; check length for post_op_attr flag
	cmp	cx,4
	jl	nfs3_readdir_fail
	sub	cx,4

	; post_op_attr flag
	lodsw
	mov	dx,ax
	lodsw
	or	dx,ax
	jz	nfs3_readdir_no_postop_attr

	cmp	cx,84
	jl	nfs3_readdir_fail

	pushm	bx, cx, di
	call	nfs3_parse_fattr
	mov	word ptr [readdir_type],bx
	mov	word ptr [readdir_len+2],dx
	mov	word ptr [readdir_len],ax
	mov	word ptr [readdir_time],cx
	mov	word ptr [readdir_date],di
	popm	di, cx, bx
	sub	cx,84

nfs3_readdir_no_postop_attr:
	; check length for post_op_fh3 flag
	cmp	cx,4
	jl	nfs3_readdir_fail
	sub	cx,4

	; post_op_fh3 flag
	lodsw
	mov	dx,ax
	lodsw
	or	dx,ax
	jz	nfs3_readdir_no_postop_fh3

	; get fh3 length
	lodsw
	or	ax,ax
	jnz	nfs3_readdir_fail
	lodsw
	xchg	ah,al
	cmp	cx,ax
	jl	nfs3_readdir_fail

	; skip the fh3 - we don't need it here
	sub	cx,ax
	add	si,ax

nfs3_readdir_no_postop_fh3:
	; invoke the callback
	pushm	di, si, bx, cx
	call	bx
	popm	cx, bx, si, di

	; next entry
	jnc	nfs3_readdir_loop

nfs3_readdir_enough:
	; callback has had enough
	popm	si, di
	ret

nfs3_readdir_eod:
	; end of directory - are there more entries?
	lodsw
	mov	dx,ax
	lodsw
	or	dx,ax
	jnz	nfs3_readdir_enough

	; more entries possible; restart the whole process - cookie has been updated
	popm	si, di
	jmp	nfs3_readdir

; nfs3_lookup: performs a lookup call on a given file
; input: ds:dx = fh3, es:di = filename
; output: carry=1 on success -> ds:dx updated
;         carry=0 on failure -> al dos error code
nfs3_lookup:
	pushm	bp, es, dx, es, di, cs
	pop	es

	; make packet
	mov	di,offset xmitbuf+OFFSET_RPCARGS_NFS	; es:di = @data:buffer
	xor	bp,bp

	; store directory handle
	mov	si,dx			; ds:si = fh3
	call	rpc_store_fh3

	; store filename
	popm	si, ds		; ds:si = filename (es = data)
	mov	bl,'\'
	call	rpc_store_string

	push	cs
	pop	ds		; ds=es=data

	; off it goes
	mov	bx,2		; service: nfs
	mov	ax,3		; procedure: lookup
	call	rpc_call
	pop	dx		; retrieve fh buffer
	jc	nfs3_lookup_ok

nfs3_lookup_fail:
	mov	al,NFS3_DOS_GENERIC_ERROR
nfs3_lookup_return_err:
	popm	es, bp
	clc
	ret

nfs3_lookup_ok:
	; we must have at least 4 bytes
	cmp	cx,4
	jl	nfs3_lookup_fail

	; fetch result
	lodsw			; hi word must be zero
	or	ax,ax
	jnz	nfs3_lookup_fail
	lodsw			; lo word must be zero too
	or	ax,ax
	jz	nfs3_lookup_noerr

	xchg	ah,al
	call	nfs3_map_error
	jmp	nfs3_lookup_return_err

nfs3_lookup_noerr:
	; we should have a fh3 now
	sub	cx,4

	mov	di,dx
	call	rpc_load_fh3	; sets carry for us
	popm	es, bp
	ret

; nfs3_read: reads from a fh3
; input: ds:si = fh3, dx:ax = offset, cx = length, es:di = buffer
; output: carry=1 on success -> cx = amount read, bl = eof
nfs3_read:
	pushm	bp, es, di, ds
	pop	es

	; make packet
	xor	bp,bp
	mov	di,offset xmitbuf+OFFSET_RPCARGS_NFS	; es:di = buffer

	; store directory handle
	pushm	cx, ax, dx
	call	rpc_store_fh3

	; store offset (top 32 bits are always zero)
	xor	ax,ax
	stosw
	stosw
	pop	ax		; was caller dx
	xchg	ah,al
	stosw
	pop	ax		; was caller ax
	xchg	ah,al
	stosw

	; store count
	xor	ax,ax
	stosw
	pop	ax		; was caller cx
	xchg	ah,al
	stosw

	; off it goes
	add	bp,12
	mov	bx,2		; service: nfs
	mov	ax,6		; procedure: read
	call	rpc_call
	popm	di, es, bp
	jc	nfs3_read_ok

nfs3_read_err:
	mov	al,NFS3_DOS_GENERIC_ERROR
nfs3_read_return_err:
	clc
	ret

nfs3_read_ok:
	; sanity check on the returned length
	cmp	cx,16
	jl	nfs3_read_err
	sub	cx,12

	; get the status
	lodsw
	or	ax,ax
	jnz	nfs3_read_err
	lodsw
	or	ax,ax
	jz	nfs3_read_errok

	xchg	ah,al
	call	nfs3_map_error
	jmp	nfs3_read_return_err

nfs3_read_errok:
	; see if there are file attributes
	lodsw
	or	ax,ax
	jnz	nfs3_read_err
	lodsw
	or	ax,ax
	jz	nfs3_read_skip_fa

	; file attributes are present; we just ignore them
	cmp	cx,84
	jl	nfs3_read_err

	add	si,84
	sub	cx,84

nfs3_read_skip_fa:
	lodsw			; count, hi word
	or	ax,ax
	jnz	nfs3_read_err
	lodsw
	xchg	ah,al
	mov	cx,ax		; count, lo word XXX check this

	; eof flag
	lodsw
	or	ax,ax
	jnz	nfs3_read_err
	lodsw
	mov	bl,ah		; eof flag

	; now we have the data itself
	lodsw
	or	ax,ax
	jnz	nfs3_read_err
	lodsw
	xchg	ah,al
	cmp	ax,cx		; compare with length above
	jne	nfs3_read_err

	; finally, copy the data
	push	cx
	rep	movsb
	pop	cx
	stc
	ret

; nfs3_write: writes to a fh3
; input: ds:si = fh3, dx:ax = offset, cx = length, es:di = buffer
; output: carry=1 on success -> cx = amount written
nfs3_write:
	pushm	bp, es, di, ds
	pop	es

	; make packet
	mov	bp,cx
	add	bp,20
	mov	di,offset xmitbuf+OFFSET_RPCARGS_NFS	; es:di = buffer

	; store directory handle
	pushm	cx, ax, dx
	call	rpc_store_fh3

	; store offset (top 32 bits are always zero)
	xor	ax,ax
	stosw
	stosw
	pop	ax		; was caller dx
	xchg	ah,al
	stosw
	pop	ax		; was caller ax
	xchg	ah,al
	stosw

	; length
	pop	cx		; was caller cx
	xor	ax,ax
	stosw
	mov	ax,cx
	xchg	ah,al
	stosw

	; stable field
	xor	ax,ax
	stosw
	stosw

	; data length
	stosw			; hi word is always zero
	mov	ax,cx
	xchg	ah,al
	stosw

	; now the data itself
	popm	si, ds		; was caller es:di
	mov	ax,cx
	rep	movsb

	push	cs
	pop	ds		; ds = cs

	; padding?
	and	al,3
	jz	nfs3_write_nopad

	mov	cx,4
	sub	cl,al
	add	bp,cx		; padding bytes
	xor	al,al
	rep	stosb

nfs3_write_nopad:
	; off it goes
	mov	bx,2		; service: nfs
	mov	ax,7		; procedure: write
	call	rpc_call
	push	cs
	popm	ds, bp		; restore ds, bp
	jc	nfs3_write_ok

nfs3_write_err:
	mov	al,NFS3_DOS_GENERIC_ERROR
nfs3_write_return_err:
	clc
	ret

nfs3_write_ok:
	cmp	cx,16
	jl	nfs3_write_err

	; already remove required fields from length
	sub	cx,16

	; fetch result code
	lodsw
	or	ax,ax
	jnz	nfs3_write_err
	lodsw
	or	ax,ax
	jz	nfs3_write_noerr

	xchg	ah,al
	call	nfs3_map_error
	jmp	nfs3_write_return_err

nfs3_write_noerr:
	; ignore weak consistency data; we don't cache anything anyway
	lodsw
	or	ax,ax
	jnz	nfs3_write_err
	lodsw
	or	ax,ax
	jz	nfs3_write_no_preattr

	; skip contents
	cmp	cx,24
	jl	nfs3_write_err
	add	si,24
	sub	cx,24

nfs3_write_no_preattr:
	; is there post op attr data?
	lodsw
	or	ax,ax
	jnz	nfs3_write_err
	lodsw
	or	ax,ax
	jz	nfs3_write_no_postattr

	; skip contents
	cmp	cx,84
	jl	nfs3_write_err
	add	si,84
	sub	cx,84

nfs3_write_no_postattr:
	; fetch the length
	lodsw
	or	ax,ax
	jnz	nfs3_write_err
	lodsw
	xchg	ah,al
	mov	cx,ax

	; all done (we ignore the other fields)
	stc
	ret

; nfs3_create: creates/truncate a given file
; input: ds:dx = fh3, es:di = filename
;        bl = 0: truncate (unchecked)
;             1: fail if exist (guarded)
; output: carry=1 on success -> dx filled out
;         carry=0 on failure -> al dos error code
nfs3_create:
	pushm	es, dx, bx, es, di, cs
	pop	es

	; make packet
	mov	bp,32
	mov	di,offset xmitbuf+OFFSET_RPCARGS_NFS

	; store file handle
	mov	si,dx
	call	rpc_store_fh3

	; store filename
	popm	si, ds		; ds:si = filename (es = data)
	xor	bl,bl
	call	rpc_store_string

	push	cs
	pop	ds		; ds=es=data

	; type = guarded
	xor	ax,ax
	stosw
	pop	bx
	xor	al,al
	mov	ah,bl
	stosw

	; we want to specify the mode
	xor	ax,ax
	stosw
	mov	ax,0100h
	stosw
	; mode is 0666 XXX and should be configurable
	xor	ax,ax
	stosw
	mov	ax,0b601h
	stosw

	; zero out all remaining attributes; the server may fill them out
	xor	ax,ax
	mov	cx,11
	rep	stosw

	; off it goes
	mov	bx,2		; service: nfs
	mov	ax,8		; procedure: create
	call	rpc_call
	pop	dx
	jc	nfs3_create_ok

nfs3_create_err:
	mov	al,NFS3_DOS_GENERIC_ERROR
nfs3_create_return_err:
	pop	es
	clc
	ret

nfs3_create_ok:
	cmp	cx,8
	jl	nfs3_create_err

	; obtain status
	lodsw
	or	ax,ax
	jnz	nfs3_create_err
	lodsw
	or	ax,ax
	jz	nfs3_create_errok

	xchg	ah,al
	call	nfs3_map_error
	jmp	nfs3_create_return_err

nfs3_create_errok:
	; is there a fh3?
	lodsw
	or	ax,ax
	jnz	nfs3_create_err
	lodsw
	or	ax,ax
	jz	nfs3_create_err

	; fetch fh3
	sub	cx,8
	mov	di,dx
	call	rpc_load_fh3	; don't care about other data (+sets cf for us)
	pop	es
	ret

; nfs3_mkdir: create a directory
; input: ds:dx = fh3, es:di = dirname
; output: carry=1 on success -> dx updated
;         carry=0 on failure -> al dos error code
nfs3_mkdir:
	pushm	es, dx, es, di, cs
	pop	es

	; make packet
	mov	bp,28
	mov	di,offset xmitbuf+OFFSET_RPCARGS_NFS	; es:di = buffer

	; store file handle
	mov	si,dx
	call	rpc_store_fh3

	; store filename
	popm	si, ds		; ds:si = filename (es = data)
	xor	bl,bl
	call	rpc_store_string

	push	cs
	pop	ds		; ds=es=data

	; we want to specify the mode
	xor	ax,ax
	stosw
	mov	ax,0100h
	stosw
	; mode is 0777 XXX and should be configurable
	xor	ax,ax
	stosw
	mov	ax,0ff01h
	stosw

	; zero out all remaining attributes; the server may fill them out
	xor	ax,ax
	mov	cx,11
	rep	stosw

	; off it goes
	mov	bx,2		; service: nfs
	mov	ax,9		; procedure: mkdir
	call	rpc_call
	pop	dx
	jc	nfs3_create_ok	; reply is identical for files
	pop	es
	ret

; nfs3_remove: remove a file
; input: si = fh3, di = name
; output: carry=1 on success
;         carry=0 on failure -> al dos error code
nfs3_remove:
	mov	bx,12		; procedure: remove
	jmp	nfs3_remove_generic

; nfs3_rmdir: removes a directory
; input: si = fh3, di = name
; output: carry=1 on success
;         carry=0 on failure -> al dos error code
nfs3_rmdir:
	mov	bx,13		; procedure: rmdir

; nfs3_remove_generic: remove a file or directory
; input: si = fh3, di = name, bx = procedure call
; output: carry=1 on success
;         carry=0 on failure -> al dos error code
nfs3_remove_generic:
	push	di

	; make packet
	xor	bp,bp
	mov	di,offset xmitbuf+OFFSET_RPCARGS_NFS

	; store file handle
	call	rpc_store_fh3

	; store filename
	pop	si		; retrieves filename
	xor	bl,bl
	call	rpc_store_string

	; off it goes
	mov	ax,bx		; procedure
	mov	bx,2		; service: nfs
	call	rpc_call
	jc	nfs3_remove_ok

nfs3_remove_err:
	mov	al,NFS3_DOS_GENERIC_ERROR
nfs3_remove_return_err:
	clc
	ret

nfs3_remove_ok:
	cmp	cx,4
	jl	nfs3_remove_err

	lodsw
	or	ax,ax
	jnz	nfs3_remove_err
	lodsw
	or	ax,ax
	jz	nfs3_remove_errok

	xchg	ah,al
	call	nfs3_map_error
	jmp	nfs3_remove_return_err

nfs3_remove_errok:
	; all set; we care not about the contents of the packet
	stc
	ret

; nfs3_rename: renames a file or directory
; input: si = fh3, dx = source, di = dest
; output: carry=1 on success
;         carry=0 on failure -> al dos error code
nfs3_rename:
	push	di

	; make packet
	xor	bp,bp
	mov	di,offset xmitbuf+OFFSET_RPCARGS_NFS

	; store file handle for source filename
	push	si
	call	rpc_store_fh3

	; store source filename
	mov	si,dx
	xor	bl,bl
	call	rpc_store_string

	; store file handle for dest filename
	pop	si
	call	rpc_store_fh3

	; store destination filename
	pop	si
	xor	bl,bl
	call	rpc_store_string

	; off it goes
	mov	bx,2		; service: nfs
	mov	ax,14		; procedure: rename
	call	rpc_call
	jc	nfs3_rename_ok

nfs3_rename_err:
	mov	al,NFS3_DOS_GENERIC_ERROR
nfs3_rename_return_err:
	clc
	ret

nfs3_rename_ok:
	cmp	cx,4
	jl	nfs3_rename_err

	; fetch status
	lodsw
	or	ax,ax
	jnz	nfs3_rename_err
	lodsw
	or	ax,ax
	jz	nfs3_rename_noerr

	xchg	ah,al
	call	nfs3_map_error
	jmp	nfs3_rename_return_err

nfs3_rename_noerr:
	; all went ok
	stc
	ret

; resolves a normalized path to a file handle
; input: es:si = normalized path, cx = #path pieces, ds:dx = output fh3
; output: carry=1 -> di=final path piece
;         carry=0 on failure -> al dos error code
nfs3_resolve_normalized:
	; first copy the mount_fh to the output
	; this is our starting point, which we will
	; overwrite for subsequent path pieces
	pushm	cx, si, es, ds
	pop	es
	mov	di,dx			; es:di = ds:dx
	mov	si,offset mount_fh	; ds:si = mount_fh
	mov	cx,FH3SIZE
	rep	movsb
	popm	es, di, cx		; di = caller si

	jcxz	nfs3_resolve_ok

nfs3_resolve_loop:
	; ds:dx = fh to start at, es:di = source
	pushm	cx, dx, si, di, es
	call	nfs3_lookup
	popm	es, di, si, dx, cx
	jnc	nfs3_resolve_fail

	; now skip the string until the next piece
nfs3_resolve_find_loop:
	mov	al,[es:di]
	inc	di
	cmp	al,'\'
	je	nfs3_resolve_find_loop_exit
	or	al,al
	jne	nfs3_resolve_find_loop

nfs3_resolve_find_loop_exit:
	loop	nfs3_resolve_loop

nfs3_resolve_ok:
	; all set; di is final piece now
	stc
	ret

nfs3_resolve_fail:
	; note: we assume cf is clear here
	ret

; nfs3_getattr: retrieve attributes from file handle
; input: ds:si = fh3
; output: carry=1 on success -> bx=type, dx:ax=size, cx=time, di=date
;         carry=0 on failure -> al dos error code
nfs3_getattr:
	pushm	es, bp, ds
	pop	es

	; make packet
	xor	bp,bp
	mov	di,offset xmitbuf+OFFSET_RPCARGS_NFS	; es:di = buffer

	; store directory handle
	call	rpc_store_fh3

	; off it goes
	mov	bx,2		; service: nfs
	mov	ax,1		; procedure: getattr
	call	rpc_call
	popm	bp, es
	jc	nfs3_getattr_ok

nfs3_getattr_error:
	mov	al,NFS3_DOS_GENERIC_ERROR
nfs3_getattr_return_error:
	clc
	ret

nfs3_getattr_ok:
	; fetch result
	lodsw			; hi word must be zero
	or	ax,ax
	jnz	nfs3_getattr_error
	lodsw			; lo word must be zero too
	or	ax,ax
	jz	nfs3_getattr_noerr

	xchg	ah,al
	call	nfs3_map_error
	jmp	nfs3_getattr_return_error

nfs3_getattr_noerr:
	sub	cx,4

	; sanity check on the returned lengt
	cmp	cx,84
	jl	nfs3_getattr_error

	call	nfs3_parse_fattr
	stc
	ret

; input: ds:si = fattr3
; output: type=bx, size=dx:ax, time=cx, date=di, si updated past fattr3
nfs3_parse_fattr:
	; ok, we care about the type (bx), size (dx:ax) and
	; timestamp. we stick to mtime (cx)
	lodsw
	lodsw
	xchg	ah,al
	mov	bx,ax			; bx = type (top 16 bits ignored)
	add	si,16			; skip mode/nlink/uid/gid
	lodsw
	lodsw				; ignore top 32 bits
	lodsw
	xchg	ah,al
	mov	dx,ax
	lodsw
	xchg	ah,al
	push	ax			; dx:ax = length
	add	si,40			; skip used/rdev/fsid/fileid/atime

	; we are at the mtime now
	push	dx
	lodsw
	xchg	ah,al
	mov	dx,ax
	lodsw
	xchg	ah,al
	; TODO: convert dx:ax to something reasonable
	popm	dx, ax

	; TODO: just yield cx:di as zero
	xor	cx,cx
	xor	di,di

	add	si,12			; skip mtime nanoseconds, ctime
	ret

; maps error in [al] to error code in [al] (assumed ds is correct)
; destroys: bl, si
nfs3_map_error:
	mov	bl,al
	mov	si,nfs3_error_tab
nfs3_map_loop:
	lodsb
	cmp	al,bl
	je	nfs3_map_ok

	or	al,al
	lodsb
	jne	nfs3_map_loop

	; map unknown errors here
	mov	al,NFS3_DOS_NONSPECIFIC_ERROR

nfs3_map_ok:
	lodsb
	ret

; nfs3 code (enum nfsstat3), dos code (table 01680, interrup.g)
nfs3_error_tab:
    db 1, 5	    ; NFS3ERR_PERM, permission denied
    db 2, 2	    ; NFS3ERR_NOENT, file not found
    db 5, 23	    ; NFS3ERR_IO, data error
    db 6, 23	    ; NFS3ERR_NXIO, data error
    db 13, 5	    ; NFS3ERR_ACCESS, permission denied
    ;db 17, 0	    ; NFS3ERR_EXIST, <handled internally>
    db 20, 3	    ; NFS3ERR_NOTDIR, path not found
    db 21, 2	    ; NFS3ERR_ISDIR, file not found
    db 22, 31	    ; NFS3ERR_INVAL, general failure
    db 28, 39	    ; NFS3ERR_NOSPC, insufficient disk space
    db 30, 19	    ; NFS3ERR_ROFS, disk write protected
    db 70, 2	    ; NFS3ERR_STALE, file not found
    db 0, 0

RESTEXT	ends
	end
