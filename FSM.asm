$NOLIST
$MODLP52
$LIST

CLK           EQU 22118400 ; Microcontroller system crystal frequency in Hz
TIMER0_RATE   EQU 4096     ; 2048Hz squarewave (peak amplitude of CEM-1203 speaker)
TIMER0_RELOAD EQU ((65536-(CLK/TIMER0_RATE)))
TIMER2_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
TIMER2_RELOAD EQU ((65536-(CLK/TIMER2_RATE)))

BAUD EQU 115200
T2LOAD EQU (0x10000-(CLK/(16*BAUD)))

BOOT_BUTTON     EQU P4.5 ;reset button
SOUND_OUT       EQU P3.7
PWM_PIN			EQU P0.0 ;change later
START_BUTTON 	EQU P0.2 ;start button

; Wiring for ADC
;CE_ADC EQU P3.5
;MY_MOSI EQU P3.4
;MY_MISO EQU P3.3
;MYSCLK EQU P3.2



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
SEC_COUNTER:	ds 2 ;timer
SEC_COUNTER_TOTAL: ds 2 ; total run time
TEMP:			ds 2 ;temperature

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

;User settings variables
buffer_temp: ds 2
buffer_time: ds 2
soak_temp: ds 2
soak_time: ds 2
reflow_temp: ds 2
reflow_time: ds 2


bseg
half_seconds_flag: dbit 1 ; Set to one in the ISR every time 500 ms had passed
start_reload_flag: dbit 1
start_sec_counter: dbit 1
start_sec_counter_total: dbit 1
state3_transition_flag: dbit 1
state5_transition_flag: dbit 1
state_transition_beep_flag: dbit 1
long_beep_flag: dbit 1
six_short_beep_flag: dbit 1


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
$include(tristan_lib.inc)
$LIST

;
;                          1234567890123456    <- This helps determine the position of the counter
Stopped_Message:      db  'SHIET MANNNN    ', 0
Stopped_Message2:     db  'restarting...   ', 0
Finished_Message:     db  'Reflow complete!', 0
Oven_Default_Message1: db 's:xxxs  xxxC xxx', 0
Oven_Default_Message2: db 'r:xxxs  xxxC    ', 0
Oven_Off_Message: db 'off', 0
Oven_On_Message:  db 'run', 0
Colon: db ':', 0
Soak_Or_Reflow_Message1:   db '  soak  reflow  ', 0
Soak_Or_Reflow_Message2:   db '  (up)  (down)  ', 0
Time_Message:     db 'time: xxxxs     ', 0
Temp_Message:     db 'temp: xxxxC     ', 0
Okay_Message:     db 'xxxxs xxxxC  ok?', 0
Continue:         db 'set to continue ', 0
Clear:            db '                ', 0
Space: db ' ', 0
Display_State_Message:  db 'State:', 0
Hello_World:  db  'Hello, World!', '\r', '\n', 0
End_Transmission: db '\r', '\n', 0


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
	jb long_beep_flag, six_short_beeps
	cpl P3.7

six_short_beeps:
	jb six_short_beep_flag, CHECK_OFF
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
	push acc
	push psw

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

	pop psw
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
	; Check if 1 second has passed
	mov a, Count1ms+0
	cjne a, #low(1000), jump_timer2_done 
	
	mov a, Count1ms+1
	cjne a, #high(1000), jump_timer2_done
	
	sjmp second_passed	

jump_timer2_done:
	ljmp Timer2_ISR_done

second_passed:
	; 1 second has passed.  Set a flag so the main program knows
	setb half_seconds_flag ; Let the main program know half second had passed
	;cpl TR1 ; This line makes a beep-silence-beep-silence sound

	;************COUNTER************
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	;***********Debug Temp Counter***	
	mov a, TEMP
	cjne a, #0x99, no_overflow
	;clr psw
	clr a
	da a
	mov TEMP, a
	mov a, TEMP + 1
	add a, #0x01
	da a
	mov TEMP + 1, a	
	sjmp debug_counter_done

no_overflow:
	add a, #0x01
	da a 
	mov TEMP, a

debug_counter_done:
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
	jb long_beep_flag, Check_SEC_COUNTER
	mov a, SHORT_BEEP_COUNTER
	add a, #0x01
	da a
	mov SHORT_BEEP_COUNTER, a
	cjne a, #0x03, Timer2_ISR_done
	cpl long_beep_flag ; clear flag & turn off long beep speaker
	mov SHORT_BEEP_COUNTER, #0x00
	
	;****STATE TRANSITIONS*****

Check_SEC_COUNTER:
	jnb start_sec_counter, Check_SEC_COUNTER_TOTAL

	mov a, SEC_COUNTER
	cjne a, #0x99, sec_counter_no_overflow
	clr a
	da a
	mov SEC_COUNTER, a
	mov a, SEC_COUNTER + 1
	add a, #0x01
	da a
	mov SEC_COUNTER + 1, a
	sjmp Timer2_ISR_done

sec_counter_no_overflow:
	add a, #0x01
	da a
	mov SEC_COUNTER, a

Check_SEC_COUNTER_TOTAL:
	jnb start_sec_counter_total, Timer2_ISR_done ;

	mov a, SEC_COUNTER_TOTAL
	cjne a, #0x99, sec_counter_total_no_overflow
	clr a
	da a
	mov SEC_COUNTER_TOTAL, a
	mov a, SEC_COUNTER_TOTAL + 1
	add a, #0x01
	da a
	mov SEC_COUNTER_TOTAL + 1, a
	sjmp Timer2_ISR_done

sec_counter_total_no_overflow:
	add a, #0x01
	da a
	mov SEC_COUNTER_TOTAL, a
	
Timer2_ISR_done:
	pop psw
	pop acc
	reti

;---------------------------------;
; Serial Stuff                    ;
;                                 ;
;---------------------------------;

; Configure the serial port and baud rate using timer 2
InitSerialPort:
	clr TR2 ; Disable timer 2
	mov T2CON, #30H ; RCLK=1, TCLK=1 
	mov RCAP2H, #high(T2LOAD)  
	mov RCAP2L, #low(T2LOAD)
	setb TR2 ; Enable timer 2
	mov SCON, #52H
	ret

; Send a character using the serial port
putchar:
	JNB TI, putchar
	CLR TI
	MOV SBUF, a
	RET

; Send a constant-zero-terminated string through the serial port
SendString:
	CLR A
	MOVC A, @A+DPTR
	JZ SendStringDone
	LCALL putchar
	INC DPTR
	SJMP SendString
SendStringDone:
	ret


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
	Set_Cursor(1, 1)			
	Send_Constant_String(#Display_State_Message)
	
	; Flags
	clr state3_transition_flag
	setb half_seconds_flag
	clr start_sec_counter
	clr start_sec_counter_total


	mov SEC_COUNTER + 1, #0x00
	mov SEC_COUNTER, #0x40

	mov SEC_COUNTER_TOTAL + 1, #0x00
	mov SEC_COUNTER_TOTAL, #0x00

	mov CURRENT_STATE, #0
	mov PWM_COUNTER, #0
	mov PWM_FLAG, PWM_OFF
	mov PWM_OFF, #0
	mov PWM_LOW, #1 ;because weird bug (ask kiron)
	mov PWM_HIGH, #10
	mov SHORT_BEEP_COUNTER, #0x00

	mov TEMP + 1, #0x01
	mov TEMP, #0x40

	mov soak_temp + 1, #0x01
	mov soak_temp, #0x50

	mov soak_time + 1, #0x00
	mov soak_time, #0x60

	mov reflow_temp + 1, #0x02
	mov reflow_temp, #0x20

	mov reflow_time + 1, #0x00
	mov reflow_time, #0x45


	; After initialization the program stays in this 'forever' loop
forever:
	sjmp loop_a

	clr TR0
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	


	mov CURRENT_STATE, #0x00
	mov PWM_COUNTER, #0x00
	mov PWM_FLAG, PWM_OFF
	mov SHORT_BEEP_COUNTER, #0x00
	setb TR0                ; Re-enable the timer
	sjmp loop_b             ; Display the new value


loop_a:
	jnb half_seconds_flag, forever
loop_b:
        clr half_seconds_flag ; We clear this flag in the main forever, but it is set in the ISR for timer 0

	; show debug temp counter
	Set_Cursor(2, 1)
	Display_BCD(TEMP + 1)
	Set_Cursor(2, 3)
	Display_BCD(TEMP)

	; show state second timer
	Set_Cursor(2, 6)
	Display_BCD(SEC_COUNTER + 1)
	Set_Cursor(2, 8)
	Display_BCD(SEC_COUNTER)

	; show state second timer
	Set_Cursor(2, 11)
	Display_BCD(SEC_COUNTER_TOTAL + 1)
	Set_Cursor(2, 13)
	Display_BCD(SEC_COUNTER_TOTAL)

	; Serial	
	clr EA ; mask interrupts
	lcall InitSerialPort
	mov a, TEMP
	lcall putchar
	mov dptr, #End_Transmission
	lcall SendString
	Wait_Milli_Seconds(#1)
	lcall Timer2_Init

	mov a, CURRENT_STATE

STATE0:
	cjne a, #0x00, STATE1 ; change this back to STATE1
	mov PWM_FLAG, PWM_OFF
	Set_Cursor(1, 7)			
	Display_BCD(#0)
	cpl P0.1 ; to test if state 5->0 transition works correctly

	jb P0.2, STATE0_DONE
	jnb P0.2, $ ; Wait for key release

	cpl start_reload_flag ; set start_reload_flag.....this beep indicates START = YES & transition to STATE 1
	mov CURRENT_STATE, #0x01 ; change this back to #0x01
STATE0_DONE:
	ljmp forever

STOPPED:
	Set_Cursor(1, 1)
	Send_Constant_String(#Stopped_Message)
	Set_Cursor(2, 1)
	Send_Constant_String(#Stopped_Message2)
	mov R4, #0xF
STOPPED_REPEAT:
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	djnz R4, STOPPED_REPEAT

	ljmp main
	
STATE1:
	Button(START_BUTTON, STOPPED, STATEONE)
STATEONE:
	cjne a, #0x01, STATE2
	setb start_sec_counter_total
	Set_Cursor(1, 7)			
	Display_BCD(#1)
	mov PWM_FLAG, PWM_HIGH

	mov a, TEMP + 1
	cjne a, soak_temp + 1, STATE1_DONE
	mov a, soak_temp
	clr c
	subb a, TEMP
	jnc STATE1_DONE

	mov CURRENT_STATE, #0x02
	cpl state_transition_beep_flag ; short beep to indicate change of state
	
	mov SEC_COUNTER + 1, #0x00
	mov SEC_COUNTER, #0x50

STATE1_DONE:
	ljmp forever
	
STATE2:
	cjne a, #0x02, STATE3 ; change this back to STATE3

	setb start_sec_counter; set flag to start incrementing SEC_COUNTER to 60s

	Set_Cursor(1, 7)			
	Display_BCD(#2)

	mov PWM_FLAG, PWM_LOW

	mov a, SEC_COUNTER + 1
	cjne a, soak_time + 1, STATE2_DONE
	mov a, SEC_COUNTER
	cjne a, soak_time, STATE2_DONE

	clr start_sec_counter
	mov SEC_COUNTER + 1, #0x00
	mov SEC_COUNTER, #0x00
	mov CURRENT_STATE, #0x03 ; change this back to #0x03
	cpl state_transition_beep_flag ; short beep flag to indicate change of state
	
	mov TEMP + 1, #0x02
	mov TEMP, #0x10

STATE2_DONE:
	ljmp forever
	
STATE3:
	cpl P0.1 ; this is to test change of state
	cjne a, #0x03, STATE4
	Set_Cursor(1, 7)			
	Display_BCD(#3)
	mov PWM_FLAG, PWM_HIGH

	mov a, TEMP + 1
	cjne a, reflow_temp + 1, STATE3_DONE
	mov a, reflow_temp
	clr c
	subb a, TEMP
	jnc STATE3_DONE

	mov CURRENT_STATE, #0x04
	cpl state_transition_beep_flag ; set flag to short beep to indicate change of state

	mov SEC_COUNTER + 1, #0x00
	mov SEC_COUNTER, #0x35

STATE3_DONE:
	ljmp forever
	
STATE4:
	cjne a, #0x04, STATE5

	Set_Cursor(1, 7)			
	Display_BCD(#4)

	setb start_sec_counter

	mov PWM_FLAG, PWM_LOW

	mov a, SEC_COUNTER + 1
	cjne a, reflow_time + 1, STATE4_DONE
	mov a, SEC_COUNTER
	cjne a, reflow_time, STATE4_DONE

	mov CURRENT_STATE, #0x05
	clr start_sec_counter
	mov SEC_COUNTER + 1, #0x00
	mov SEC_COUNTER, #0x00
	cpl long_beep_flag

	mov TEMP + 1, #0x00
	mov TEMP, #0x65

STATE4_DONE:
	ljmp forever
	
STATE5:
	cpl P0.7
	cjne a, #0x05, STATE5_DONE

	Set_Cursor(1, 7)			
	Display_BCD(#5)

	mov PWM_FLAG, PWM_OFF

	mov a, TEMP + 1
	cjne a, #0x00, STATE3_DONE
	mov a, TEMP
	mov R3, #0x60
	clr c
	subb a, R3
	jnc FINISH_BEEP

STATE5_DONE:
	ljmp forever

FINISH_BEEP:
	Set_Cursor(1, 1)
	Send_Constant_String(#Finished_Message)
	Set_Cursor(2, 1)
	Send_Constant_String(#Stopped_Message2)

	mov CURRENT_STATE, #0x00
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	Wait_Milli_Seconds(#255)
	mov R2, #0x9
DECREMENT_LABEL:
	cpl six_short_beep_flag
	Wait_Milli_Seconds(#255)
	;Wait_Milli_Seconds(#255)
	;Wait_Milli_Seconds(#255)
	djnz R2, DECREMENT_LABEL
	cpl six_short_beep_flag
	ljmp main









