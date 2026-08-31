# Clock signal (100 MHz)
set_property PACKAGE_PIN W5 [get_ports clk]
    set_property IOSTANDARD LVCMOS33 [get_ports clk]
    create_clock -add -name clk -period 10.00 -waveform {0 5} [get_ports clk]

# System Reset (Slide Switch SW0 - Flip UP to run, DOWN to reset)
set_property PACKAGE_PIN V17 [get_ports rst_n]
    set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# Auto-baud Locked Indicator (LED 0)
set_property PACKAGE_PIN U16 [get_ports locked_led]
    set_property IOSTANDARD LVCMOS33 [get_ports locked_led]

# USB-UART Interface
set_property PACKAGE_PIN B18 [get_ports RsRx]
    set_property IOSTANDARD LVCMOS33 [get_ports RsRx]
set_property PACKAGE_PIN A18 [get_ports RsTx]
    set_property IOSTANDARD LVCMOS33 [get_ports RsTx]