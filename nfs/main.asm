; vim:set ts=8 sw=8 noet:
CLASS_ETHERNET	equ	1
HWADDR_LEN	equ	6
PROTO_ICMP	equ	1h
PROTO_UDP	equ	11h

OFFSET_UDPDATA		equ	42
OFFSET_DHCPOPTS		equ	OFFSET_UDPDATA+243
OFFSET_RPCARGS		equ	82
OFFSET_RPCARGS_NFS	equ	OFFSET_RPCARGS+20

FH3SIZE		equ	64	; maximum
COOKIE_SIZE	equ	8
COOKIEV_SIZE	equ	8

NUM_HANDLE_SLOTS	equ	4
NUM_DIR_SLOTS 		equ	4

;
; RESIDENT CODE ENDS HERE; data continues
;

arpbuf_len	equ	64			; minimal packet size
pktbuf_len	equ	1536			; one ethernet frame
pktbuf		times	pktbuf_len db 0
arpbuf		times	arpbuf_len db 0
xmitbuf		times	pktbuf_len db 0
recvbuf		times	pktbuf_len db 0
mount_fh	times	FH3SIZE+1 db 0
temp_fh		times	FH3SIZE+1 db 0
temp_fh2	times	FH3SIZE+1 db 0
handle_slots	times	(FH3SIZE+1)*NUM_HANDLE_SLOTS db 0
; each dir slot contains handle, cookie, cookiev
DIR_SLOT_SIZE	equ	FH3SIZE+1+COOKIE_SIZE+COOKIEV_SIZE
dir_slots	times	DIR_SLOT_SIZE*NUM_DIR_SLOTS db 0
next_dir_slot	db	0

; readdir state
readdir_fname	dw	0	; offset in ds of filename
readdir_flen	dw	0	; filename length (bytes)
readdir_type	dw	0	; file type
readdir_len	dd	0	; file length (bytes)
readdir_time	dw	0
readdir_date	dw	0

xid		dd	0
ip_id		dw	0
my_ip		dd	0
my_hwaddr	times	HWADDR_LEN db 0
server_ip	db	255, 255, 255, 255
server_hwaddr	times	HWADDR_LEN db 0
server_hwaddr_valid	db	0
recv_len	dw	0

handle_arp	dw	0
handle_ip 	dw	0

rpc_progmap	dd	0a0860100h		; portmap (100000)
		dd	0a5860100h		; mountd (100005)
		dd	0a3860100h		; nfs (100003)

rpc_portmap	dw	111			; portmap is always 111
		dw	0			; unknown
		dw	0			; unknown

rpc_versionmap	dw	0200h			; portmap
		dw	0300h			; mountd
		dw	0300h			; nfs

sda		dd	0
drive_cds	dd	0
drive_no	db	0			; 1 = A:, etc

hextab		db	"0123456789abcdef"	; XXX only if REDIR_DEBUG_CALLS

; RESIDENT DATA ends here
resident_end	equ	$

; arp_get_server: requests the ethernet address for server_ip
; returns carry=1 on success
arp_get_server:
	mov	di,xmitbuf
	xor	ax,ax
	dec	ax			; destination hw address (ff)
	stosw
	stosw
	stosw
	mov	si,my_hwaddr		; source hw address
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
	mov	si,my_hwaddr		; source hw address
	movsw
	movsw
	movsw
	mov	si,my_ip		; source ip
	movsw
	movsw
	xor	ax,ax			; dest hw
	stosw
	stosw
	stosw
	mov	si,server_ip
	movsw
	movsw

	; off it goes!
	mov	ah,4		; pktdrv: send_pkt
	mov	si,xmitbuf
	mov	cx,63
	call	pktdrv_call

	; ok, now we wait until the server address is filled out
	xor	ax,ax
	mov	es,ax

	mov	ax,[es:46ch]	; timer tick lo
	add	ax,18*3+1	; roughly 3 seconds

arp_wait:
	cmp	byte [server_hwaddr_valid],0
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
	mov	di,xmitbuf+OFFSET_RPCARGS
	lea	si,[rpc_progmap+bp] ; program
	movsw
	movsw
	; version, hi
	xor	ax,ax
	stosw
	mov	ax,[rpc_versionmap+bx]	; version, lo
	stosw
	; protocol is always UDP
	xor	ax,ax
	stosw
	mov	ax,PROTO_UDP << 8
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
	mov	[rpc_portmap+bx],ax
	stc
	ret

; mountd_mount: retrieve the filename for path in si
; input: ds:si = filehandle path
; output: carry=1 on success -> mount_fh valid
mountd_mount:
	; make packet
	mov	di,xmitbuf+OFFSET_RPCARGS
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

	mov	di,mount_fh
	jmp	rpc_load_fh3	; sets carry for us

mount_fail:
	clc
	ret

%include "dhcp.asm"
%include "redir2.asm"
%include "net2.asm"
%include "helper2.asm"

usage_err:
	mov	ah,9
	int	21h
	mov	dx,crlf
	int	21h
usage:
	mov	ah,9
	mov	dx,msg_usage
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
.p_loop:
	lodsb
	or	al,al
	jz	.p_end
	cmp	al,' '
	je	.p_next
	cmp	al,'/'
	je	.p_arg

	; not a slash, not a space: must be the path to mount
	dec	si
	mov	[mount_path],si
	jmp	.p_end

.p_arg:
	lodsw
	cmp	al,'?'
	je	usage
	cmp	al,'h'
	je	usage
	cmp	al,'H'
	je	usage
	cmp	ax,'P:'
	je	.p_pkt
	cmp	ax,'p:'
	je	.p_pkt
	cmp	ax,'IP'
	je	.p_ip
	cmp	ax,'ip'
	je	.p_ip

.p_arg_bad:
	mov	dx,msg_unknown_arg
	jmp	usage_err

.p_ip:	lodsb
	cmp	al,':'
	jne	.p_arg_bad

	; got a client IP now, try to parse
	mov	di,my_ip
	call	parse_ip
	jnc	.p_next

	mov	dx,msg_bad_ip
	jmp	usage_err

.p_pkt:
	mov	bx,16
	call	parse_int
	or	dh,dh
	jnz	.p_pkt_bad
	cmp	dl,60h
	jb	.p_pkt_bad
	cmp	dl,80h
	ja	.p_pkt_bad

	mov	[pktdrv_int],dl
	jmp	.p_next

.p_pkt_bad:
	mov	dx,msg_bad_pkt
	jmp	usage_err

.p_next:
	jmp	.p_loop

.p_end:
	ret

main:
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
	mov	al,byte [ds:pktdrv_int]
	mov	byte [cs:pktdrv_int],al

	call	pkt_unhook
	call	redir_unhook

	push	ds
	pop	es
	mov	ah,49h		; dos: free memory (es)
	int	21h

	push	cs
	pop	ds

	mov	ah,9
	mov	dx,uninstalled_msg
	int	21h

	int	20h

not_installed:
	call	parse_cmdline

	mov	ax,[mount_path]
	or	ax,ax
	jnz	.path_filled

	mov	dx,msg_no_path
	jmp	die

.path_filled:
	; mount_path must be xx.xx.xx.xx:path - resolve the IP address
	mov	di,nfs_server_ip
	call	parse_ip
	jnc	.server_ip_ok

.server_ip_err:
	mov	dx,msg_ip_error
	jmp	die

.server_ip_ok:
	cmp	al,':'
	jne	.server_ip_err
	mov	[mount_path],si		    ; points to path now

	; 'randomize' our xid, this keeps the server from
	; thinking it already serviced our request
	push	es
	xor	ax,ax
	mov	es,ax
	mov	ax,[es:46ch]	; timer tick lo
	mov	bx,[es:46eh]	; timer tick hi
	pop	es
	mov	word [xid+0],ax
	mov	word [xid+2],bx

	mov	dl,[pktdrv_int]
	or	dl,dl
	jnz	got_pktdrv

	; look for a packet driver
	call	pktdrv_search
	or	dx,dx
	jne	found_pktdrv

pktdrv_error:
	mov	dx,nopkt
die:	mov	ah,9
	int	21h
	int	20h

found_pktdrv:
	; got one; patch it inside our code
	mov	byte [pktdrv_int],dl

got_pktdrv:
	; and tell the user
	push	dx
	mov	ah,9
	mov	dx,pktdrv_found
	int	21h
	pop	ax
	call	printhex
	mov	ah,9
	mov	dx,pktdrv_found2
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
	mov	dx,errpkt
	jmp	die

pktclass_ok:
	mov	ah,2			; pktdrv: access_type
	mov	bx,dx			; if_type
	mov	al,ch			; if_class
	mov	dl,cl			; if_number
	mov	si,type_arp		; ds:si = type
	mov	di,arp_receiver		; es:di = receiver
	pushm	bx, cx, dx
	mov	cx,2
	call	pktdrv_call
	popm	dx, cx, bx
	jc	pktfail
	mov	[handle_arp],ax

	mov	ah,2			; pktdrv: access_type
	mov	al,ch			; if_class
	mov	si,type_ip		; ds:si = type
	mov	di,ip_receiver		; es:di = receiver
	mov	cx,2
	call	pktdrv_call
	jc	pktfail
	mov	[handle_ip],ax

	; fetch hw address (why does this need a handle instead of an
	; if_class/type/numer?)
	mov	bx,ax			; handle
	mov	ah,6			; pktdrv: get_address
	mov	di,my_hwaddr
	mov	cx,6
	call	pktdrv_call
	jc	pkterr
	cmp	cx,6
	jne	pkterr

	; fill out broadcast hw address
	mov	di,server_hwaddr
	xor	ax,ax
	dec	ax
	mov	cx,3
	rep	stosw

	; see if we have an IP address; if so, skip DHCP
	mov	si,my_ip
	lodsw
	mov	bx,ax
	lodsw
	or	ax,bx
	jnz	.have_ip

	; use DHCP to obtain our IP address
	call	dhcp_request
	jc	.have_ip

	mov	dx,dhcp_failure
	jmp	pkterr_msg

.have_ip:
	; tell the user about our IP address
	mov	ah,9
	mov	dx,ip_success
	int	21h

	mov	si,my_ip
	call	printip

	mov	ah,9
	mov	dx,crlf
	int	21h

	; copy nfs server to the server IP - this is the only host we'll be
	; talking to from now on
	mov	si,nfs_server_ip
	mov	di,server_ip
	movsw
	movsw

	; fetch the server's hw address
	call	arp_get_server
	jc	arp_server_ok

	mov	dx,arp_failed
	jmp	pkterr_msg

arp_server_ok:
	mov	ah,9
	mov	dx,arp_msg
	int	21h

	mov	si,server_hwaddr
	call	printhwaddr

	mov	ah,9
	mov	dx,crlf
	int	21h

	; look up mountd port first
	mov	bx,1
	call	portmap_get
	jc	portmap_ok

	mov	dx,mountport_failed
	jmp	pkterr_msg

portmap_ok:
	; then look up nfsd port
	mov	bx,2
	call	portmap_get
	jc	nfsd_ok

	mov	dx,nfsport_failed
	jmp	pkterr_msg

nfsd_ok:
	; now mount our path
	mov	si,[mount_path]
	call	mountd_mount
	jc	mount_ok

	mov	dx,mount_failed
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
	mov	dx,resident_end
	shr	dx,1
	shr	dx,1
	shr	dx,1
	shr	dx,1
	inc	dx
	int	21h

pkterr_msg:
	mov	ah,9
	int	21h
	mov	dx,crlf
	int	21h
pkterr:
	call	pkt_unhook
	int	20h

; NON-RESIDENT DATA
msg_bad_pkt	db	'error: packet driver interrupt not in range 60..80$'
msg_bad_ip	db	'error: cannot parse client ip$'
msg_unknown_arg	db	'error: unrecognized parameter$'
msg_no_path	db	'error: mount path not supplied$'
msg_ip_error	db	'error: mount path invalid, must be server_ip:path$'
msg_usage	db	'NFSPKT - NFS filesystem driver for DOS (GPLv3)',10,13
		db	'(c) 2020 Rink Springer <rink@rink.nu>',10,13
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

pktdrv_sig	db	"PKT DRVR",0
pktdrv_siglen	equ	$-pktdrv_sig
