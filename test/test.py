import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Helper function to wait for a specific digit to be active and return its segments
async def get_segments_for_digit(dut, digit_mask):
    # Wait up to 10 cycles to find the right digit in the multiplexing cycle
    for _ in range(10):
        # Check if the active digit (uio_out) matches our mask (e.g., 00001 for units)
        if (int(dut.uio_out.value) & 0x1F) == digit_mask:
            return int(dut.uo_out.value) & 0x7F
        await RisingEdge(dut.clk)
    return None

@cocotb.test()
async def test_fibonacci_sequence(dut):
    dut._log.info("Starting Multiplexed Display Test")
    
    clock = Clock(dut.clk, 1, units="ms")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.ena.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    # Fibonacci Sequence to test: 0, 1, 1, 2, 3, 5, 8, 13...
    expected_values = [
        {"val": 0, "seg": 0x3f},
        {"val": 1, "seg": 0x06},
        {"val": 1, "seg": 0x06},
        {"val": 2, "seg": 0x5b}
    ]

    for item in expected_values:
        dut._log.info(f"Testing Fibonacci number: {item['val']}")

        # 1. Wait until BCD is ready (Bit 7 of uo_out)
        while (int(dut.uo_out.value) & 0x80) == 0:
            await RisingEdge(dut.clk)

        # 2. Capture segments specifically when Digit 0 (Units) is active
        # Digit 0 mask is 5'b00001 (0x01)
        segments = await get_segments_for_digit(dut, 0x01)
        
        dut._log.info(f"Detected segments: {hex(segments)} for digit 0")
        assert segments == item['seg'], f"Error: Expected {hex(item['seg'])}, got {hex(segments)}"

        # 3. Pulse 'advance' for next number (using ui_in[0])
        dut.ui_in.value = 1
        await ClockCycles(dut.clk, 2)
        dut.ui_in.value = 0
        
        # Wait a bit for the conversion to start (ready goes low)
        await ClockCycles(dut.clk, 2)

    dut._log.info("Multiplexed sequence test passed!")
