cseg

;---------------------------------;
; Button Macro                    ;
; Button(port, goto, else)        ;
;---------------------------------;
Button mac
	 jb %0, %2  
	 Wait_Milli_Seconds(#50)
	 jb %0, %2
	 jnb %0, %1
endmac





