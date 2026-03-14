import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, ClockCycles

@cocotb.test()
async def test_project(dut):
    dut._log.info("Starting Fibonacci 7-Segment Test")
    
    # 1. Setup Clock: 1kHz (1ms period) to match multiplexing requirements
    clock = Clock(dut.clk, 1, units="ms")
    cocotb.start_soon(clock.start())

    # 2. Reset Sequence
    dut._log.info("Applying Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0      # Ensure manual step is low
    dut.uio_in.value = 0
    dut.rst_n.value = 0      # Active low reset
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1      # Release reset
    await ClockCycles(dut.clk, 5)

    # 3. Test Fibonacci 0 (Initial State)
    dut._log.info("Checking Initial State: Fibonacci 0")
    
    # Wait for signals to stabilize
    await ClockCycles(dut.clk, 2)
    
    # Mask uo_out[6:0] to get only 7-segment patterns (ignore ready bit [7])
    segments = int(dut.uo_out.value) & 0x7F
    
    # In the Verilog code, digit '0' is mapped to 7'b0111111 (0x3F)
    dut._log.info(f"Segments for digit 0: {hex(segments)} (Expected: 0x3f)")
    assert segments == 0x3f, f"Error: Fibonacci 0 should show 0x3f, but got {hex(segments)}"

    # 4. Trigger Manual Step (ui_in[0])
    dut._log.info("Pulsing ui_in[0] to request next Fibonacci number")
    dut.ui_in.value = 1      # Pulse high
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = 0      # Return to low
    
    # 5. Wait for BCD Conversion
    # Double Dabble takes 17 cycles. Waiting 20 to be safe.
    dut._log.info("Waiting for BCD conversion (Double Dabble process)...")
    await ClockCycles(dut.clk, 20)
    
    # 6. Test Fibonacci 1 (Next State)
    # The next number is 1. Digit '1' is 7'b0000110 (0x06) in your Verilog
    segments = int(dut.uo_out.value) & 0x7F
    dut._log.info(f"Segments for digit 1: {hex(segments)} (Expected: 0x06)")
    
    assert segments == 0x06, f"Error: Fibonacci 1 should show 0x06, but got {hex(segments)}"

    dut._log.info("All manual step and conversion tests passed successfully!")

