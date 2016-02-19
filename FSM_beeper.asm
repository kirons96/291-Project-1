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

next_line EQU $

;BOOT_BUTTON     EQU P4.5 ;reset button
SOUND_OUT       EQU P1.2
PWM_PIN			EQU P0.0 ;change later
START_BUTTON 	EQU P0.2 ;start button

;UI pins
; User control buttons
USR_SET equ P2.5
USR_UP equ P0.7
USR_DOWN equ P0.5
;USR_RUN equ P0.6

; Wiring for ADC
CE_ADC EQU P2.0
MY_MOSI EQU P2.1
MY_MISO EQU P2.2
MY_SCLK EQU P2.3

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

;math32.inc variables
Result: ds 2
x:   ds 4
y:   ds 4
bcd: ds 5

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

sixty_degrees: ds 1


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
clap_flag: dbit 1

;UI flags
seconds_flag: dbit 1 ; Set to one in the ISR every time 1000 ms had passed
oven_on: dbit 1 ; One means oven is on
reflow_setup: dbit 1 ; One means user is setting reflow

;for math32.inc
mf: dbit 1


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
$include(math32.inc)
$LIST

;
;                          1234567890123456    <- This helps determine the position of the counter
Stopped_Message:      db  'SHIET MANNNN    ', 0
Stopped_Message2:     db  'restarting...   ', 0
Display_State_Message: db 'State:', 0
Finished_Message:     db  'Reflow complete!', 0
Oven_Default_Message1: db 's:xxxs  xxxC    ', 0
Oven_Default_Message2: db 'r:xxxs  xxxC    ', 0
Colon: db ':', 0
Soak_Or_Reflow_Message1:   db '  soak  reflow  ', 0
Soak_Or_Reflow_Message2:   db '  (up)  (down)  ', 0
Time_Message:     db 'time: xxxxs     ', 0
Temp_Message:     db 'temp: xxxxC     ', 0
Okay_Message:     db 'xxxxs xxxxC  ok?', 0
Continue:         db 'set to continue ', 0
Clear:            db '                ', 0
Space: db ' ', 0
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
; 2048 Hz square wave at pin P1.2 ;
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
	cpl P1.2 ; turn on speaker

beep_transition:
	jb state_transition_beep_flag, long_beep_transition
	cpl P1.2 ; turn on speaker
long_beep_transition:
	jb long_beep_flag, six_short_beeps
	cpl P1.2

six_short_beeps:
	jb six_short_beep_flag, CHECK_OFF
	cpl P1.2
	
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
	
	; The two registers used in the ISR must be saved in the stack
	push acc
	push psw
	
	; Increment the 16-bit counter
	inc Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1


	;jb P3.7, Inc_Done
;	jnb P3.7, $
	;setb clap_flag

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
	;mov a, TEMP
	;cjne a, #0x99, no_overflow
	;clr psw
	;clr a
	;da a
	;mov TEMP, a
	;mov a, TEMP + 1
	;add a, #0x01
	;da a
	;mov TEMP + 1, a	
	;sjmp debug_counter_done

no_overflow:
	;add a, #0x01
	;da a 
	;mov TEMP, a

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
; SPI stuff                       ;
;---------------------------------;

INIT_SPI:
 setb MY_MISO ; Make MISO an input pin
 clr MY_SCLK ; For mode (0,0) SCLK is zero
 ret

DO_SPI_G:
 push acc
 mov R1, #0 ; Received byte stored in R1
 mov R2, #8 ; Loop counter (8-bits)
 
 
 
DO_SPI_G_LOOP:
 mov a, R0 ; Byte to write is in R0
 rlc a ; Carry flag has bit to write
 mov R0, a
 mov MY_MOSI, c
 setb MY_SCLK ; Transmit
 mov c, MY_MISO ; Read received bit
 mov a, R1 ; Save received bit in R1
 rlc a
 mov R1, a
 clr MY_SCLK
 djnz R2, DO_SPI_G_LOOP
 pop acc

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
	
	; Flags
	clr state3_transition_flag
	setb half_seconds_flag
	clr start_sec_counter
	clr start_sec_counter_total
	clr oven_on
	clr reflow_setup
	clr clap_flag


	mov SEC_COUNTER + 1, #0x00
	mov SEC_COUNTER, #0x00

	mov SEC_COUNTER_TOTAL + 1, #0x00
	mov SEC_COUNTER_TOTAL, #0x00

	mov CURRENT_STATE, #0
	mov PWM_COUNTER, #0
	mov PWM_FLAG, PWM_OFF
	mov PWM_OFF, #0
	mov PWM_LOW, #1 ;because weird bug (ask kiron)
	mov PWM_HIGH, #10
	mov SHORT_BEEP_COUNTER, #0x00

	mov sixty_degrees, #0x60

	mov TEMP + 1, #0x00
	mov TEMP, #0x00

	mov soak_temp + 1, #0x01
	mov soak_temp, #0x50

	mov soak_time + 1, #0x00
	mov soak_time, #0x60

	mov reflow_temp + 1, #0x02
	mov reflow_temp, #0x20

	mov reflow_time + 1, #0x00
	mov reflow_time, #0x45

	mov buffer_temp + 1, #0x01
	mov buffer_temp, #0x40

	mov buffer_time + 1, #0x00
	mov buffer_time, #0x50


	; Draw main menu
	ljmp main_menu_jumper	
done_menu_init:
	

	;UI INIT
	;lcall oven_init
	;setb seconds_flag
	;lcall draw_main_menu



	; SPI
	lcall INIT_SPI

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

	jb oven_on, running 
	ljmp UI_jumper
done_UI_main:
	ljmp PRE_STATE0


running:

	Set_Cursor(1, 1)			
	Send_Constant_String(#Display_State_Message)

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

	; SPI Temp Reading

	clr CE_ADC
	mov R0, #00000001B ; Start bit:1
	lcall DO_SPI_G
	mov R0, #10000000B ; Single ended, read channel 0
	lcall DO_SPI_G
	mov a, R1 ; R1 contains bits 8 and 9
	anl a, #00000011B ; We need only the two least significant bits
	mov Result+1, a ; Save result high.
	mov R0, #55H ; It doesn't matter what we transmit...
	lcall DO_SPI_G
	mov Result, R1 ; R1 contains bits 0 to 7. Save result low.
	setb CE_ADC

	; ******************************

	mov x+0, Result+0
	mov x+1, Result+1
	mov x+2, #0
	mov x+3, #0
;--------------VOLTAGE TO TEMP CONVERSION---------------------;
	load_y(53300)
	lcall mul32
	load_y(5)
	lcall mul32
	load_y(1023000)
	lcall div32
	load_y(22)
	lcall add32
;--------------VOLTAGE TO TEMP CONVERSION---------------------;	
	lcall hex2bcd

	mov a, bcd+1
	swap a
	anl a, #0x0f
	orl a, #0x30
;--------------SEND TO TERMINAL-------------------------------;

	clr EA ; mask interrupts
	lcall InitSerialPort

	

	
	lcall putchar
	mov a, bcd+1
	mov TEMP + 1, a
	anl a, #0x0f
	orl a, #0x30
	lcall putchar

	mov a, bcd+0
	mov TEMP, a
	swap a
	anl a, #0x0f
	orl a, #0x30

	lcall putchar

	mov a, bcd+0
	anl a, #0x0f
	orl a, #0x30
	lcall putchar

; Send new line / carriage return
	mov a, #'\r'
	lcall putchar
	mov a, #'\n'
	lcall putchar
	
	Wait_Milli_Seconds(#1)
	lcall Timer2_Init



PRE_STATE0:
	mov a, CURRENT_STATE

STATE0:
	cjne a, #0x00, STATE1_jumper ; change this back to STATE1

	mov PWM_FLAG, PWM_OFF
	;Set_Cursor(1, 7)			
	;Display_BCD(#0)

	;jnb clap_flag, STATE0_DONE
	jb P3.7, STATE0_DONE
	jnb P3.7, $
	;jnb P3.7, $ ; Wait for key release


	cpl start_reload_flag ; set start_reload_flag.....this beep indicates START = YES & transition to STATE 1
	mov CURRENT_STATE, #0x01 ; change this back to #0x01
	setb oven_on
	Set_Cursor(1, 1)
	Send_Constant_String(#Clear)
	Set_Cursor(2, 1)
	Send_Constant_String(#Clear)

STATE0_DONE:
	ljmp forever

STATE1_jumper:
	sjmp STATE1

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
	Set_Cursor(1, 8)			
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
	

STATE1_DONE:
	ljmp forever
	
STATE2:
	cjne a, #0x02, STATE3 ; change this back to STATE3

	setb start_sec_counter; set flag to start incrementing SEC_COUNTER to 60s

	Set_Cursor(1, 8)			
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

	mov SEC_COUNTER + 1, #0x00
	mov SEC_COUNTER, #0x00
	

STATE2_DONE:
	ljmp forever
	
STATE3:
	cpl P0.1 ; this is to test change of state
	cjne a, #0x03, STATE4
	Set_Cursor(1, 8)			
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


STATE3_DONE:
	ljmp forever
	
STATE4:
	cjne a, #0x04, STATE5

	Set_Cursor(1, 8)			
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

	mov SEC_COUNTER + 1, #0x00
	mov SEC_COUNTER, #0x00

STATE4_DONE:
	ljmp forever
	
STATE5:
	cpl P0.7
	cjne a, #0x05, STATE5_DONE

	Set_Cursor(1, 8)			
	Display_BCD(#5)

	mov PWM_FLAG, PWM_OFF

	mov a, TEMP + 1
	cjne a, #0x00, STATE5_DONE
	mov a, TEMP
	;mov R6, #0x60
	clr c
	subb a, sixty_degrees
	jc FINISH_BEEP

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



;-------------------------------------------------------------------;
; UI subroutine                                                     ;
; 								    ;
; 1) See if oven is on, only let user change times/temps            ;
;    if the oven is not running                                     ;
;                                                                   ;
; 2) User chooses to edit soak or reflow times/temps                ;
;                                                                   ;
; 3) User chooses time then temperature for soak or reflow cycle    ;
;                                                                   ;
; 4) User gets confirmation screen, set to continue else disregard  ;
;    changes                                                        ;
;                                                                   ;
; 5) Write changes from selection buffer to either reflow or soak   ;
;                                                                   ;
;-------------------------------------------------------------------; 
UI_jumper:
	lcall UI_update	
	ljmp done_ui_main


UI_update:

push acc
push psw

UI_start:
	 
user_control:
	; if oven is running, user cannot adjust settings
	;jnb oven_on, setup_mode
	;ret

setup_mode:
	Button(USR_SET, set_pressed, no_setup)	
	;sjmp set_pressed

	;jnb USR_SET, set_pressed

no_setup:
	pop psw
	pop acc
	ret
 
set_pressed:
	Set_Cursor(1, 1)
	Send_Constant_String(#Soak_Or_Reflow_Message1)    
	Set_Cursor(2, 1)
	Send_Constant_String(#Soak_Or_Reflow_Message2)  

choose_time:    
	Button(USR_UP, time_buffer, choose_alarm)

choose_alarm:
	Button(USR_DOWN, reflow_bit_set, choose_time)

reflow_bit_set:
	setb reflow_setup

;-----------------------------;
; Time                        ;	
;-----------------------------;
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

	Set_Cursor(1, 7)
	Send_Constant_String(#Space)
	
	Wait_Milli_Seconds(#150)	; delay so user doesn't accidentally press something

        ;jump to minute if user presses 'set' button
	Button(USR_SET, temp_buffer, time_select)
time_select:
time_up_button:
	Button(USR_UP, time_up, time_down_button)
time_down_button:
	Button(USR_DOWN, time_down, time_loop)
time_up:
	mov a, buffer_time
	cjne a, #0x99, time_up_under_99
	mov a, #0x00
	lcall buffer_time_da
time_hundreds_up:
	mov a, buffer_time + 1
	cjne a, #0x02, time_hundreds_up_over
	mov a, #0x00
	mov buffer_time + 1, a
	ljmp time_loop
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
	mov a, #0x02
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

;-----------------------------;
; Temperature                 ;	
;-----------------------------;
temp_buffer:
   	Set_Cursor(1, 1)
        Send_Constant_String(#Temp_Message) 
    
temp_loop:
	Set_Cursor(1, 9)
	Display_BCD(buffer_temp)
	
	Set_Cursor(1, 7)
	Display_BCD(buffer_temp + 1)

	Set_Cursor(1, 7)
	Send_Constant_String(#Space)
	
	Wait_Milli_Seconds(#150)	; delay so user doesn't accidentally press something

        ; jump to minute if user presses 'set' button
	Button(USR_SET, ok_message, temp_select)
	
temp_select:
temp_up_button:
	Button(USR_UP, temp_up, temp_down_button)
temp_down_button:
	Button(USR_DOWN, temp_down, temp_loop)
temp_up:
	mov a, buffer_temp
	cjne a, #0x99, temp_up_under_99
	mov a, #0x00
	lcall buffer_temp_da
temp_hundreds_up:
	mov a, buffer_temp + 1
	cjne a, #0x02, temp_hundreds_up_over
	mov a, #0x00
	mov buffer_temp + 1, a
	ljmp temp_loop
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
	mov a, #0x02
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

	Button(USR_SET, writeback_soak, choose_ok)

choose_ok:
ok_up_button:
	Button(USR_UP, ok_up, ok_down_button)
ok_down_button:
	Button(USR_DOWN, ok_down, ok_buffer)
ok_up:
	lcall reset_buffer
	Wait_Milli_Seconds(#200)
	ljmp done_UI
	
ok_down:
	lcall reset_buffer
	Wait_Milli_Seconds(#200)
	ljmp done_UI


	 
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
	ljmp done_UI

reset_buffer:
	mov buffer_time + 1, #0x00
	mov buffer_time, #0x50
	mov buffer_temp + 1, #0x01
	mov buffer_temp, #0x40
	clr reflow_setup

	ret    

oven_init:
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
	ret

main_menu_jumper:
	lcall draw_main_menu
	ljmp done_menu_init

draw_main_menu:

	Set_Cursor(1, 1)
	Send_Constant_String(#Oven_Default_Message1)
	Set_Cursor(2, 1)
	Send_Constant_String(#Oven_Default_Message2)	

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

	ret

done_UI:
	lcall draw_main_menu
	Wait_Milli_Seconds(#200)
	Wait_Milli_Seconds(#200)
	Wait_Milli_Seconds(#200)
	Wait_Milli_Seconds(#200)

	pop psw
	pop acc
	ret
;-----------------------------------;
; End of UI                         ;
;-----------------------------------;







