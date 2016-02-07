$NOLIST
$MODLP52
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

BOOT_BUTTON     EQU P4.5 ;reset button
SOUND_OUT       EQU P3.7
PWM_PIN			EQU P0.0 ;change later
START_BUTTON 	EQU P0.2 ;start button

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
Count1ms:     	ds 2 ; Used to determine when half second has passed
CURRENT_STATE:	ds 1 ;current state 

;FSM VARIABLES
SEC_COUNTER:	ds 1 ;timer
TEMP:			ds 1 ;temperature

;PWM VARIABLES
PWM_FLAG:		ds 1 ;
PWM_COUNTER:	ds 1 ;timing
PWM_OFF:		ds 1 ;constants
PWM_LOW:		ds 1
PWM_HIGH:		ds 1

;BEEPER FEEDBACK VARIABLES
;SHORT_BEEP:		ds 1
SHORT_BEEP_COUNTER: ds 1
;LONG_BEEP:		ds 1
;LONG_BEEP_COUNTER: ds 1

bseg
half_seconds_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed
start_reload_flag: dbit 1
start_sec_counter_state2_flag: dbit 1
start_sec_counter_state4_flag: dbit 1
state3_transition_flag: dbit 1
state5_transition_flag: dbit 1
state_transition_beep_flag: dbit 1
long_beep_flag: dbit 1


cseg
; These 'equ' must match the wiring between the microcontroller and the LCD!
LCD_RS equ P1.4
LCD_RW equ P1.5
LCD_E  equ P1.6
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5
$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;
Display_State_Message:  db 'State:', 0

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 0                     ;
;---------------------------------;
Timer0_Init:
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
	ret

;---------------------------------;
; ISR for timer 0.  Set to execute;
; every 1/4096Hz to generate a    ;
; 2048 Hz square wave at pin P3.7 ;
;---------------------------------;
Timer0_ISR:
	; Define a latency correction for the timer reload
	CORRECTION EQU (4+4+2+2+4+4) ; lcall+ljmp+clr+mov+mov+setb
	; In mode 1 we need to reload the timer.
	clr TR0
	mov TH0, #high(TIMER0_RELOAD+CORRECTION)
	mov TL0, #low(TIMER0_RELOAD+CORRECTION)
	setb TR0
	
	;push acc
	;push psw
	
	;************BEEPER************
	; check to see if START_BUTTON is pressed
	jb start_reload_flag, beep_transition ; if start_reload_flag is not yet set, skip over
	cpl P3.7 ; turn on speaker

beep_transition:
	jb state_transition_beep_flag, long_beep_transition
	cpl P3.7 ; turn on speaker
long_beep_transition:
	jb long_beep_flag, CHECK_OFF
	cpl P3.7
	
	;**************PWM**************
	;CHANGE THE CODE: CLR THE PIN BELOW, SET IT ON ABOVE AT 0
CHECK_OFF:
	push acc
	push psw
	
	mov a, PWM_FLAG
	cjne a, PWM_OFF, CHECK_LOW
	
	setb PWM_PIN
	
	sjmp CHECK_COMPLETE

CHECK_LOW:
	mov a, PWM_FLAG
	cjne a, PWM_LOW, CHECK_HIGH
	
	mov a, PWM_COUNTER
	cjne a, PWM_LOW, CHECK_COMPLETE

	setb PWM_PIN
	
	sjmp CHECK_COMPLETE

CHECK_HIGH:
	clr PWM_PIN

CHECK_COMPLETE:
	;incrementing
	mov a, PWM_COUNTER
	add a, #1
	mov PWM_COUNTER, a
	
	;checking for end of PWM
	mov a, PWM_COUNTER
	cjne a, PWM_HIGH, FINISH_T0 ;PWM_HIGH is the max counter

RESET_PWM_COUNTER:
	mov a, #0
	mov PWM_COUNTER, a
	
	;only change when PWM is low
	mov a, PWM_FLAG
	cjne a, PWM_LOW, FINISH_T0
	clr PWM_PIN			
	
FINISH_T0:
	pop psw
	pop acc
	reti

;---------------------------------;
; Routine to initialize the ISR   ;
; for timer 2                     ;
;---------------------------------;
Timer2_Init:
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
	; Check if 1 second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), Timer2_ISR_done
	mov a, Count1ms+1
	cjne a, #high(1000), Timer2_ISR_done
	
	; 1 second has passed.  Set a flag so the main program knows
	setb half_seconds_flag ; Let the main program know half second had passed
	;cpl TR1 ; This line makes a beep-silence-beep-silence sound

	;************COUNTER************
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
	mov a, TEMP
	add a, #0x03
	;da a 
	mov TEMP, a
	; Increment the BCD counter
	;mov a, SEC_COUNTER
	;add a, #0x01
	;da a
	;mov SEC_COUNTER, a
	
	;************BEEPER************
	; condition to even consider SHORT_BEEP_COUNTER
	jb start_reload_flag, state_transition_beeps ; if start_reload_flag in main is not yet set, skip over
	mov a, SHORT_BEEP_COUNTER
	add a, #0x01
	da a 
	mov SHORT_BEEP_COUNTER, a 
	cjne a, #0x01, Timer2_ISR_done
	cpl start_reload_flag ; clear flag & turn off speaker
	mov SHORT_BEEP_COUNTER, #0x00
	
	;****STATE TRANSITION BEEPS****
state_transition_beeps:
	jb state_transition_beep_flag, long_beep
	mov a, SHORT_BEEP_COUNTER
	add a, #0x01
	da a 
	mov SHORT_BEEP_COUNTER, a 
	cjne a, #0x01, Timer2_ISR_done
	cpl state_transition_beep_flag ; clear flag & turn off speaker
	mov SHORT_BEEP_COUNTER, #0x00
	
	;********LONG BEEP*********
long_beep:
	jb long_beep_flag, check_transition_2_3
	mov a, SHORT_BEEP_COUNTER
	add a, #0x01
	da a
	mov SHORT_BEEP_COUNTER, a
	cjne a, #0x03, Timer2_ISR_done
	cpl long_beep_flag ; clear flag & turn off long beep speaker
	mov SHORT_BEEP_COUNTER, #0x00
	
	;****STATE TRANSITIONS*****
check_transition_2_3:
	;state 2->3 transition
	jb start_sec_counter_state2_flag, check_transition_4_5 ; if state3_transition_flag in main is not yet set, skip over
	mov a, SEC_COUNTER
	add a, #0x01
	da a
	mov SEC_COUNTER, a
	cjne a, #0x10, Timer2_ISR_done
	cpl state3_transition_flag ; set state3_transition_flag for main 
	cpl start_sec_counter_state2_flag ; clear flag
	mov SEC_COUNTER, #0x00
	
check_transition_4_5:
	;state 4->5 transition
	jb start_sec_counter_state4_flag, Timer2_ISR_done ; if state3_transition_flag in main is not yet set, skip over
	mov a, SEC_COUNTER
	add a, #0x01
	da a
	mov SEC_COUNTER, a
	cjne a, #0x15, Timer2_ISR_done 
	cpl state5_transition_flag ; set state5_transition_flag for main
	cpl start_sec_counter_state4_flag ; clear flag
	mov SEC_COUNTER, #0x00
	
Timer2_ISR_done:
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
	Set_Cursor(1, 1)			
	Send_Constant_String(#Display_State_Message)
	
	setb half_seconds_flag
	mov SEC_COUNTER, #0
	mov CURRENT_STATE, #0
	mov PWM_COUNTER, #0
	mov PWM_FLAG, PWM_OFF
	mov PWM_OFF, #0
	mov PWM_LOW, #1 ;because weird bug (ask kiron)
	mov PWM_HIGH, #10
	;mov SHORT_BEEP, #0
	mov SHORT_BEEP_COUNTER, #0x00
	;mov LONG_BEEP, #0
	;mov LONG_BEEP_COUNTER, #0
	mov TEMP, #0

	; After initialization the program stays in this 'forever' loop
forever:
	jb BOOT_BUTTON, loop_a  ; if the 'BOOT' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb BOOT_BUTTON, loop_a  ; if the 'BOOT' button is not pressed skip
	jnb BOOT_BUTTON, $		; wait for button release
	; A clean press of the 'BOOT' button has been detected, reset the BCD counter.
	; But first stop the timer and reset the milli-seconds counter, to resync everything.
	clr TR0
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
	mov SEC_COUNTER, #0x00
	mov CURRENT_STATE, #0x00
	mov PWM_COUNTER, #0x00
	mov PWM_FLAG, PWM_OFF
	;mov SHORT_BEEP, #0x00
	mov SHORT_BEEP_COUNTER, #0x00
	;mov LONG_BEEP, #0x00
	;mov LONG_BEEP_COUNTER, #0x00
	setb TR0                ; Re-enable the timer
	sjmp loop_b             ; Display the new value
loop_a:
	jnb half_seconds_flag, forever
loop_b:
    clr half_seconds_flag ; We clear this flag in the main forever, but it is set in the ISR for timer 0
	
	mov a, CURRENT_STATE
STATE0:
	cjne a, #0x00, STATE1 ; change this back to STATE1
	mov PWM_FLAG, PWM_OFF
	Set_Cursor(1, 7)			
	Display_BCD(#0)
	cpl P0.1 ; to test if state 5->0 transition works correctly
	jb P0.2, forever
	jnb P0.2, $ ; Wait for key release
	cpl start_reload_flag ; set start_reload_flag.....this beep indicates START = YES & transition to STATE 1
	mov CURRENT_STATE, #0x01 ; change this back to #0x01
	;cpl start_sec_counter_state2_flag ; set flag to start incrementing SEC_COUNTER to 60s (WON'T NEED THIS LINE)
STATE0_DONE:
	ljmp forever
	
STATE1:
	cpl P0.1
	cjne a, #0x01, STATE2
	Set_Cursor(1, 7)			
	Display_BCD(#1)
	mov PWM_FLAG, PWM_HIGH
	;mov SEC_COUNTER, #0x00
	mov a, #150
	;mov TEMP, #160
	clr c
	subb a, TEMP
	jnc STATE1_DONE
	mov CURRENT_STATE, #0x02
	cpl state_transition_beep_flag ; short beep to indicate change of state
	cpl start_sec_counter_state2_flag ; set flag to start incrementing SEC_COUNTER to 60s
STATE1_DONE:
	ljmp forever
	
STATE2:
	cjne a, #0x02, STATE3 ; change this back to STATE3
	Set_Cursor(1, 7)			
	Display_BCD(#2)
	;cpl P0.1
	mov PWM_FLAG, PWM_LOW
	jb state3_transition_flag, STATE2_DONE ; if state3_transition_flag is not yet set, skip over
	cpl P0.1; to test correct change of state
	;mov PWM_FLAG, PWM_LOW
	mov CURRENT_STATE, #0x03 ; change this back to #0x03
	cpl state_transition_beep_flag ; short beep flag to indicate change of state
	;cpl start_sec_counter_state4_flag ; set flag to start incrementing SEC_COUNTER to 45s (WON'T NEED THIS LINE)
STATE2_DONE:
	ljmp forever
	
STATE3:
	cpl P0.1 ; this is to test change of state
	cjne a, #0x03, STATE4
	Set_Cursor(1, 7)			
	Display_BCD(#3)
	mov PWM_FLAG, PWM_HIGH
	;mov SEC_COUNTER, #0x00
	mov a, #220
	;mov TEMP, #225
	clr c
	subb a, TEMP
	jnc STATE3_DONE
	mov CURRENT_STATE, #0x04
	cpl start_sec_counter_state4_flag ; set flag to start incrementing SEC_COUNTER to 45s
	cpl state_transition_beep_flag ; set flag to short beep to indicate change of state
STATE3_DONE:
	ljmp forever
	
STATE4:
	cjne a, #0x04, STATE5
	Set_Cursor(1, 7)			
	Display_BCD(#4)
	cpl P0.7
	mov PWM_FLAG, PWM_LOW
	jb state5_transition_flag, STATE4_DONE ; if state5_transition_flag is not yet set, skip over
	;cpl P0.7 ; to test the transition from STATE2 to STATE4
	;mov PWM_FLAG, PWM_LOW
	mov CURRENT_STATE, #0x05
	cpl state_transition_beep_flag ;  set flag to short beep to indicate change of state
STATE4_DONE:
	ljmp forever
	
STATE5:
	cpl P0.7
	cjne a, #0x05, STATE5_DONE
	Set_Cursor(1, 7)			
	Display_BCD(#5)
	;mov CURRENT_STATE, #0x00 ; to test change of state from 5->0
	;cpl long_beep_flag ; to test to see if long beep feedback works correctly
	;ljmp STATE5_DONE ; to test (WON'T NEED THIS LINE)
	mov PWM_FLAG, PWM_OFF
	mov a, TEMP
	mov R1, #0x60
	clr c
	subb a, R1
	jnc STATE5_DONE
	mov CURRENT_STATE, #0x00
	cpl long_beep_flag
STATE5_DONE:
	ljmp forever
