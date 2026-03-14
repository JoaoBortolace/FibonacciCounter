import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Helper function to wait for a specific digit to be active and return its segments
async def get_segments_for_digit(dut, digit_mask):
    # Wait up to 20 cycles to find the right digit in the multiplexing cycle
    for _ in range(20):
        # Check if the active digit (uio_out) matches our mask (e.g., 0x01 for units)
        if (int(dut.uio_out.value) & 0x1F) == digit_mask:
            return int(dut.uo_out.value) & 0x7F
        await RisingEdge(dut.clk)
    return None

@cocotb.test()
async def test_fibonacci_sequence(dut):
    dut._log.info("Starting Consolidated Fibonacci & BCD Test")
    
    # 1. Setup Clock: 1kHz (1ms period)
    clock = Clock(dut.clk, 1, unit="ms")
    cocotb.start_soon(clock.start())

    # 2. Reset Sequence
    dut._log.info("Applying System Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    # 3. Define Sequence to Test (Value and Expected Unit Segment)
    # 0: 0x3f, 1: 0x06, 2: 0x5b, 3: 0x4f, 5: 0x6d, 8: 0x7d
    sequence = [
        {"val": 0, "seg": 0x3f},
        {"val": 1, "seg": 0x06},
        {"val": 1, "seg": 0x06},
        {"val": 2, "seg": 0x5b},
        {"val": 3, "seg": 0x4f},
        {"val": 5, "seg": 0x6d},
        {"val": 8, "seg": 0x7f}
    ]

    for item in sequence:
        dut._log.info(f"Testing Fibonacci: {item['val']}")
        
        # Wait for BCD Ready (Bit 7 of uo_out)
        while (int(dut.uo_out.value) & 0x80) == 0:
            await RisingEdge(dut.clk)

        # Verify Unit Digit (Digit 0 - Mask 0x01)
        seg_unit = await get_segments_for_digit(dut, 0x01)
        assert seg_unit == item['seg'], f"Error on {item['val']}: Expected {hex(item['seg'])}, got {hex(seg_unit)}"

        # Pulse advance for next number
        dut.ui_in.value = 1
        await ClockCycles(dut.clk, 2)
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 2) # Wait for conversion to start

    # 4. Special Test: Fibonacci 13 (Two Digits Validation)
    dut._log.info("Testing Fibonacci 13: Checking Units and Tens")
    
    # Wait for conversion of the 13 (which was requested in the last loop iteration)
    while (int(dut.uo_out.value) & 0x80) == 0:
        await RisingEdge(dut.clk)

    # Check Unit Digit (3) -> Expected 0x4f
    seg_unit_13 = await get_segments_for_digit(dut, 0x01)
    dut._log.info(f"Unit Digit (3): {hex(seg_unit_13)}")
    assert seg_unit_13 == 0x4f, f"Expected 0x4f for '3', got {hex(seg_unit_13)}"

    # Check Ten Digit (1) -> Expected 0x06
    seg_ten_13 = await get_segments_for_digit(dut, 0x02)
    dut._log.info(f"Ten Digit (1): {hex(seg_ten_13)}")
    assert seg_ten_13 == 0x06, f"Expected 0x06 for '1', got {hex(seg_ten_13)}"

    # 5. Overflow Test: Fibonacci 24 (46368) -> Fibonacci 25 (Overflows to 0)
    dut._log.info("Testing Max Fibonacci (46368) and Overflow behavior")

    # We force the internal registers to a value near the limit to save time
    # Note: 'dut.fib_inst' must match the instance name in your top-level
    dut.fib_inst.fib_number.value = 28657 # Fibonacci 23
    dut.fib_inst.aux_reg.value    = 17711 # Fibonacci 22
    
    # Pulse 'advance' to reach Fibonacci 24 (46368)
    dut.ui_in.value = 1
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = 0
    
    # Wait for conversion
    while (int(dut.uo_out.value) & 0x80) == 0:
        await RisingEdge(dut.clk)
        
    # Check if units of 46368 (which is '8') shows correctly
    seg_unit_max = await get_segments_for_digit(dut, 0x01)
    assert seg_unit_max == 0x7d, f"Expected 0x7d for digit '8', got {hex(seg_unit_max)}"
    dut._log.info("Successfully reached Fibonacci 46368")

    # Trigger OVERFLOW: 46368 + 28657 = 75025 (> 65535)
    dut._log.info("Triggering overflow (75025 > 16-bit)...")
    dut.ui_in.value = 1
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = 0
    
    while (int(dut.uo_out.value) & 0x80) == 0:
        await RisingEdge(dut.clk)

    # After overflow, the core should reset to 0
    seg_overflow = await get_segments_for_digit(dut, 0x01)
    assert seg_overflow == 0x3f, f"Expected 0x3f (0) after overflow, got {hex(seg_overflow)}"
    dut._log.info("Overflow handled correctly: Counter reset to 0")

    dut._log.info("Full sequence and multi-digit BCD tests passed!")
