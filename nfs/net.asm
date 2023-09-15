; vim:set ts=8 sw=8 noet:

RESTEXT		segment word public 'CODE'

include defines.inc
include macro.inc
include settings.inc

extern arpbuf: byte
extern server_ip: dword
extern server_hwaddr: byte
extern server_hwaddr_valid: byte
extern my_ip: dword
extern my_hwaddr: byte
extern recv_len: word
extern pktbuf: byte
extern recvbuf: byte
extern xmitbuf: byte
extern ip_id: word

public pktdrv_call
public udp_send
public pktdrv_int

pktdrv_call    proc
		db	0cdh	; INT
pktdrv_int:
		db	0	; patched as needed
		ret
pktdrv_call    endp

e_hdr		struc
eh_dst:		db	6 dup (?)	; 0
eh_src:		db	6 dup (?)	; 6
eh_hwtype:	dw	?		; 12
e_hdr		ends

ip_hdr		struc
ip_vlen:	db	?		; 0
ip_tos:		db	?		; 1
ip_len:		dw	?		; 2
ip_iid:		dw	?		; 4
ip_ffrag:	dw	?		; 6
ip_ttl:		db	?		; 8
ip_proto:	db	?		; 9
ip_hchk:	dw	?		; 10
ip_saddr:	dd	?		; 12
ip_daddr:	dd	?		; 14
ip_hdr		ends

udp_hdr		struc
udp_sport:	dw	?		; 0
udp_dport:	dw	?		; 2
udp_len:	dw	?		; 4
udp_cksum:	dw	?		; 6
udp_hdr		ends

;
; arp_receiver: called when the NIC driver receives an ARP packet
;
public		arp_receiver
arp_receiver	proc
		; bx = handle, ax = flag, cx = len
		or	ax,ax		; length req?
		jnz	arp_data	; no -> handle data

		cmp	cx,ARPBUF_LEN	; can we store the packet?
		jge	pkt_reject	; no; reject buffer

		; packet will fit, hand buffer
		mov	ax,cs
		mov	es,ax
		mov	di,offset arpbuf
		retf
arp_receiver	endp

arp_data:
	;
	; ARP packets looks like the following (Stevens, p56)
	;
	; 0...5 6.11 12/13 14,15 16,17 18 19 20,21 22..27 28..31 32..37 38..41
	; desta srca ft    hw    prot  hs ps op    srca   srcip  tgta   tgtip
	;
	; ft = frame type, 806h for ARP
	; hw = hardware type, 1 for ethernet
	; prot = protocol type, 800h for IP
	; hs = hardware size, 6 for ethernet
	; ps = protocol size, 4 for IP
	; op = operation, 1 = request, 2 = reply
	; srca, srcip = sender ethernet address, ip address
	; tgta, tgtip = target ethernet address, ip address
	;

	; do basic hw/prot/hs/ps checks first; ft doesn't need checking since
	; the packet driver does that for us
	cmp	word ptr [si+14],100h	; hw type must be 1
	jne	arp_ignore
	cmp	word ptr [si+16],8h	; prot must be 8
	jne	arp_ignore
	cmp	word ptr [si+18],0406h	; hs must be 6, ps must be 4
	jne	arp_ignore

	; ok, we likely need to work on this. set some stuff up
	push	cs
	pop	es

	cmp	word ptr [si+20],100h	; arp request?
	je	arp_request
	cmp	word ptr [si+20],200h	; arp reply?
	jne	arp_ignore

arp_reply:
	; target is the server ip?
	push	si
	mov	di,offset server_ip
	add	si,28			; target address
	mov	cx,2
	repe	cmpsw
	pop	si
	jne	arp_ignore

	; copy frame's source address
	add	si,6
	mov	di,offset server_hwaddr
	mov	cx,3
	rep	movsw

	; mark the server address as valid
	inc	byte ptr [server_hwaddr_valid]
	retf

arp_request:
	; target is us?
	push	si
	mov	di,offset my_ip
	add	si,38			; target address
	mov	cx,2
	repe	cmpsw
	pop	si
	jne	arp_ignore

	; swap source/target ip addresses
	mov	ax,[si+28]
	xchg	ax,[si+38]
	mov	[si+28],ax
	mov	ax,[si+30]
	xchg	ax,[si+40]
	mov	[si+30],ax

	; set operation to reply
	inc	byte ptr [si+21]

	; copy source hw address to frame/dest; we are replying to it
	mov	di,si
	add	si,6
	mov	cx,3
arp_c1:	lodsw
	mov	[es:di],ax
	mov	[es:di+32],ax
	inc	di
	inc	di
	loop	arp_c1

	; fill out our hw address; note that di=pkt+6 at this point
	mov	si,offset my_hwaddr
	mov	cx,3
arp_c2:	lodsw
	mov	[es:di],ax
	mov	[es:di+16],ax	; 16 because di=pkt+6
	inc	di
	inc	di
	loop	arp_c2

	; off it goes!
	mov	ah,4		; pktdrv: send_pkt
	mov	si,offset arpbuf
	mov	cx,63
	call	pktdrv_call

arp_ignore:
	retf

pkt_reject:
	; es:si = 0:0 means we care not about the packet
	xor	di,di
	mov	es,di
	retf

;
; ip_receiver: called when the NIC driver receives an IP packet in ds:si
;
public		ip_receiver
ip_receiver	proc
		; bx = handle, ax = flag, cx = len
		or	ax,ax		; length req?
		jnz	ip_data		; no -> handle data

if 1
		; got data pending?
		cmp	word ptr [cs:recv_len],0
		;jnz	pkt_reject	; KOE - fixen
		jz	OOKK

		mov	ax,0e21h ; '!'
		int     10h
		int	3
		jmp	pkt_reject
OOKK:
endif

		cmp	cx,PKTBUF_LEN	; can we store the packet?
		jg	pkt_reject	; no, reject it

		; packet will fit, hand buffer
		mov	ax,cs
		mov	es,ax
		mov	di,offset pktbuf
		retf
ip_receiver	endp

ip_data:
	push    cs
	pop	es

	; verify the destination IP address
	add	si,size e_hdr+ip_daddr
	mov	di,offset my_ip
	mov	cx,2
	push	si
	repe	cmpsw
	pop	si
	je	ip_forus

	; IP address mismatch; is our address all zero (i.e. we don't know) ?
	cmp	word ptr [my_ip],0
	jne	ip_discard
	cmp	word ptr [my_ip+2],0
	jz	ip_forus

ip_discard:
	retf

ip_forus:
	sub	si,ip_daddr	; move pointer back to ip header

	; calculate pointer to inner protocol data
	mov	bx,word ptr [si+ip_vlen]
	and	bx,0fh
	shl	bx,1
	shl	bx,1		; bx = length of ip header
	lea	bp,[si+bx]	; bp = payload

	; ok, this packet is for us; see if it's ICMP or UDP
	mov	al,byte ptr [si+ip_proto]
	cmp	al,PROTO_UDP	; udp
	je	udp_receive
	cmp	al,PROTO_ICMP	; icmp
	je	icmp_receive

	; neither ICMP nor UDP; silently drop it
	retf

udp_receive:
	; si = ip header, bp = udp header - is the destination port okay?
	mov	ax,word ptr [ds:bp+udp_dport]
	xchg	ah,al

	; calculate UDP length
	mov	cx,word ptr [si+ip_len]
	xchg	ch,cl
	sub	cx,bx		; cx = UDP length (incl header)

	; check the UDP length
	mov	ax,word ptr [ds:bp+udp_len]
	xchg	ah,al
	cmp	ax,cx
	jne	ip_discard

	; XXX verify checksum
	sub	ax,size udp_hdr		; skip header

	; copy UDP packet contents
	lea	si,[bp+size udp_hdr]
	mov	di,offset recvbuf
	mov	cx,ax
	rep	movsb

	; all set, store length
	mov	word ptr [recv_len],ax
	retf

icmp_receive:
	; bp = ip header
	cmp	word ptr [ds:bp],8h	; icmp echo req?
	je	icmp_echoreq

	; XXX we only handle echo request
	retf

icmp_echoreq:
	; calculate reply length
	mov	cx,[si+2]
	xchg	ch,cl
	sub	cx,20
	mov	bp,cx		; bp = packet length minus IP header

	push	si
	mov	bh,PROTO_ICMP
	call	ip_make
	pop	si
	add	si,24		; si = icmp id/seq/payload

	; place icmp header
	xor	ax,ax		; type: reply
	stosw
	stosw			; checksum

	; copy all data
	sub	cx,4		; skip type/code and checksum
	rep	movsb
	xor	al,al		; zero-pad for header checksum
	stosb
	mov	cx,bp
	inc	cx
	shr	cx,1		; cx = size in words
	dec	cx

	; need to fix the ICMP checksum
	mov	si,offset xmitbuf+34	; skip frame+IP header
	lodsw
	mov	bx,ax
icmp_cksum:
	lodsw
	add	bx,ax
	adc	bx,0
	loop	icmp_cksum
	not	bx

	; store the checksum
	mov	si,offset xmitbuf+36
	mov	[si],bx

	; off it goes!
	mov	ah,4		; pktdrv: send_pkt
	mov	si,offset xmitbuf
	mov	cx,bp
	add	cx,34		; ip header + frame header
	call	pktdrv_call

	retf

;
; ip_make: creates an IP header. bh = protocol, bp = payload length
;
; returns: xmitbuf = frame, di = IP payload pointer
; corrupts: ax, bx, si
;
ip_make:
	mov	di,offset xmitbuf
	; frame: destination hw address
	mov	si,offset server_hwaddr
	movsw
	movsw
	movsw
	; frame: source hw address
	mov	si,offset my_hwaddr
	movsw
	movsw
	movsw
	; frame: type
	mov	ax,08h
	stosw
	; ip: version, length, tos
	mov	ax,45h
	stosw
	; ip: total length
	mov	ax,bp
	add	ax,20		; ip header
	xchg	ah,al
	stosw
	; ip: identification
	inc	word ptr [ip_id]
	mov	ax,word ptr [ip_id]
	xchg	ah,al
	stosw
	; ip: flags, fragment
	xor	ax,ax
	stosw
	; ip: ttl, protocol
	mov	ax,bx
	mov	al,20h		; ttl = 32
	stosw
	; ip: header checksum
	xor	ax,ax
	stosw
	; ip: source IP
	mov	si,offset my_ip
	movsw
	movsw
	; ip: dest IP
	mov	si,offset server_ip
	movsw
	movsw

	; now we must calculate the header checksum
	lea	si,[di-20]
	lodsw
	mov	bx,ax
ip_cksum:
	lodsw
	add	bx,ax
	adc	bx,0
	cmp	si,di
	jne	ip_cksum
	not	bx

	; store the checksum
	sub	si,10
	mov	[si],bx
	ret
;
; udp_send: bp = length, bx = source port, dx = dest port (network order)
;           data must be present at xmitbuf+OFFSET_UDPDATA
;
udp_send:
	pushm	bx, bp
	mov	bh,PROTO_UDP
	add	bp,8		 ; udp header len
	call	ip_make
	popm	bp, bx

	; udp: source port
	mov	ax,bx
	xchg	ah,al
	stosw
	; udp: dest port
	mov	ax,dx
	xchg	ah,al
	stosw
	; udp: length
	mov	ax,bp
	add	ax,8		; size includes header
	xchg	ah,al
	stosw
	; udp: checksum (optional so we don't care :-)
	xor	ax,ax
	stosw

	; off it goes!
	mov	ah,4			; pktdrv: send_pkt
	mov	si,offset xmitbuf
	mov	cx,bp
	add	cx,OFFSET_UDPDATA	; ethernet+ip+udp headers
	call	pktdrv_call
	ret

RESTEXT	ends
	end
