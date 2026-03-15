import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Segment map (gfedcba) from your Verilog code
SEG_MAP = [0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07, 0x7f, 0x6f]

async def get_segments_for_digit(dut, digit_index, num_dig):
    """
    Waits for the multiplexer to select a specific digit and returns its segments.
    digit_index: 0 (units) to 4 (ten thousands)
    """
    mask = 1 << digit_index
    for _ in range(20):
        if (int(dut.uio_out.value) & ((1 << num_dig) - 1)) == mask:
            return int(dut.uo_out.value) & 0x7F
        await RisingEdge(dut.clk)
    return None

@cocotb.test()
async def test_full_fibonacci_all_digits(dut):
    dut._log.info("Starting Full Fibonacci All-Digits Test")
    
    clock = Clock(dut.clk, 1, unit="ms")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.ena.value = 1
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # Fibonacci Golden Model (Python)
    fib_curr, fib_prev = 0, 1
    
    # We will test until it overflows (16-bit limit)

     # Get number of bits
    try:
        num_bits = int(dut.user_project.fib_inst.NUM_BITS.value)
    except AttributeError:
        # No GL Test, a hierarquia some. Defina manualmente o valor aqui:
        num_bits = 23 # Max in 7 displays
    
    max_value = (1 << num_bits) - 1

    try:
        num_dig = int(dut.user_project.fib_inst.NUM_DIG.value)
    except AttributeError:
        num_dig = 7 # Valor fixo para o pós-síntese
    
    dut._log.info(f"Test dynamic setup: NUM_BITS={num_bits}, NUM_DIG={num_dig}, MAX_VAL={max_value}")
    
    while fib_curr <= max_value:
        dut._log.info(f"--- Testing Fibonacci: {fib_curr} ---")

        # 1. Wait for BCD Ready (Bit 7 of uo_out)
        while (int(dut.uo_out.value) & 0x80) == 0:
            await RisingEdge(dut.clk)

        # 2. Check all 5 digits for the current number
        temp_val = fib_curr
        for i in range(num_dig):
            digit_val = temp_val % 10
            expected_seg = SEG_MAP[digit_val]
            
            actual_seg = await get_segments_for_digit(dut, i, num_dig)
            
            # Log only units or if digit is non-zero to keep log clean
            if i == 0 or temp_val > 0:
                dut._log.info(f"Digit {i}: Expected {digit_val} ({hex(expected_seg)}), Got {hex(actual_seg)}")
                assert actual_seg == expected_seg, f"Error at Fib {fib_curr}, Digit {i}!"
            
            temp_val //= 10

        # 3. Advance Fibonacci
        next_val = fib_curr + fib_prev
        if next_val > max_value: break # End of N-bit sequence
        
        fib_prev = fib_curr
        fib_curr = next_val

        # Pulse ui_in[0] to advance
        dut.ui_in.value = 1
        await ClockCycles(dut.clk, 2)
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 5) # Wait for conversion to start

    dut._log.info(f"--- Overflow ---")

    # Pulse ui_in[0] to advance
    dut.ui_in.value = 1
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 5) # Wait for conversion to start

    # 1. Wait for BCD Ready (Bit 7 of uo_out)
    while (int(dut.uo_out.value) & 0x80) == 0:
        await RisingEdge(dut.clk)

    # 2. Check all 5 digits for the current number
    temp_val = 0
    for i in range(5):
        digit_val = temp_val % 10
        expected_seg = SEG_MAP[digit_val]
        
        actual_seg = await get_segments_for_digit(dut, i, num_dig)
        
        # Log only units or if digit is non-zero to keep log clean
        if i == 0 or temp_val > 0:
            dut._log.info(f"Digit {i}: Expected {digit_val} ({hex(expected_seg)}), Got {hex(actual_seg)}")
            assert actual_seg == expected_seg, f"Error at Fib {fib_curr}, Digit {i}!"
        
        temp_val //= 10

    dut._log.info("Full sequence verified for ALL digits!")
