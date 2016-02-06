; ISR_example.asm: a) Increments/decrements a BCD variable every half second using
; an ISR for timer 2; b) Generates a 2kHz square wave at pin P3.7 using
; an ISR for timer 0; and c) in the 'main' loop it displays the variable
; incremented/decremented using the ISR for timer 0 on the LCD.  Also resets it to 
; zero if the 'BOOT' pushbutton connected to P4.5 is pressed.
$NOLIST
$MODLP52
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

SOUND_OUT     equ P3.7

; Reset vector
org 0000H
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0003H
	reti

; Timer/Counter 0 overflow interrupt vector
org 000BH
	ljmp Timer0_ISR

; External interrupt 1 vector (not used in this code)
org 0013H
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 001BH
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0023H 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 002BH
	ljmp Timer2_ISR

dseg at 30h
Count1ms: ds 2
buffer_temp: ds 2
buffer_time: ds 2
soak_temp: ds 2
soak_time: ds 2
reflow_temp: ds 2
reflow_time: ds 2

bseg
seconds_flag: dbit 1 ; Set to one in the ISR every time 1000 ms had passed
oven_on: dbit 1 ; One means oven is on
reflow_setup: dbit 1 ; One means user is setting reflow
cseg
; These 'equ' must match the wiring between the microcontroller and the LCD!
LCD_RS equ P1.4
LCD_RW equ P1.5
LCD_E  equ P1.6
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5
; User control buttons
USR_SET equ P2.6
USR_UP equ P2.3
USR_DOWN equ P2.0
USR_ALRM equ P0.6

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;                     1234567890123456    <- This helps determine the position of the counter
Oven_Default_Message1: db 's:xxxs  xxxC xxx', 0
Oven_Default_Message2: db 'r:xxxs  xxxC    ', 0
Oven_Off_Message: db 'off', 0
Oven_On_Message:  db 'on ', 0
Colon: db ':', 0
Soak_Or_Reflow_Message1:   db '  soak  reflow  ', 0
Soak_Or_Reflow_Message2:   db '  (up)  (down)  ', 0
Time_Message:     db 'time: xxxx      ', 0
Temp_Message:     db 'temp: xxxxC     ', 0
Okay_Message:     db 'xxxxs xxxxC  ok?', 0
Continue:         db 'set to continue ', 0
Clear:            db '                ', 0
Space: db ' ', 0
                      
;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
	push acc
	push psw
	mov a, TMOD
	anl a, #0xf0 ; Clear the bits for timer 0
	orl a, #0x01 ; Configure timer 0 as 16-timer
	mov TMOD, a
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	; Enable the timer and interrupts
	setb ET0  ; Enable timer 0 interrupt
	setb TR0  ; Start timer 0
	setb EA   ; Enable Global interrupts
	pop psw
	pop acc
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P3.7 ;
;---------------------------------;
Timer0_ISR:
	; Define a latency correction for the timer reload
	CORRECTION EQU (4+4+2+2+4+4) ; lcall+ljmp+clr+mov+mov+setb



no_alarms:
	; In mode 1 we need to reload the timer.
	clr TR0
	mov TH0, #high(TIMER0_RELOAD+CORRECTION)
	mov TL0, #low(TIMER0_RELOAD+CORRECTION)
	setb TR0
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
    push acc
	mov T2CON, #0 ; Stop timer.  Autoreload mode.
	; One millisecond interrupt
	mov RCAP2H, #high(TIMER2_RELOAD)
	mov RCAP2L, #low(TIMER2_RELOAD)
	; Set the 16-bit variable Count1ms to zero
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Enable the timer and interrupts
	setb ET2  ; Enable timer 2 interrupt
	setb TR2  ; Enable timer 2
	setb EA   ; Enable Global interrupts
	pop acc
	ret

;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically in ISR
	cpl P3.6 ; To check the interrupt rate with oscilloscope. It must be a 1 ms pulse.
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw

	; Increment the 16-bit counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:
	; Check if one second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), exit
	mov a, Count1ms+1
	cjne a, #high(1000), exit
	
	; 1000 milliseconds have passed.  Set a flag so the main program knows
	setb seconds_flag ; Let the main program know half second had passed
	cpl TR1 ; This line makes a beep-silence-beep-silence sound
	; Reset the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
exit:	
	pop psw
	pop acc
	reti

;---------------------------------;
; Main program. Includes hardware ;
; initialization and 'forever'    ;
; loop.                           ;
;---------------------------------;
main:
	; Initialization
	mov SP, #7FH
	mov PMOD, #0 ; Configure all ports in bidirectional mode
	lcall Timer0_Init
	lcall Timer2_Init
	lcall LCD_4BIT
	; For convenience a few handy macros are included in 'LCD_4bit.inc':
	setb seconds_flag
	clr reflow_setup
	clr oven_on
buffer_initial:
	mov buffer_temp + 1, #0x03
	mov buffer_temp, #0x50

	mov buffer_time + 1, #0x01
	mov buffer_time, #0x45
soak_initial:
	mov soak_time + 1, #0x02
	mov soak_time, #0x50

	mov soak_temp + 1, #0x01
	mov soak_temp, #0x45

reflow_initial:
	mov reflow_time + 1, #0x02
	mov reflow_time, #0x50

	mov reflow_temp + 1, #0x01
	mov reflow_temp, #0x45

	; After initialization the program stays in this 'forever' loop
loop:

	Set_Cursor(1, 1)
	Send_Constant_String(#Oven_Default_Message1)
	Set_Cursor(2, 1)
	Send_Constant_String(#Oven_Default_Message2)	

loop_a:
	jnb seconds_flag, loop_a
	clr seconds_flag ; We clear this flag in the main loop, but it is set in the ISR for timer 0

oven:	
	jb USR_ALRM, check_if_on
	Wait_Milli_Seconds(#50)	 
	jb USR_ALRM, check_if_on
	Wait_Milli_Seconds(#50)
	jnb USR_ALRM, $
	cpl oven_on

check_if_on:
	jb oven_on, oven_is_on
	ljmp oven_is_off
	
oven_is_on:	
	Set_Cursor(1, 14)
        Send_Constant_String(#Oven_On_Message)
	sjmp draw_values
    
oven_is_off:	
	Set_Cursor(1, 14)
        Send_Constant_String(#Oven_Off_Message) 

draw_values:
	Set_Cursor(1, 2)
	Display_BCD(soak_time + 1)
	Set_Cursor(1, 4)
	Display_BCD(soak_time)
 	Set_Cursor(2, 2)
	Display_BCD(reflow_time + 1)
	Set_Cursor(2, 4)
	Display_BCD(reflow_time)

	Set_Cursor(1, 8)
	Display_BCD(soak_temp + 1)
	Set_Cursor(1, 10)
	Display_BCD(soak_temp)
 	Set_Cursor(2, 8)
	Display_BCD(reflow_temp + 1)
	Set_Cursor(2, 10)
	Display_BCD(reflow_temp)

	Set_Cursor(1, 2)
	Send_Constant_String(#Colon)
	Set_Cursor(2, 2)
	Send_Constant_String(#Colon)

	Set_Cursor(1, 8)
	Send_Constant_String(#Space)
	Set_Cursor(2, 8)
	Send_Constant_String(#Space)



user_control:
	; if oven is running, user cannot adjust settings
	jnb oven_on, setup_mode
	ljmp loop_a
setup_mode:
   	; Enter setup mode if user presses 'set' button
   	jb USR_SET, no_setup  ; if the 'set' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_SET, no_setup; if the 'set' button is not pressed skip
	jnb USR_SET, set_pressed		; wait for button release
	
no_setup:
	ljmp loop_a
 
set_pressed:
	Set_Cursor(1, 1)
	Send_Constant_String(#Soak_Or_Reflow_Message1)    
	Set_Cursor(2, 1)
	Send_Constant_String(#Soak_Or_Reflow_Message2)  

choose_time:    
   ; Enter time mode if user presses 'up' button
   	jb USR_UP, choose_alarm  ; if the 'up' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_UP, choose_alarm  ; if the 'up' button is not pressed skip
	jnb USR_UP, time_buffer	; wait for button release

choose_alarm:
   ; Enter alarm mode if user presses 'down' button
   	jb USR_DOWN, choose_time  ; if the 'down' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_DOWN, choose_time  ; if the 'up' button is not pressed skip
	jnb USR_DOWN, reflow_bit_set; wait for button release

reflow_bit_set:
	setb reflow_setup
	
time_buffer:
	Set_Cursor(1, 1)
    	Send_Constant_String(#Time_Message)
 	Set_Cursor(2, 1)
    	Send_Constant_String(#Continue) 
    
time_loop:
	Set_Cursor(1, 9)
	Display_BCD(buffer_time)
	
	Set_Cursor(1, 7)
	Display_BCD(buffer_time + 1)
	
	Wait_Milli_Seconds(#150)	; delay so user doesn't accidentally press something

        ;jump to minute if user presses 'set' button
   	jb USR_SET, time_select; if the 'set' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_SET, time_select; if the 'set' button is not pressed skip
	jnb USR_SET, temp_buffer         ; wait for button release
time_select:
time_up_button:
   	jb USR_UP, time_down_button  
	Wait_Milli_Seconds(#100)	 
	jb USR_UP, time_down_button  
	jnb USR_UP, time_up
time_down_button:
   	jb USR_DOWN,time_loop 
	Wait_Milli_Seconds(#100)	 
	jb USR_DOWN,time_loop 
	jnb USR_DOWN, time_down

time_up:
	mov a, buffer_time
	cjne a, #0x99, time_up_under_99
	mov a, #0x00
	lcall buffer_time_da
time_hundreds_up:
	mov a, buffer_time + 1
	cjne a, #0x08, time_hundreds_up_over
	mov a, #0x00
	mov buffer_time + 1, a
	sjmp time_loop
time_hundreds_up_over:
	add a, #0x01
	da a
	mov buffer_time + 1, a
	ljmp time_loop
time_up_under_99:
	add a, #0x01
	lcall buffer_time_da
	ljmp time_loop

time_down:
	mov a, buffer_time
	cjne a, #0x00, time_down_over_0
	mov a, #0x99
	lcall buffer_time_da
time_hundreds_down:
	mov a, buffer_time + 1
	cjne a, #0x00, time_hundreds_down_under
	mov a, #0x08
	da a
	mov buffer_time + 1, a
	ljmp time_loop
time_hundreds_down_under:
	add a, #0x99
	da a
	mov buffer_time +1, a	
	ljmp time_loop
time_down_over_0:
	add a, #0x99
	lcall buffer_time_da
	ljmp time_loop

;temperature 
temp_buffer:
   	Set_Cursor(1, 1)
        Send_Constant_String(#Temp_Message) 
    
temp_loop:
	Set_Cursor(1, 9)
	Display_BCD(buffer_temp)
	
	Set_Cursor(1, 7)
	Display_BCD(buffer_temp + 1)
	
	Wait_Milli_Seconds(#150)	; delay so user doesn't accidentally press something

   ; jump to minute if user presses 'set' button
   	jb USR_SET, temp_select; if the 'set' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_SET, temp_select; if the 'set' button is not pressed skip
	jnb USR_SET, ok_message; wait for button release
	
temp_select:
temp_up_button:
   	jb USR_UP, temp_down_button  
	Wait_Milli_Seconds(#100)	 
	jb USR_UP, temp_down_button  
	jnb USR_UP, temp_up
temp_down_button:
   	jb USR_DOWN,temp_loop 
	Wait_Milli_Seconds(#100)	 
	jb USR_DOWN,temp_loop 
	jnb USR_DOWN, temp_down

temp_up:
	mov a, buffer_temp
	cjne a, #0x99, temp_up_under_99
	mov a, #0x00
	lcall buffer_temp_da
temp_hundreds_up:
	mov a, buffer_temp + 1
	cjne a, #0x08, temp_hundreds_up_over
	mov a, #0x00
	mov buffer_temp + 1, a
	sjmp temp_loop
temp_hundreds_up_over:
	add a, #0x01
	da a
	mov buffer_temp + 1, a
	ljmp temp_loop
temp_up_under_99:
	add a, #0x01
	lcall buffer_temp_da
	ljmp temp_loop

temp_down:
	mov a, buffer_temp
	cjne a, #0x00, temp_down_over_0
	mov a, #0x99
	lcall buffer_temp_da
temp_hundreds_down:
	mov a, buffer_temp + 1
	cjne a, #0x00, temp_hundreds_down_under
	mov a, #0x08
	da a
	mov buffer_temp + 1, a
	ljmp temp_loop
temp_hundreds_down_under:
	add a, #0x99
	da a
	mov buffer_temp + 1, a	
	ljmp temp_loop
temp_down_over_0:
	add a, #0x99
	lcall buffer_temp_da
	ljmp temp_loop

buffer_time_da:
	da a
	mov buffer_time, a
	ret
	
buffer_temp_da:
	da a
	mov buffer_temp, a
	ret

ok_message:
   	Set_Cursor(1, 1)
	Send_Constant_String(#Okay_Message) 	
	Set_Cursor(2, 1)
	Send_Constant_String(#Continue)

	Set_Cursor(1, 1)
	Display_BCD(buffer_time + 1)
	Set_Cursor(1, 3)
	Display_BCD(buffer_time)

	Set_Cursor(1, 7)
	Display_BCD(buffer_temp + 1)
	Set_Cursor(1, 9)
	Display_BCD(buffer_temp)	

	Set_Cursor(1, 1)
	Send_Constant_String(#Space)
	Set_Cursor(1, 7)
	Send_Constant_String(#Space)

ok_buffer:
   	
	Wait_Milli_Seconds(#200)	; delay so user doesn't accidentally press something

	; jump to second if user presses 'set' button
   	jb USR_SET, choose_ok  ; if the 'set' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_SET, choose_ok  ; if the 'set' button is not pressed skip
	jnb USR_SET, writeback_soak		; wait for button release

choose_ok:
ok_up_button:
   	jb USR_UP, ok_down_button  
	Wait_Milli_Seconds(#100)	 
	jb USR_UP, ok_down_button  
	jnb USR_UP, ok_up
ok_down_button:
   	jb USR_DOWN, ok_buffer  
	Wait_Milli_Seconds(#100)	 
	jb USR_DOWN, ok_buffer  
	jnb USR_DOWN, ok_down

ok_up:
	lcall reset_buffer
	Wait_Milli_Seconds(#200)
	ljmp loop
	
ok_down:
	lcall reset_buffer
	Wait_Milli_Seconds(#200)
	ljmp loop  
	 
writeback_soak:
	jb reflow_setup, writeback_reflow
	
	mov a, buffer_time + 1
	mov soak_time + 1, a
	mov a, buffer_time
	mov soak_time, a

	mov a, buffer_temp + 1
	mov soak_temp + 1, a
	mov a, buffer_temp
	mov soak_temp, a

	sjmp done_writeback
	
writeback_reflow:
	
	mov a, buffer_time + 1
	mov reflow_time + 1, a
	mov a, buffer_time
	mov reflow_time, a

	mov a, buffer_temp + 1
	mov reflow_temp + 1, a
	mov a, buffer_temp
	mov reflow_temp, a

	sjmp done_writeback
	
done_writeback:
	lcall reset_buffer
	Wait_Milli_Seconds(#200)
	ljmp loop	

reset_buffer:
	mov buffer_time + 1, #0x02
	mov buffer_time, #0x50
	mov buffer_temp + 1, #0x01
	mov buffer_temp, #0x45
	clr reflow_setup
	ret    
     
END
