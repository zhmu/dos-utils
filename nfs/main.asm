; vim:set ts=8 sw=8 noet:

_text	segment byte public use16 'code'

include settings.inc
include defines.inc
include macro.inc

extern pktdrv_call: proc
extern rpc_call: proc
extern rpc_store_string: proc
extern rpc_load_fh3: proc
extern parse_ip: proc
extern parse_int: proc
extern pkt_unhook: proc
extern redir_unhook: proc
extern pktdrv_search: proc
extern printhex: proc
extern arp_receiver: proc
extern ip_receiver: proc
extern dhcp_request: proc
extern printip: proc
extern printhwaddr: proc
extern redir_init: proc
extern resident_end: byte

extern xmitbuf: byte
extern my_hwaddr: byte
extern my_ip: dword
extern server_ip: byte
extern server_hwaddr_valid: byte
extern server_hwaddr: byte
extern rpc_progmap: dword
extern rpc_versionmap: word
extern rpc_portmap: word
extern mount_fh: byte
extern xid: dword
extern handle_arp: word
extern handle_ip: word

; arp_get_server: requests the ethernet address for server_ip
; returns carry=1 on success
arp_get_server:
	mov	di,offset xmitbuf
	xor	ax,ax
	dec	ax			; destination hw address (ff)
	stosw
	stosw
	stosw
	mov	si,offset my_hwaddr	; source hw address
	movsw
	movsw
	movsw
	mov	ax,0608h		; frame type
	stosw
	mov	ax,0100h		; hw type
	stosw
	mov	ax,08h			; protocol
	stosw
	mov	ax,0406h		; hw/sw size
	stosw
	mov	ax,0100h		; operation: request
	stosw
	mov	si,offset my_hwaddr	; source hw address
	movsw
	movsw
	movsw
	mov	si,offset my_ip		; source ip
	movsw
	movsw
	xor	ax,ax			; dest hw
	stosw
	stosw
	stosw
	mov	si,offset server_ip
	movsw
	movsw

	; off it goes!
	mov	ah,4		; pktdrv: send_pkt
	mov	si,offset xmitbuf
	mov	cx,63
	call	pktdrv_call

	; ok, now we wait until the server address is filled out
	xor	ax,ax
	mov	es,ax

	mov	ax,[es:46ch]	; timer tick lo
	add	ax,18*3+1	; roughly 3 seconds

arp_wait:
	cmp	byte ptr [server_hwaddr_valid],0
	jnz	arp_ok

	cmp	[es:46ch],ax
	jl	arp_wait

arp_fail:
	push	ds
	pop	es
	clc
	ret

arp_ok:
	push	ds
	pop	es
	stc
	ret

; retrieve a port using portmap
; input: bx = service index
; output: carry=1 on success, port array filled out
portmap_get:
	shl	bx,1			; bx = idx * 2
	mov	bp,bx
	shl	bp,1			; bp = idx * 4

	; prepare getport request
	mov	di,offset xmitbuf+OFFSET_RPCARGS
	lea	si,[rpc_progmap+bp] ; program
	movsw
	movsw
	; version, hi
	xor	ax,ax
	stosw
	mov	ax,word ptr [rpc_versionmap+bx]	; version, lo
	stosw
	; protocol is always UDP
	xor	ax,ax
	stosw
	mov	ax,(PROTO_UDP shl 8)
	stosw
	; port (zero, we want to know it)
	xor	ax,ax
	stosw
	stosw

	push	bx
	xor	bx,bx		; service: portmap
	mov	ax,3		; procedure: getport
	mov	bp,16		; data len: 4 dwords
	call	rpc_call
	pop	bx
	jc	portmap_get_ok

portmap_err:
	clc
	ret

portmap_get_ok:
	cmp	cx,4		; reply must be port only
	jne	portmap_err

	; fetch port number
	lodsw
	or	ax,ax
	jnz	portmap_err
	lodsw
	xchg	ah,al

	; bx is still the service number * 2
	mov	word ptr [rpc_portmap+bx],ax
	stc
	ret

; mountd_mount: retrieve the filename for path in si
; input: ds:si = filehandle path
; output: carry=1 on success -> mount_fh valid
mountd_mount:
	; make packet
	mov	di,offset xmitbuf+OFFSET_RPCARGS
	xor	bp,bp
	xor	bl,bl		; ds:si is zero-terminated
	call	rpc_store_string

	; send it
	mov	bx,1		; mountd
	mov	ax,1		; mnt
	call	rpc_call
	jnc	mount_fail

	; we must have at least a status and file handle now ...
	cmp	cx,4
	jl	mount_fail

	; status ok?
	lodsw
	or	ax,ax
	jne	mount_fail
	lodsw
	or	ax,ax
	jne	mount_fail

	mov	di,offset mount_fh
	jmp	rpc_load_fh3	; sets carry for us

mount_fail:
	clc
	ret

usage_err:
	mov	ah,9
	int	21h
	mov	dx,offset crlf
	int	21h
usage:
	mov	ah,9
	mov	dx,offset msg_usage
	int	21h
	mov	ax,4c01h
	int	21h

parse_cmdline:
	mov	si,80h		; cmdline length
	lodsb

	; zero terminate
	xor	ah,ah
	mov	bx,ax
	xor	al,al
	lea	di,[si+bx]
	stosb

	; walk throught the command line one-by-one
p_loop:
	lodsb
	or	al,al
	jz	p_end
	cmp	al,' '
	je	p_next
	cmp	al,'/'
	je	p_arg

	; not a slash, not a space: must be the path to mount
	dec	si
	mov	word ptr [mount_path],si
	jmp	p_end

p_arg:
	lodsw
	cmp	al,'?'
	je	usage
	cmp	al,'h'
	je	usage
	cmp	al,'H'
	je	usage
	cmp	ax,'P:'
	je	p_pkt
	cmp	ax,'p:'
	je	p_pkt
	cmp	ax,'IP'
	je	p_ip
	cmp	ax,'ip'
	je	p_ip

p_arg_bad:
	mov	dx,offset msg_unknown_arg
	jmp	usage_err

p_ip:	lodsb
	cmp	al,':'
	jne	p_arg_bad

	; got a client IP now, try to parse
	mov	di,offset my_ip
	call	parse_ip
	jnc	p_next

	mov	dx,offset msg_bad_ip
	jmp	usage_err

p_pkt:
	mov	bx,16
	call	parse_int
	or	dh,dh
	jnz	p_pkt_bad
	cmp	dl,60h
	jb	p_pkt_bad
	cmp	dl,80h
	ja	p_pkt_bad

	mov	byte ptr [pktdrv_call+1],dl
	jmp	p_next

p_pkt_bad:
	mov	dx,offset msg_bad_pkt
	jmp	usage_err


p_next:
	jmp	p_loop

p_end:
	ret

public main
main	proc
	; see if we are already installed
	mov	ax,11feh	; installation check
	mov	bx,5052h
	mov	cx,5357h
	xor	dx,dx
	int	2fh
	cmp	dh,0feh
	jne	not_installed

	; already installed (code in ax, drive in dl) -> deinstall
	mov	ds,ax

	; patch packet driver irq over to our cs so that we can
	; call it
	mov	bx,offset pktdrv_call+1
	mov	al,byte ptr [ds:bx]
	mov	byte ptr [cs:bx],al

	call	pkt_unhook
	call	redir_unhook

	push	ds
	pop	es
	mov	ah,49h		; dos: free memory (es)
	int	21h

	push	cs
	pop	ds

	mov	ah,9
	mov	dx,offset uninstalled_msg
	int	21h

	int	20h

not_installed:
	; overwrite entrypoint with packet driver call
	mov	di,offset pktdrv_call
	mov	ax,000cdh	    ; int 00h
	stosw
	mov	al,0c3h		    ; ret
	stosb

	; handle command line arguments (may overwrite pktdrv interrupt)
	call	parse_cmdline

	mov	ax,word ptr [mount_path]
	or	ax,ax
	jnz	path_filled

	mov	dx,offset msg_no_path
	jmp	die

path_filled:
	; mount_path must be xx.xx.xx.xx:path - resolve the IP address
	mov	di,offset nfs_server_ip
	call	parse_ip
	jnc	server_ip_ok

server_ip_err:
	mov	dx,offset msg_ip_error
	jmp	die

server_ip_ok:
	cmp	al,':'
	jne	server_ip_err
	mov	word ptr [mount_path],si		    ; points to path now

	; 'randomize' our xid, this keeps the server from
	; thinking it already serviced our request
	push	es
	xor	ax,ax
	mov	es,ax
	mov	ax,[es:46ch]	; timer tick lo
	mov	bx,[es:46eh]	; timer tick hi
	pop	es
	mov	word ptr [xid+0],ax
	mov	word ptr [xid+2],bx

	mov	dl,byte ptr [pktdrv_call+1]
	or	dl,dl
	jnz	got_pktdrv

	; look for a packet driver
	call	pktdrv_search
	or	dx,dx
	jne	found_pktdrv

pktdrv_error:
	mov	dx,offset nopkt
die:	mov	ah,9
	int	21h
	int	20h

found_pktdrv:
	; got one; patch it inside our code
	mov	byte ptr [pktdrv_call+1],dl

got_pktdrv:
	; and tell the user
	push	dx
	mov	ah,9
	mov	dx,offset pktdrv_found
	int	21h
	pop	ax
	call	printhex
	mov	ah,9
	mov	dx,offset pktdrv_found2
	int	21h

	; see if the packet driver we found is sane
	mov	ax,01ffh	; pktdrv: driver info
	xor	bx,bx
	call	pktdrv_call
	cmp	al,0ffh
	push	cs
	pop	ds
	je	pktdrv_error

	; ch = class, dx = type, cl = number, ds:si = name
	cmp	ch,1
	je	pktclass_ok

pktfail:
	mov	dx,offset errpkt
	jmp	die

pktclass_ok:
	mov	ah,2			; pktdrv: access_type
	mov	bx,dx			; if_type
	mov	al,ch			; if_class
	mov	dl,cl			; if_number
	mov	si,offset type_arp	; ds:si = type
	mov	di,offset arp_receiver		; es:di = receiver
	pushm	bx, cx, dx
	mov	cx,2
	call	pktdrv_call
	popm	dx, cx, bx
	jc	pktfail
	mov	word ptr [handle_arp],ax

	mov	ah,2			; pktdrv: access_type
	mov	al,ch			; if_class
	mov	si,offset type_ip	; ds:si = type
	mov	di,offset ip_receiver		; es:di = receiver
	mov	cx,2
	call	pktdrv_call
	jc	pktfail
	mov	word ptr [handle_ip],ax

	; fetch hw address (why does this need a handle instead of an
	; if_class/type/numer?)
	mov	bx,ax			; handle
	mov	ah,6			; pktdrv: get_address
	mov	di,offset my_hwaddr
	mov	cx,6
	call	pktdrv_call
	jc	pkterr
	cmp	cx,6
	jne	pkterr

	; fill out broadcast hw address
	mov	di,offset server_hwaddr
	xor	ax,ax
	dec	ax
	mov	cx,3
	rep	stosw

	; see if we have an IP address; if so, skip DHCP
	mov	si,offset my_ip
	lodsw
	mov	bx,ax
	lodsw
	or	ax,bx
	jnz	have_ip

	; use DHCP to obtain our IP address
	call	dhcp_request
	jc	have_ip

	mov	dx,offset dhcp_failure
	jmp	pkterr_msg

have_ip:
	; tell the user about our IP address
	mov	ah,9
	mov	dx,offset ip_success
	int	21h

	mov	si,offset my_ip
	call	printip

	mov	ah,9
	mov	dx,offset crlf
	int	21h

	; copy nfs server to the server IP - this is the only host we'll be
	; talking to from now on
	mov	si,offset nfs_server_ip
	mov	di,offset server_ip
	movsw
	movsw

	; fetch the server's hw address
	call	arp_get_server
	jc	arp_server_ok

	mov	dx,offset arp_failed
	jmp	pkterr_msg

arp_server_ok:
	mov	ah,9
	mov	dx,offset arp_msg
	int	21h

	mov	si,offset server_hwaddr
	call	printhwaddr

	mov	ah,9
	mov	dx,offset crlf
	int	21h

	; look up mountd port first
	mov	bx,1
	call	portmap_get
	jc	portmap_ok

	mov	dx,offset mountport_failed
	jmp	pkterr_msg

portmap_ok:
	; then look up nfsd port
	mov	bx,2
	call	portmap_get
	jc	nfsd_ok

	mov	dx,offset nfsport_failed
	jmp	pkterr_msg

nfsd_ok:
	; now mount our path
	mov	si,word ptr [mount_path]
	call	mountd_mount
	jc	mount_ok

	mov	dx,offset mount_failed
	jmp	pkterr_msg

mount_ok:
	;
	; all is okay: we got DHCP, we got the handle to the NFS directory. We
	; should become resident here
	;
	call	redir_init
	jnc	pkterr

	mov	ah,48h		; dos: free memory
	mov	es,[ds:2ch]	; environment table
	int	21h

	mov	ax,3100h	; dos: terminate, stay resident
	mov	dx,offset resident_end
	shr	dx,1
	shr	dx,1
	shr	dx,1
	shr	dx,1
	inc	dx
	int	21h

pkterr_msg:
	mov	ah,9
	int	21h
	mov	dx,offset crlf
	int	21h
pkterr:
	call	pkt_unhook

	int	20h
main	endp

; NON-RESIDENT DATA
msg_bad_pkt	db	'error: packet driver interrupt not in range 60..80$'
msg_bad_ip	db	'error: cannot parse client ip$'
msg_unknown_arg	db	'error: unrecognized parameter$'
msg_no_path	db	'error: mount path not supplied$'
msg_ip_error	db	'error: mount path invalid, must be server_ip:path$'
msg_usage	db	'NFSPKT - NFS filesystem driver for DOS (GPLv3)',10,13
		db	'(c) 2020-2023 Rink Springer <rink@rink.nu>',10,13
		db	'https://github.com/zhmu/dos-utils',10,13
		db	10,13
		db	'usage: NFSPKT [/?h] [/p:xx] [/ip:x.x.x.x] server_ip:path',10,13
		db	10,13
		db	'/?, /h           help',10,13
		db	'/p:xx            use xx as packet driver interrupt (default: detect)',10,13
		db	'/ip:x.x.x.x      set client IP to x.x.x.x (default: DHCP)'
crlf		db	10,13,'$'
mount_path	dw	0
nfs_server_ip	dd	0

pktdrv_found	db	'Using packet driver at interrupt $'
pktdrv_found2	db	'h',10,13,'$'
nopkt		db	'Packet driver not installed$'
errpkt		db	'Packet driver error$'
dhcp_failure	db	'DHCP: unable to obtain address'
ip_success	db	'IP: my address is $'
arp_msg		db	'ARP: server MAC is $'

arp_failed	db	'Unable to obtain server MAC address$'
mount_failed	db	'Unable to mount NFS$'
mountport_failed	db	'Unable to lookup mountd port$'
nfsport_failed	db	'Unable to lookup nfsd port$'

type_arp	dw	0608h
type_ip		dw	0008h

uninstalled_msg	db	'Uninstalled$'

_text	ends
	end
