; vim:set ts=8 sw=8 noet:

_text	segment byte public use16 'code'

include defines.inc

extern recv_len: word
extern udp_send: proc
extern xid: dword
extern xmitbuf: byte
extern my_hwaddr: byte
extern recvbuf: byte
extern my_ip: dword

public dhcp_request

; dhcp_call: performs DHCP request and waits for the reply
; input: dl = packet type, options @ xmitbuf+OFFSET_DHCPOPTS,
;        cx = options length
; output: carry=1 on success -> dh = request type,
;                               bp = server id (zero if not present)
dhcp_call:
	; increment xid
	inc	word ptr [xid+0]
	adc	word ptr [xid+2],0

	; fill out the packet
	push	cx
	mov	di,offset xmitbuf+OFFSET_UDPDATA
	mov	ax,0101h		; operation/htype
	stosw
	mov	ax,0006h		; hlen/hops
	stosw
	mov	ax,word ptr [xid+0]	; xid lo
	stosw
	mov	ax,word ptr [xid+2]	; xid hi
	stosw
	xor	ax,ax
	stosw				; secs
	stosw				; flags
	mov	cx,8
	rep	stosw			; [csg]iaddr
	mov	si,offset my_hwaddr
	mov	cx,3
	rep	movsw			; hwaddr
	mov	cx,5
	xor	ax,ax
	rep	stosw			; hwaddr (zero-pad)
	mov	cx,32
	rep	stosw			; sname
	mov	cx,64
	rep	stosw			; file
	mov	ax,8263h
	stosw				; options magic cookie 1
	mov	ax,6353h
	stosw				; options magic cookie 2
	mov	ax,0135h
	stosw				; dhcp message type
	mov	al,dl
	stosb				; dhcpdiscover
	pop	bp			; was cx
	add	di,bp
	mov	al,255
	stosb				; end of options
	sub	di,offset xmitbuf+OFFSET_UDPDATA
	mov	bp,di			; length

	; reset response
	xor	ax,ax
	mov	[recv_len],ax

	; off it goes; our port must be 67, server is 68
	mov	bx,68
	mov	dx,67
	call	udp_send
	jmp	dhcp_wait

dhcp_wait_reset:
	xor	ax,ax
	mov	word ptr [recv_len],ax

dhcp_wait:
	mov	ah,1		; keyboard: check for keystroke
	int	16h
	jnz	dhcp_error	; if any, abort

	mov	dx,word ptr [recv_len]
	cmp	dx,247		; must be at least 247 bytes
	jl	dhcp_wait_reset	; (BOOTP with DHCP options)

	; ok, is this a reply?
	mov	si,offset recvbuf
	cmp	byte ptr [si],2
	jne	dhcp_wait_reset	; no, discard

	; is this for our xid?
	mov	di,offset xid
	add	si,4
	mov	cx,2
	repe	cmpsw
	jne	dhcp_wait_reset	; no, discard

	; xid matches; is this a DHCP packet?
	lea	bp,[si+228]
	xchg	bp,si
	lodsw
	cmp	ax,8263h
	jne	dhcp_wait_reset
	lodsw
	cmp	ax,6353h
	jne	dhcp_wait_reset

	; calculate options length
	mov	ax,si
	sub	ax,offset recvbuf
	mov	cx,word ptr [recv_len]
	sub	cx,ax

	; now walk through the options and fetch the DHCP type and
	; server identification fields
	xor	bp,bp
	xor	bh,bh
	xor	dh,dh
dhcp_opts_loop:
	lodsb
	cmp	al,0ffh
	je	dhcp_opts_done
	mov	dl,al		; dl = option
	lodsb
	mov	bl,al
	dec	cx		; subtract type
	dec	cx		; subtract length
	sub	cx,bx
	js	dhcp_error	; reply corrupt

	lea	di,[si+bx-1]	; di = offset of next option

	; now, dl = option, si = option data
	cmp	dl,35h		; dhcp message type?
	jne	dhcp_opts_notype

	mov	dh,[di]		; store type in dh

dhcp_opts_notype:
	cmp	dl,36h		; dhcp server identifier?
	jne	dhcp_opts_nosid

	; is the length sane?
	cmp	bl,4
	jne	dhcp_error

	mov	bp,si		; store server id in bp

dhcp_opts_nosid:
	lea	si,[di+1]
	jmp	dhcp_opts_loop

dhcp_opts_done:
	stc
	ret

dhcp_error:
	clc
	ret

dhcp_request:
	xor	cx,cx
	mov	dl,1		; DHCPDISCOVER
	call	dhcp_call
	jnc	dhcp_error

	cmp	dh,2		; type = DHCPOFFER?
	jne	dhcp_error	; no, reject

	or	bp,bp		; have a server id?
	jz	dhcp_error	; no, reject

	; ok, we have obtained a valid address - copy it
	mov	si,offset recvbuf+16	; yiaddr
	mov	di,offset my_ip
	mov	cx,2
	rep	movsw

	; now we need to send a DHCPREQUEST with the IP addresses we found and
	; the server's identifier; this means we acknowledge the address. It
	; must be broadcast so that all servers get it

	; insert selected server in "server identifier"
	; ciaddr must be zero
	; requested ip address = yiaddr
	mov	di,offset xmitbuf+OFFSET_DHCPOPTS
	mov	ax,0432h	; option: requested ip address, length 4
	stosw
	mov	si,offset my_ip
	mov	cx,2
	rep	movsw

	mov	ax,0436h	; option: server identifier
	stosw
	mov	si,bp
	mov	cx,2
	rep	movsw

	mov	cx,12
	mov	dl,3		; DHCPREQUEST
	call	dhcp_call
	jnc	dhcp_error

	cmp	dh,5		; DHCPACK
	jne	dhcp_error
	stc
	ret

_text	ends
	end
