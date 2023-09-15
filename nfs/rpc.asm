; vim:set ts=8 sw=8 noet:

RESTEXT		segment word public 'CODE'

include defines.inc
include macro.inc
include settings.inc

extern recv_len: word
extern udp_send: proc
extern rpc_portmap: word
extern rpc_versionmap: word
extern rpc_portmap: word
extern rpc_progmap: word
extern xid: dword
extern xmitbuf: byte
extern recvbuf: byte

public rpc_call
public rpc_load_fh3
public rpc_store_string
public rpc_store_fh3

if RPC_SHOW_INDICATOR
rpc_indicator_seg:	dw	0xb800
rpc_indicator_off:	dw	(78*2)
rpc_indicator_prev:	dw	0
endif

; NOTE: ASSUMES ds=es=data !!!
; rpc_call: bp = length, bx = service, ax = procedure
;           data must be present at xmitbuf+OFFSET_RPCARGS
; returns: carry=1 on success -> ds:si = reply, cx = length
; corrupts: ax, bx, cx, dx, si, di
rpc_call:
	; fetch program/port number
	shl	bx,1
	mov	dx,[rpc_portmap+bx]		; dx = port
	lea	cx,[rpc_versionmap+bx]	; cx = version
	shl	bx,1
	lea	si,[rpc_progmap+bx]	; si = rpc progname

	; increment xid
	inc	word ptr [xid+0]
	adc	word ptr [xid+2],0

	push	ax				; store procedure

	; start crafting the packet
	mov	di,offset xmitbuf+OFFSET_UDPDATA	; frame+ip+udp header

	mov	ax,word ptr [xid+0]		; xid lo
	stosw
	mov	ax,word ptr [xid+2]		; xid hi
	stosw

	; call
	xor	ax,ax
	stosw
	stosw

	; version 2
	stosw
	mov	ax,0200h
	stosw

	; program number, already in si
	movsw
	movsw

	; version number
	xor	ax,ax
	stosw
	mov	si,cx
	movsw

	; procedure number
	xor	ax,ax
	stosw
	pop	ax
	xchg	ah,al
	stosw

	cmp	bx,8			; nfs?
	jne	rpc_cred_null		; no, use AUTH_NULL auth

	; credentials
	xor	ax,ax
	stosw
	mov	ax,0100h
	stosw				; AUTH_UNIX
	xor	ax,ax
	stosw
	mov	ax,1400h
	stosw				; length
	xor	ax,ax

	stosw
	stosw				; stamp 0
	stosw
	stosw				; no machinename
	stosw
	stosw				; uid 0
	stosw
	stosw				; gid 0
	stosw
	stosw				; no extra ids

	add	bp,20			; extra headers
	jmp	rpc_set_verifier

rpc_cred_null:
	; credentials
	xor	ax,ax
	stosw				; AUTH_NULL
	stosw
	stosw				; length is 0
	stosw

rpc_set_verifier:
	; verifier
	stosw				; AUTH_NULL
	stosw
	stosw				; length is 0
	stosw

	; parameters must be here, filled out by caller
	xor	ax,ax
	mov	[recv_len],ax

	; call it!
	; bx was our portmap offset; we use it as our port too
	add	bx,100
	add	bp,40			; rpc headers
	call	udp_send

	; now we have to wait for the reply ...

	; TODO: we should also handle errors here more
	; sanely - maybe via timeout? retransmit?
if RPC_SHOW_INDICATOR
	push	es
	mov	ax,[rpc_indicator_seg]
	mov	es,ax
	mov	di,[rpc_indicator_off]
	mov	ax,[es:di]
	mov	[rpc_indicator_prev],ax
	mov	ax,04d00h + 'N'
	stosw
	pop	es
endif

	pushf
	sti
	jmp	rpc_reply_wait

rpc_reply_reset:
	mov	ax,0e7ch ; '|'
	int	10h
	xor	ax,ax
	mov	[recv_len],ax

rpc_reply_wait:
	mov	dx,[recv_len]
	or	dx,dx
	jz	rpc_reply_wait

	; sanity check on the length
	cmp	dx,24
	jl	rpc_reply_reset		; discard if too short

	; parse the reply
	mov	si,offset recvbuf
	mov	di,offset xid
	mov	cx,2
	repe	cmpsw
	jne	rpc_reply_reset		; if not equal, discard packet

	; this must be a reply
	lodsw
	or	ax,ax
	jne	rpc_reply_reset
	lodsw
	cmp	ax,0100h
	jne	rpc_reply_reset

	; restore interrupts
	popf

if RPC_SHOW_INDICATOR
	; restore what was there
	push	es
	mov	ax,[rpc_indicator_seg]
	mov	es,ax
	mov	di,[rpc_indicator_off]
	mov	ax,[rpc_indicator_prev]
	stosw
	pop	es
endif

	; is the reply accepted?
	lodsw
	or	ax,ax
	jne	rpc_rejected
	lodsw
	or	ax,ax
	jne	rpc_rejected

	; verifier data
	lodsw
	lodsw
	lodsw			; length
	or	ax,ax
	jne	rpc_rejected
	lodsw			; length lo
	xchg	ah,al
	add	si,ax		; skip it

	; accept status
	lodsw
	or	ax,ax
	jne	rpc_rejected
	lodsw
	or	ax,ax
	jne	rpc_rejected

	; reply seems ok; calculate the length
	mov	cx,si
	sub	cx,offset recvbuf	; cx = amount we parsed
	sub	dx,cx			; dx = total - cx
	mov	cx,dx

	stc
	ret

rpc_rejected:
	clc
	ret

; rpc_store_fh3: stores the filehandle in si
; input:  ds:si = fh3, es:di = buffer, bp = length so far
; output: di, bp updated
; corrupts: ax, cx, si
rpc_store_fh3:
	; retrieve handle length
	xor	cx,cx
	lodsb
	mov	cl,al

	; update output length
	add	bp,4
	add	bp,cx

	; store dir handle length
	xor	ax,ax
	stosw
	mov	ah,cl
	stosw

	; copy dir handle contents XXX padding?
	rep	movsb
	ret

; rpc_load_fh3: retrieve the filehandle from si
; input: ds:si = rpc buffer, cx = remaining length, es:di = fh3 buffer
; output: carry=1 on success -> es:di valid
;
rpc_load_fh3:
	; fetch the filehandle length
	lodsw
	or	ax,ax
	jne	rpc_load_fh3_err
	lodsw
	xchg	ah,al
	cmp	ax,FH3SIZE
	jg	rpc_load_fh3_err

	; ensure we have this much available
	cmp	cx,ax
	jl	rpc_load_fh3_err

	; store the length byte
	stosb

	; copy the mount file handle
	push	cx
	mov	cx,ax
	rep	movsb
	pop	cx
	sub	cx,ax

	stc
	ret

rpc_load_fh3_err:
	clc
	ret

; rpc_store_string: stores the string in si
; input:  ds:si = string, es:di = buffer, bp = length so far, bl = extra terminator char
;         (0 is always a terminator char)
; output: di, bp updated
; corrupts: ax, cx, dx
rpc_store_string:
	push	si
	; calculate string length in dx
	xor	dx,dx
rpc_strlen_loop:
	lodsb
	or	al,al
	jz	rpc_strlen_end
	cmp     al,bl
	jz	rpc_strlen_end

	inc	dx
	jmp	rpc_strlen_loop

rpc_strlen_end:
	pop	si

	; update lengths so far
	add	bp,dx
	add	bp,4

	; store filename length
	xor	ax,ax
	stosw
	mov	ax,dx
	xchg	ah,al
	stosw

	; store filename
	mov	cx,dx
	rep	movsb

	; handle padding
	and	dl,3
	jz	rpc_store_string_nopad

	mov	cx,4
	sub	cl,dl
	add	bp,cx		; padding bytes
	xor	al,al
	rep	stosb

rpc_store_string_nopad:
	ret

RESTEXT	ends
	end
