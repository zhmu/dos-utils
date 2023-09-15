; vim:set ts=8 sw=8 noet:

_text	segment byte public use16 'code'

include defines.inc
include macro.inc
include settings.inc

; NETWORK STUFF, NON-RESIDENT

extern pktdrv_call: proc
extern handle_ip: word
extern handle_arp: word

public pktdrv_search
public pkt_unhook

; looks for a packet driver
; output: on success -> dl = packet driver interrupt (60h - 80h)
;         otherwise -> dl = 0
pktdrv_search:
	mov	dx,60h

pktdrv_loop:
	xor	ax,ax
	mov	es,ax
	mov	bx,dx
	shl	bx,1
	shl	bx,1
	les	di,[es:bx]	; es:di = interrupt dx handler

	mov	cx,12		; need to scan 12 bytes

	mov	si,offset pktdrv_sig
	lodsb
	repne	scasb
	jne	pktdrv_skip

	; found the first char, try to match the rest
	mov	cx,pktdrv_siglen-1
	repe	cmpsb
	jne	pktdrv_skip

	; all matches; report success
	jmp	pktdrv_search_done

pktdrv_skip:
	inc	dx
	cmp	dx,81h
	jne	pktdrv_loop
	xor	dx,dx		; not found

pktdrv_search_done:
	push	cs
	pop	es
	ret

pkt_unhook:
	; kill packet driver, ip part
	mov	ah,3		; pktdrv: release_type
	mov	bx,word ptr [handle_ip]
	call	pktdrv_call

	; kill packet driver, arp part
	mov	ah,3		; pktdrv: release_type
	mov	bx,word ptr [handle_arp]
	call	pktdrv_call
	ret


pktdrv_sig	db	"PKT DRVR",0
pktdrv_siglen	equ	$-pktdrv_sig

_text	ends
	end
