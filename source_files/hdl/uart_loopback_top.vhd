--------------------------------------------------------------------------------
-- File Name    : uart_loopback_top.vhd
-- Author       : Imran
-- Description  : Top-level structural module for UART auto-baud loopback testing.
--                Echoes characters received from the PC back to the PC.
--
-- Note         : The terminal MUST send a capital 'U' (ASCII 0x55) first to 
--                calibrate the receiver's auto-baud estimator.
--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY uart_loopback_top IS
    GENERIC (
        CLK_FREQ   : INTEGER := 100000000;  -- 100 MHz
        BAUD_RATE  : INTEGER := 9600        -- Fixed TX baud rate
    );
    PORT (
        clk        : IN STD_LOGIC;
        rst_n      : IN STD_LOGIC;          -- Map to a physical button
        RsRx       : IN STD_LOGIC;          -- USB-UART Rx pin (from PC)
        RsTx       : OUT STD_LOGIC;         -- USB-UART Tx pin (to PC)
        locked_led : OUT STD_LOGIC          -- LED to indicate successful baud lock
    );
END uart_loopback_top;

ARCHITECTURE structural OF uart_loopback_top IS
    
    SIGNAL data_bus_s    : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL data_valid_s  : STD_LOGIC;
    SIGNAL baud_locked_s : STD_LOGIC;

BEGIN

    -- Route the lock signal to a physical LED 
    locked_led <= baud_locked_s;

    -- 1. Instantiate the Auto-Baud Receiver subsystem
    rx_sys_inst : ENTITY work.uart_rx_top
        GENERIC MAP (
            DATA_WIDTH  => 8
        )
        PORT MAP (
            clk         => clk,
            rst_n       => rst_n,
            uart_rx_bit => RsRx,
            data        => data_bus_s,
            data_valid  => data_valid_s,
            frame_err   => OPEN,
            baud_locked => baud_locked_s
        );

    -- 2. Instantiate the Standard Transmitter
    tx_inst : ENTITY work.uart_tx
        GENERIC MAP (
            CLK_FREQ   => CLK_FREQ,
            BAUD_RATE  => BAUD_RATE,
            DATA_WIDTH => 8
        )
        PORT MAP (
            clk    => clk,
            rst_n  => rst_n,
            data   => data_bus_s,
            tx_en  => data_valid_s,         -- RX triggers TX directly when a byte is ready
            tx_rdy => OPEN,
            tx_bit => RsTx
        );

END structural;
