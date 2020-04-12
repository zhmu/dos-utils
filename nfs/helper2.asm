; vim:set ts=8 sw=8 noet:

; in: ax = number to print
print_dec:
	or	ax,ax
	jnz	.p_nonzero

	mov	ax,0e30h
	int	10h
	ret

.p_nonzero:
	push	bp

	mov	si,dec_tab
	mov	di,hextab
	xor	bh,bh
	xor	cx,cx

.p_loop:
	xchg	ax,bp
	lodsw
	xchg	ax,bp
	or	bp,bp
	jz	.p_done
	xor	dx,dx
	div	bp

	mov	ah,ch
	or	ax,ax
	jz	.p_skip

	mov	bl,al
	mov	al,[di+bx]
	mov	ah,0eh
	int	10h
	inc	ch

.p_skip:
	mov	ax,dx
	jmp	.p_loop

.p_done:
	pop	bp
	ret

; converts ascii al to char in al
; results: cf=1 on error
; 21 bytes
parse_char:
	cmp	al,'9'
	ja	.p_1
	cmp	al,'0'
	jb	.p_bad

	sub	al,'0'
	jmp	.p_ok

.p_1:	cmp	al,'F'
	ja	.p_2
	cmp	al,'A'
	jb	.p_bad

	sub	al,'A'-10
	jmp	.p_ok

.p_2:	cmp	al,'f'
	ja	.p_bad
	cmp	al,'a'
	jb	.p_bad
	sub	al,'a'-10

.p_ok:
	clc
	ret

.p_bad:
	stc
	ret

; converts asciiz in ds:si to ax
; in: bx = 10 for decimal, 16 for hex
; out: al = last char parsed, dx = value, si updated
parse_int:
	push	bp
	xor	bp,bp
.p_loop:
	lodsb
	or	al,al
	jz	.p_done

	xor	ah,ah
	call	parse_char
	jc	.p_done
	cmp	ax,bx
	jae	.p_done

	push	ax
	mov	ax,bp
	mul	bx
	mov	bp,ax
	pop	ax

	add	bp,ax
	jmp	.p_loop

.p_done:
	mov	dx,bp
	pop	bp
	ret

; parse the a.b.c.d ip address in ds:si to 4-bytes in es:di
; returns; carry=0 on success, si updated, al = next char
parse_ip:
	mov	bx,10
	call	parse_int
	cmp	al,'.'
	jne	.p_err
	or	dh,dh
	jnz	.p_err
	mov	al,dl
	stosb

	call	parse_int
	cmp	al,'.'
	jne	.p_err
	or	dh,dh
	jnz	.p_err
	mov	al,dl
	stosb

	call	parse_int
	cmp	al,'.'
	jne	.p_err
	or	dh,dh
	jnz	.p_err
	mov	al,dl
	stosb

	call	parse_int
	or	dh,dh
	jnz	.p_err

	push	ax
	mov	al,dl
	stosb
	pop	ax
	clc
	ret

.p_err:
	stc
	ret

dec_tab:
	dw	10000, 1000, 100, 10, 1, 0
