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
Count1ms:     ds 2 ; Used to determine when half second has passed
second_counter:  ds 1 ; The BCD counter incrememted in the ISR and displayed in the main loop
minute_counter: ds 1
hour_counter: ds 1
alarm_second: ds 1 ;Holds the alarm digits
alarm_minute: ds 1
alarm_hour: ds 1
buffer_second: ds 1 ;Buffer for user entry
buffer_minute: ds 1
buffer_hour: ds 1
number_of_beeps: ds 1
bseg
seconds_flag: dbit 1 ; Set to one in the ISR every time 1000 ms had passed
pm_flag: dbit 1 ; Set to one for pm
pm_flag_alarm: dbit 1
pm_flag_buffer: dbit 1
alarm_on: dbit 1 ; One means alarm is on
alarm_setup: dbit 1 ; One means user is setting alarm
alarm_trigger: dbit 1
timer_alternator: dbit 1
output: dbit 1
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
; Output to arduino
SECONDS1 equ P1.0
SECONDS2 equ P1.1
SECONDS3 equ P1.2
SECONDS4 equ P1.3

SECONDS5 equ P0.0
SECONDS6 equ P0.1
SECONDS7 equ P0.2
SECONDS8 equ P0.3

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST

;                     1234567890123456    <- This helps determine the position of the counter
Initial_Message:  db 'time:xx:xx:xx xx', 0
Alarm_Message:    db 'alrm:xx:xx:xx xx', 0
No_Alarm_Message: db 'alrm: off       ', 0
AM_Message:  db 'AM', 0
PM_Message:  db 'PM', 0
Time_Or_Alarm1:   db '  time   alarm  ', 0
Time_Or_Alarm2:   db '  (up)  (down)  ', 0
Time_Hour:        db 'hour: xx        ', 0
Time_Minute:      db 'minute: xx      ', 0
Time_Second:      db 'second: xx      ', 0
Time_PM:          db 'AM/PM:  xx      ', 0
Okay_Message:     db 'xx:xx:xx xx  ok?', 0
Continue:         db 'set to continue ', 0
Clear:            db '                ', 0
                      
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
	push psw
	jnb alarm_trigger, no_alarms
	jnb timer_alternator, no_alarms
	; Define a latency correction for the timer reload
	CORRECTION EQU (4+4+2+2+4+4) ; lcall+ljmp+clr+mov+mov+setb

	cpl SOUND_OUT ; Connect speaker to P3.7!


no_alarms:
	; In mode 1 we need to reload the timer.
	clr TR0
	mov TH0, #high(TIMER0_RELOAD+CORRECTION)
	mov TL0, #low(TIMER0_RELOAD+CORRECTION)
	setb TR0
	pop psw
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
	cjne a, #low(1000), exit_jumper
	mov a, Count1ms+1
	cjne a, #high(1000), exit_jumper
	
	; 1000 milliseconds have passed.  Set a flag so the main program knows
	setb seconds_flag ; Let the main program know half second had passed
	cpl TR1 ; This line makes a beep-silence-beep-silence sound
	; Reset the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
	; Increment the seconds if less than 59
Seconds:
	mov a, second_counter
	cjne a, #0x59, Seconds_Less_Than_59 
	clr a
	lcall Seconds_da	
Minutes:
	mov a, minute_counter
	cjne a, #0x59, Minutes_Less_Than_59
	clr a
	lcall Minutes_da
Check_for_AMPM:
	mov a, hour_counter
	cjne a, #0x11, Hours	
	cpl pm_flag		
Hours:
	cjne a, #0x12, Hours_Less_Than_12
	mov a, #0x01
	lcall Hours_da
	sjmp Timer2_ISR_done
	
Hours_Less_Than_12:
	add a, #0x01
	lcall Hours_da
	sjmp Timer2_ISR_done	

Minutes_Less_Than_59:
	add a, #0x01
	lcall Minutes_da
	sjmp Timer2_ISR_done	
	
Seconds_Less_Than_59:
	add a, #0x01
	lcall Seconds_da
	sjmp Timer2_ISR_done

Seconds_da:
	da a
	mov second_counter, a
	ret

Minutes_da:
	da a
	mov minute_counter, a
	ret
	
Hours_da:
	da a
	mov hour_counter, a
	ret
	
exit_jumper:
	ljmp exit
		
Timer2_ISR_done:
	; if alarm is on alternate it
	djnz number_of_beeps, arduino
	clr alarm_trigger
	
arduino:	
; write to arduino output pins
	mov a, second_counter
	
	setb SECONDS1
    setb SECONDS2
    setb SECONDS3
    setb SECONDS4
    setb SECONDS5
    setb SECONDS6
    setb SECONDS7
    setb SECONDS8
	;output shift routine
output_1:		
	rlc a 
	mov output, c
	jnb output, output_2
	clr SECONDS1
output_2:
    rlc a 
	mov output, c
	jnb output, output_3
	clr SECONDS2
output_3:
    rlc a 
	mov output, c
	jnb output, output_4
	clr SECONDS3
output_4:
    rlc a 
	mov output, c
	jnb output, output_5
	clr SECONDS4
output_5:
    rlc a 
	mov output, c
	jnb output, output_6
	clr SECONDS5
output_6:
    rlc a 
	mov output, c
	jnb output, output_7
	clr SECONDS6
output_7:
    rlc a 
	mov output, c
	jnb output, output_8
	clr SECONDS7
output_8:
    rlc a 
	mov output, c
	jnb output, alternate
	clr SECONDS8	
	
alternate:
	cpl timer_alternator
	setb SOUND_OUT
	; check if alarm should be triggered
	jnb alarm_on, exit
same_seconds:
	mov a, alarm_hour
	cjne a, hour_counter, exit
	mov a, alarm_minute
	cjne a, minute_counter, exit 
	mov a, alarm_second
	cjne a, second_counter, exit
	
	jb pm_flag, is_pm
	jb pm_flag_alarm, exit
	setb alarm_trigger
	mov number_of_beeps, #0x08
	sjmp exit
	
is_pm:	
	jnb pm_flag_alarm, exit
	setb alarm_trigger
	mov number_of_beeps, #0x08
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
    mov number_of_beeps, #0x00
    clr timer_alternator
    clr alarm_trigger
    lcall Timer0_Init
    lcall Timer2_Init
    lcall LCD_4BIT
    ; For convenience a few handy macros are included in 'LCD_4bit.inc':
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
    setb seconds_flag
    clr pm_flag
    clr pm_flag_buffer
    setb pm_flag_alarm
    clr alarm_setup
    setb alarm_on
    
    setb SECONDS1
    setb SECONDS2
    setb SECONDS3
    setb SECONDS4
    setb SECONDS5
    setb SECONDS6
    setb SECONDS7
    setb SECONDS8

	mov second_counter, #0x56
	mov minute_counter, #0x59
	mov hour_counter, #0x05
	
	mov buffer_second, #0x00
	mov buffer_minute, #0x00
	mov buffer_hour, #0x12
	
	mov alarm_second, #0x00
	mov alarm_minute, #0x00
	mov alarm_hour, #0x01
	
	; After initialization the program stays in this 'forever' loop
loop:

loop_a:
	jnb seconds_flag, loop
loop_b:
    clr seconds_flag ; We clear this flag in the main loop, but it is set in the ISR for timer 0
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
	Set_Cursor(1, 12)     ; the place in the LCD where we want the BCD counter value
	Display_BCD(second_counter) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(1, 9)
	Display_BCD(minute_counter)
	Set_Cursor(1, 6)
	Display_BCD(hour_counter)
	
	jb pm_flag, its_pm ; If it's PM jump to set pm loop
		
	Set_Cursor(1, 15)
    Send_Constant_String(#AM_message)
    ljmp alarm		
	
its_pm:
	Set_Cursor(1, 15)
    Send_Constant_String(#PM_message)
    
alarm:
	
	jb USR_ALRM, check_alarm  
	Wait_Milli_Seconds(#50)	 
	jb USR_ALRM, check_alarm  
	jnb USR_ALRM, $
	cpl alarm_on

check_alarm:
	jb alarm_on, alarm_is_on
	ljmp no_alarm
	
alarm_is_on:	
	Set_Cursor(2, 1)
    Send_Constant_String(#Alarm_message)
    
	Set_Cursor(2, 12)     
	Display_BCD(alarm_second)
	Set_Cursor(2, 9)
	Display_BCD(alarm_minute)
	Set_Cursor(2, 6)
	Display_BCD(alarm_hour)
 
 	jb pm_flag_alarm, alarm_is_pm ; If it's PM jump to set pm loop
		
	Set_Cursor(2, 15)
    Send_Constant_String(#AM_message)
    sjmp user_control
    
alarm_is_pm:
	Set_Cursor(2, 15)
    Send_Constant_String(#PM_message)
    sjmp user_control	
    
no_alarm:	
	Set_Cursor(2, 1)
    Send_Constant_String(#No_Alarm_message)	 
	
user_control:
   ; Enter setup mode if user presses 'set' button
   	jb USR_SET, done_main_1  ; if the 'set' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_SET, done_main_1  ; if the 'set' button is not pressed skip
	jnb USR_SET, set_pressed		; wait for button release
	
	done_main_1:
	ljmp loop
   
set_pressed:
	Set_Cursor(1, 1)
    Send_Constant_String(#Time_Or_Alarm1)    
 	Set_Cursor(2, 1)
    Send_Constant_String(#Time_Or_Alarm2)  

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
	jnb USR_DOWN, alarm_bit_set	; wait for button release

alarm_bit_set:
	setb alarm_setup
	
time_buffer:
	Set_Cursor(1, 1)
    Send_Constant_String(#Time_hour) 
 	Set_Cursor(2, 1)
    Send_Constant_String(#Continue) 
    
hour_buffer:
	Set_Cursor(1, 7)
	Display_BCD(buffer_hour)
	
	Wait_Milli_Seconds(#150)	; delay so user doesn't accidentally press something

   ; jump to minute if user presses 'set' button
   	jb USR_SET, choose_hour  ; if the 'set' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_SET, choose_hour  ; if the 'set' button is not pressed skip
	jnb USR_SET, minute_message		; wait for button release
	
choose_hour:
hour_up_button:
   	jb USR_UP, hour_down_button  
	Wait_Milli_Seconds(#100)	 
	jb USR_UP, hour_down_button  
	jnb USR_UP, hour_up
hour_down_button:
   	jb USR_DOWN, hour_buffer  
	Wait_Milli_Seconds(#100)	 
	jb USR_DOWN, hour_buffer  
	jnb USR_DOWN, hour_down

hour_up:
	mov a, buffer_hour
	cjne a, #0x12, hour_up_under_12
	mov a, #0x01
	lcall buffer_hours_da
	sjmp hour_buffer
	
hour_up_under_12:
	add a, #0x01
	lcall buffer_hours_da
	sjmp hour_buffer

hour_down:
	mov a, buffer_hour
	cjne a, #0x01, hour_down_over_1
	mov a, #0x12
	lcall buffer_hours_da
	sjmp hour_buffer
	
hour_down_over_1:
	add a, #0x99
	lcall buffer_hours_da
	sjmp hour_buffer
; minute message
minute_message:
   	Set_Cursor(1, 1)
    Send_Constant_String(#Time_Minute) 
    
minute_buffer:
	Set_Cursor(1, 9)
	Display_BCD(buffer_minute)
	
	Wait_Milli_Seconds(#200)	; delay so user doesn't accidentally press something

   ; jump to minute if user presses 'set' button
   	jb USR_SET, choose_minute  ; if the 'set' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_SET, choose_minute  ; if the 'set' button is not pressed skip
	jnb USR_SET, $		; wait for button release
	ljmp second_message
	
choose_minute:
minute_up_button:
   	jb USR_UP, minute_down_button  
	Wait_Milli_Seconds(#100)	 
	jb USR_UP, minute_down_button  
	jnb USR_UP, minute_up
minute_down_button:
   	jb USR_DOWN, minute_buffer  
	Wait_Milli_Seconds(#100)	 
	jb USR_DOWN, minute_buffer  
	jnb USR_DOWN, minute_down

minute_up:
	mov a, buffer_minute
	cjne a, #0x59, minute_up_under_59
	mov a, #0x00
	lcall buffer_minutes_da
	sjmp minute_buffer
	
minute_up_under_59:
	add a, #0x01
	lcall buffer_minutes_da
	sjmp minute_buffer

minute_down:
	mov a, buffer_minute
	cjne a, #0x00, minute_down_over_0
	mov a, #0x59
	lcall buffer_minutes_da
	sjmp minute_buffer
	
minute_down_over_0:
	add a, #0x99
	lcall buffer_minutes_da
	sjmp minute_buffer	
	
;seconds
second_message:
   	Set_Cursor(1, 1)
    Send_Constant_String(#Time_Second) 
    
second_buffer:
	Set_Cursor(1, 9)
	Display_BCD(buffer_second)
	
	Wait_Milli_Seconds(#200)	; delay so user doesn't accidentally press something

   ; jump to second if user presses 'set' button
   	jb USR_SET, choose_second  ; if the 'set' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_SET, choose_second  ; if the 'set' button is not pressed skip
	jnb USR_SET, ampm_message		; wait for button release
	
choose_second:
second_up_button:
   	jb USR_UP, second_down_button  
	Wait_Milli_Seconds(#100)	 
	jb USR_UP, second_down_button  
	jnb USR_UP, second_up
second_down_button:
   	jb USR_DOWN, second_buffer  
	Wait_Milli_Seconds(#100)	 
	jb USR_DOWN, second_buffer  
	jnb USR_DOWN, second_down

second_up:
	mov a, buffer_second
	cjne a, #0x59, second_up_under_59
	mov a, #0x00
	lcall buffer_seconds_da
	sjmp second_buffer
	
second_up_under_59:
	add a, #0x01
	lcall buffer_seconds_da
	sjmp second_buffer

second_down:
	mov a, buffer_second
	cjne a, #0x00, second_down_over_0
	mov a, #0x59
	lcall buffer_seconds_da
	sjmp second_buffer
	
second_down_over_0:
	add a, #0x99
	lcall buffer_seconds_da
	sjmp second_buffer	

buffer_seconds_da:
	da a
	mov buffer_second, a
	ret

buffer_minutes_da:
	da a
	mov buffer_minute, a
	ret
	
buffer_hours_da:
	da a
	mov buffer_hour, a
	ret

ampm_message:
	Set_Cursor(1, 1)
    Send_Constant_String(#Time_PM)
     
ampm_buffer:
	Set_Cursor(1, 9)
	jb pm_flag_buffer, buffer_pm
    Send_Constant_String(#AM_message)
    sjmp buffer_set		
buffer_pm:	
	Send_Constant_String(#PM_message)
	
buffer_set:	
	Wait_Milli_Seconds(#200)	; delay so user doesn't accidentally press something

   ; jump to second if user presses 'set' button
   	jb USR_SET, choose_ampm  ; if the 'set' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_SET, choose_ampm  ; if the 'set' button is not pressed skip
	jnb USR_SET, ok_message		; wait for button release
	
choose_ampm:
ampm_up_button:
   	jb USR_UP, ampm_down_button  
	Wait_Milli_Seconds(#100)	 
	jb USR_UP, ampm_down_button  
	jnb USR_UP, ampm_up
ampm_down_button:
   	jb USR_DOWN, ampm_buffer  
	Wait_Milli_Seconds(#100)	 
	jb USR_DOWN, ampm_buffer  
	jnb USR_DOWN, ampm_down

ampm_up:
	cpl pm_flag_buffer
	sjmp ampm_buffer
	
ampm_down:
	cpl pm_flag_buffer
	sjmp ampm_buffer

ok_message:
   	Set_Cursor(1, 1)
    Send_Constant_String(#Okay_Message) 	

	Set_Cursor(1, 7)   
	Display_BCD(buffer_second) 
	Set_Cursor(1, 4)
	Display_BCD(buffer_minute)
	Set_Cursor(1, 1)
	Display_BCD(buffer_hour)

	Set_Cursor(1, 10)
	jb pm_flag_buffer, ok_ampm
    Send_Constant_String(#AM_message)
    sjmp ok_buffer		
ok_ampm:	
	Send_Constant_String(#PM_message)
		
ok_buffer:
   	
	Wait_Milli_Seconds(#200)	; delay so user doesn't accidentally press something

   ; jump to second if user presses 'set' button
   	jb USR_SET, choose_ok  ; if the 'set' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb USR_SET, choose_ok  ; if the 'set' button is not pressed skip
	jnb USR_SET, writeback		; wait for button release

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
	 
writeback:
	jb alarm_setup, chose_alarm
	
	;turn off interupts
    clr EA   ; disable Global interrupts	
	;write to time regs
	mov a, buffer_second
	mov second_counter, a
	mov a, buffer_minute
	mov minute_counter, a
	mov a, buffer_hour
	mov hour_counter, a
	jb pm_flag_buffer, write_pm
	clr pm_flag
	sjmp done_writeback_1
	
write_pm:	
	setb pm_flag
	
done_writeback_1:
	lcall reset_buffer
	Wait_Milli_Seconds(#200)
    lcall Timer0_Init
    lcall Timer2_Init
    setb seconds_flag
    ljmp loop	
	
chose_alarm:
	;write to alarm regs
	mov a, buffer_second
	mov alarm_second, a
	mov a, buffer_minute
	mov alarm_minute, a
	mov a, buffer_hour
	mov alarm_hour, a
	jb pm_flag_buffer, write_alarm_pm
	clr pm_flag_alarm 
	sjmp done_writeback_2
	
write_alarm_pm:
    setb pm_flag_alarm
       
done_writeback_2: 
	lcall reset_buffer
	Wait_Milli_Seconds(#200)   			
    ljmp loop
 
reset_buffer:
	mov buffer_second, #0x00
	mov buffer_minute, #0x00
	mov buffer_hour, #0x12
	clr pm_flag_buffer
	clr alarm_setup
	ret    
     
END