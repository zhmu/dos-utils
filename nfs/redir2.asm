; vim:set ts=8 sw=8 noet:

;
; redirector, not resident pieces
;
cds_entry_len	equ	58h	; length of a single cds entry, in bytes
no_drives	db	'No available drives found$'
drive_msg	db	'Using ?:$'
uninstalled_msg	db	'Uninstalled$'

	; returns es:di = cds pointer
get_cds:
	mov	ah,52h		; dos 3+: get list of lists
	int	21h

	les	di,[es:bx+16h]	; get cds pointer
	ret

redir_unhook:
	;
	; removes our CDS entry and interrupt handler
	;

	; unhook our drive from cds list
	call	get_cds
	xor	dh,dh
	mov	dl,[drive_no]
	dec	dx		; as drive_no is 1-based
	mov	ax,cds_entry_len
	mul	dx
	mov	di,ax
	and	word [es:di+43h],3fffh	; clear top bits to mark invalid

	; restore the previous int2f
	push	ds
	mov	ax,word [old_2f+2]
	mov	dx,word [old_2f]
	mov	ds,ax
	mov	ax,252fh	; dos: set int handlr
	int	21h
	pop	ds

	ret

	; initializes the redirectory
	; result: carry=1 -> success
redir_init:
	mov	ax,cs

	mov	ax,5d06h	; dos: get sda address
	int	21h
	mov	word [cs:sda],si
	mov	word [cs:sda+2],ds

	push	cs
	pop	ds

	call	get_cds
	xor	ch,ch
	mov	cl,[es:bx+21h]	; number of drives

	mov	al,1
	mov	[drive_no],al	; start at 1

find_drive:
	mov	ax,[es:di+43h]	; get drive attributes
	and	ax,0c000h	; valid?
	jz	got_drive	; no -> got one we can use

	; use the next drive
	inc	byte [drive_no]
	add	di,cds_entry_len
	loop	find_drive

	; nothing found?
	mov	ah,9
	mov	dx,no_drives
	int	21h
	clc
	ret

got_drive:
	; cds entry is in es:di here, store it
	mov	word [drive_cds],di
	mov	word [drive_cds+2],es
	mov	al,[drive_no]
	add	al,'@'
	mov	cl,al

	; edit cds, set network+physical bits
	or	word [es:di+43h],0c000h
	mov	word [es:di+49h],0ffffh	; ifs pointer
	mov	word [es:di+4bh],0ffffh
	mov	byte [es:di+4fh],2		; root slash offset
	; set cds directory to the root
	stosb
	mov	al,':'
	stosb
	mov	al,'\'
	stosb
	xor	al,al
	stosb

	; now display the 'we got drive' banner
	mov	ah,9
	mov	dx,drive_msg
	mov	[drive_msg+6],cl
	int	21h

	; grab the int2f handler
	mov	ax,352fh
	int	21h
	mov	word [old_2f],bx
	mov	word [old_2f+2],es

	; activate the new one
	mov	ax,252fh
	mov	dx,int_2f
	int	21h

	mov	ah,48h		; dos: free memory
	mov	es,[ds:2ch]	; environment table
	int	21h
	ret
