; vim:set ts=8 sw=8 noet:

; prints the digit in al [0..9] in decimal
printdigit:
	push	ax
	add	al,'0'
	mov	ah,0eh
	int	10h
	pop	ax
	ret

; prints the number in al
printnumber:
	xor	ch,ch
	xor	ah,ah
	mov	bl,al
	cmp	bl,100
	jb	printnumber1

	inc	ch
	mov	cl,100
	div	cl		; al = ax / 100, ah = ax % 100
	mov	bl,ah
	call	printdigit

printnumber1:
	or	ch,ch		; print something already?
	jnz	printnumber3	; yes, always print this digit
	mov	bl,al
	cmp	bl,10
	jb	printnumber2

printnumber3:
	xor	ah,ah
	mov	al,bl
	mov	cl,10
	div	cl		; al = ax / 10, ah = ax % 10
	call	printdigit
	mov	al,ah

printnumber2:
	jmp	printdigit

; prints the ip address in si
printip:
	mov	cx,4
printip2:
	lodsb
	push	cx
	call	printnumber
	pop	cx
	dec	cx
	jz	printip3
	mov	ax,0e2eh	; video: print '.'
	int	10h
	jmp	printip2
printip3:
	ret

; print al as hexdecimal digit
printhexdigit:
	xor	bh,bh
	mov	bl,al
	mov	al,[hextab+bx]
	mov	ah,0eh		; video: print digit in al
	int	10h
	ret

; print al as hexdecimal
printhex:
	push	ax
	shr	al,1
	shr	al,1
	shr	al,1
	shr	al,1
	call	printhexdigit
	pop	ax
	and	al,15
	jmp	printhexdigit

; print ax as hexdecimal
printhex_word:
	push	ax
	mov	al,ah
	call	printhex
	pop	ax
	jmp	printhex

; print mac address in ds:si
printhwaddr:
	mov	cx,6
printhwaddr_l:
	lodsb
	call	printhex

	cmp	cl,1
	jne	printhwaddr_n

	ret

printhwaddr_n:
	mov	al,':'		; note: uses that ah=0eh
	int	10h
	loop	printhwaddr_l

	; NOTREACHED
