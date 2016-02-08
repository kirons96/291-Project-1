$MODLP52
org 0000H
ljmp MainProgram

CLK  EQU 22118400
BAUD equ 115200
T2LOAD equ (0x10000-(CLK/(16*BAUD)))

CE_ADC EQU P2.0
MY_MOSI EQU P2.1
MY_MISO EQU P2.2
MY_SCLK EQU P2.3

$NOLIST
$include(LCD_4bit.inc)
$include(math32.inc)
$LIST

DSEG at 30H
Result: ds 2
Result1:ds 2
x:   ds 4
y:   ds 4
bcd: ds 5

BSEG
mf: dbit 1

CSEG
; These 'equ' must match the hardware wiring
; They are used by 'LCD_4bit.inc'
LCD_RS equ P1.4
LCD_RW equ P1.5
LCD_E  equ P1.6
LCD_D4 equ P3.2
LCD_D5 equ P3.3
LCD_D6 equ P3.4
LCD_D7 equ P3.5

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

MainProgram:
    MOV SP, #7FH ; Set the stack pointer to the begining of idata
    mov PMOD, #0 ; Configure all ports in bidirectional mode
    
    LCALL InitSerialPort
    lcall INIT_SPI
	lcall LCD_4bit

Forever:
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
	
	
	
	;channel two...........................................................................
	
	mov R0, #00000001B ; Start bit:1
	lcall DO_SPI_G
	mov R0, #10000001B ; Single ended, read channel 
	lcall DO_SPI_G
	mov a, R1 ; R1 contains bits 8 and 9
	anl a, #00000011B ; We need only the two least significant bits
	mov Result1+1, a ; Save result1 high.
	mov R0, #55H ; It doesn't matter what we transmit...
	lcall DO_SPI_G
	mov Result1, R1 ; R1 contains bits 0 to 7. Save result low.
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	
	setb CE_ADC
	lcall Display
	set_Cursor(1,10)
	Display_BCD(result)
	Wait_Milli_Seconds(#150)
	Wait_Milli_Seconds(#150)
	Wait_Milli_Seconds(#200)
	sjmp Forever

Display:
	;result manipulation..........................................
	mov x+0, Result+0
	mov x+1, Result+1
	mov x+2, #0
	mov x+3, #0
	Load_y(10000)
	lcall mul32 ;result*10k avoids 
	Load_y(1023)
	lcall div32
	Load_y(5)
	lcall mul32 ;gets Vout*100k
	Load_y(100)
	lcall mul32 ; Vout*100
	Load_y(273)
	lcall sub32 ;gives temp*10000
	Load_y(10000)
	lcall div32
	Load_y(273)
	lcall sub32
	mov Result+0 , x+0 
	mov Result+1 , x+1 
	
	
	;result 1 manipulation................................................
	mov x+0, Result1+0
	mov x+1, Result1+1
	mov x+2, #0
	mov x+3, #0
	load_y(50000)
	lcall mul32
	load_y(1023)
	lcall div32
	load_y(23)
	lcall sub32
	load_y(41)
	lcall div32 
	load_y(273)
	lcall sub32
	
	
	;add the two...............................................................
	
	mov x+0, Result+0
	mov x+1, Result+1
	mov x+2, #0
	mov x+3, #0
	
	mov x+0, Result+0
	mov x+1, Result+1
	mov x+2, #0
	mov x+3, #0
	mov y+0, Result1+0
	mov y+1, Result1+1
	mov y+2, #0
	mov y+3, #0
	lcall add32
	lcall hex2bcd
	
	
	mov a, bcd+1
	swap a
	anl a, #0x0f
	orl a, #0x30
	lcall putchar

	mov a, bcd+1
	anl a, #0x0f
	orl a, #0x30
	lcall putchar

	mov a, bcd+0
	swap a
	anl a, #0x0f
	orl a, #0x30
	lcall putchar

	mov a, bcd+0
	anl a, #0x0f
	orl a, #0x30
	lcall putchar
	
	set_Cursor(1,10)
	Display_BCD(bcd)

Continue:
	mov a, #'\r'
	lcall putchar
	mov a, #'\n'
	lcall putchar
	
ret
    
END