RESTEXT		segment word public 'CODE'

;
; this file must be the final object file in the RESTEXT segment!
;

public resident_end

; symbol to determine the end of the resident code/data area
resident_end    db  0

RESTEXT	ends
	end
