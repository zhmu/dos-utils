pushm	    macro   r1, r2, r3, r4, r5, r6, r7, r8
	    push    r1
	    ifnb <r2>
	    push    r2
	    endif
	    ifnb <r3>
	    push    r3
	    endif
	    ifnb <r4>
	    push    r4
	    endif
	    ifnb <r5>
	    push    r5
	    endif
	    ifnb <r6>
	    push    r6
	    endif
	    ifnb <r7>
	    push    r7
	    endif
	    ifnb <r8>
	    push    r8
	    endif
	    endm

popm	    macro   r1, r2, r3, r4, r5, r6, r7, r8
	    pop    r1
	    ifnb <r2>
	    pop    r2
	    endif
	    ifnb <r3>
	    pop    r3
	    endif
	    ifnb <r4>
	    pop    r4
	    endif
	    ifnb <r5>
	    pop    r5
	    endif
	    ifnb <r6>
	    pop    r6
	    endif
	    ifnb <r7>
	    pop    r7
	    endif
	    ifnb <r8>
	    pop    r8
	    endif
	    endm
