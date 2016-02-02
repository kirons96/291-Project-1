		mov a, state
state0:
		cjne a, #0, state1
		mov pwm, #0
		jb P0.3, state0_done
		lcall wait50ms ; debounce time
		jb P0.3, state0_done
		jnb P0.3, $ ; Wait for key release
		mov state, #1
state0_done:
		ljmp forever
state1:
		cjne a, #1, state2
		mov pwm, #100
		mov sec, #0
		mov a, #150
		clr c
		subb a, temp
		jnc state1_done
		mov state, #2
state1_done:
		ljmp forever
state2:
		cjne a, #2, state3
		mov pwm, #20
		mov a, #60
		clr c
		subb a, sec
		jnc state2_done
		mov state, #3
state2_done:
		ljmp forever
