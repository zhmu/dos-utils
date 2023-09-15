RESTEXT		segment word public 'CODE'
            org 100h

extern main: proc

public pktdrv_call

; pktdrv_call will be patched to INT xx, RET; this conveniently overwrites
; the bootstrap jmp instruction, saving a whole 3 bytes
pktdrv_call:

; entry point (overwritten)
_entry:
            jmp main


include settings.inc
include defines.inc
include macro.inc

;
; this file contains all resident data
;
public pktbuf
public arpbuf
public xmitbuf
public recvbuf
public mount_fh
public temp_fh
public temp_fh2
public handle_slots
public dir_slots
public next_dir_slot

public readdir_fname
public readdir_flen
public readdir_type
public readdir_len
public readdir_time
public readdir_date

public xid
public ip_id
public my_ip
public my_hwaddr
public server_ip
public server_hwaddr
public server_hwaddr_valid
public recv_len

public handle_arp
public handle_ip

public rpc_progmap
public rpc_portmap

public rpc_versionmap

public sda
public drive_cds
public drive_no

public hextab

pktbuf		db	PKTBUF_LEN dup (0)
arpbuf		db	ARPBUF_LEN dup (0)
xmitbuf		db	PKTBUF_LEN dup (0)
recvbuf		db	PKTBUF_LEN dup (0)
mount_fh	db	FH3SIZE+1 dup (0)
temp_fh		db	FH3SIZE+1 dup (0)
temp_fh2	db	FH3SIZE+1 dup (0)
handle_slots	db	(FH3SIZE+1)*NUM_HANDLE_SLOTS dup (0)
; each dir slot contains handle, cookie, cookiev
dir_slots	db	DIR_SLOT_SIZE*NUM_DIR_SLOTS dup (0)
next_dir_slot	db	0

; readdir state
readdir_fname	dw	0	; offset in ds of filename
readdir_flen	dw	0	; filename length (bytes)
readdir_type	dw	0	; file type
readdir_len	dd	0	; file length (bytes)
readdir_time	dw	0
readdir_date	dw	0

xid		    dd	0
ip_id		dw	0
my_ip		dd	0
my_hwaddr	db	HWADDR_LEN dup (0)
server_ip	db	255, 255, 255, 255
server_hwaddr	db	HWADDR_LEN dup (0)
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

RESTEXT ends
        end _entry
