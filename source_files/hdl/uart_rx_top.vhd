----------------------------------------------------------------------------------
-- Module Name:     uart_rx_top
-- Author:          Imran
-- Last Modified:   1 September 2026
--
-- Description: A top-level structural wrapper for the UART receiver subsystem. 
--              It connects the autobaud estimator directly to the standard 
--              receiver module. It routes the internal feedback loop required 
--              to force a system recalibration if a framing error occurs.
--
-- Generics:
--   DATA_WIDTH  : Width of the received data payload in bits (usually 8 bits).
--
-- Ports:
--   clk         : System clock input.
--   rst_n       : Asynchronous active-low reset.
--   uart_rx_bit : Serial data input line.
--   data        : Parallel data payload received.
--   data_valid  : Valid flag; HIGH when a full, error-free frame is received.
--   frame_err   : Error flag; HIGH if the expected stop bit is missing.
--   baud_locked : Lock flag; HIGH when the estimator has found a valid baud rate.
----------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY uart_rx_top IS
    GENERIC (
        DATA_WIDTH : INTEGER := 8
    );
    PORT (
        clk         : IN STD_LOGIC;
        rst_n       : IN STD_LOGIC;
        uart_rx_bit : IN STD_LOGIC;
        data        : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
        data_valid  : OUT STD_LOGIC;
        frame_err   : OUT STD_LOGIC;
        baud_locked : OUT STD_LOGIC         -- Exposing the lock status
    );
END uart_rx_top;

ARCHITECTURE structural OF uart_rx_top IS

    -- Internal "wires" connecting the Estimator and the Receiver
    SIGNAL baud_period_s : INTEGER;
    SIGNAL baud_locked_s : STD_LOGIC;
    SIGNAL frame_err_s   : STD_LOGIC;

BEGIN

    -- Route the internal status signals out to the top-level output pins
    baud_locked <= baud_locked_s;
    frame_err   <= frame_err_s;

    -- 1. Instantiate the Autobaud Estimator
    estimator_inst : ENTITY work.autobaud_estimator
        PORT MAP (
            clk          => clk,
            rst_n        => rst_n,
            uart_rx_bit  => uart_rx_bit,
            frame_err_in => frame_err_s,   -- Feedback loop from the receiver
            baud_period  => baud_period_s,
            baud_locked  => baud_locked_s
        );

    -- 2. Instantiate the Standard UART Receiver
    uart_rx_inst : ENTITY work.uart_rx
        GENERIC MAP (
            DATA_WIDTH  => DATA_WIDTH
        )
        PORT MAP (
            clk         => clk,
            rst_n       => rst_n,
            uart_rx_bit => uart_rx_bit,
            baud_period => baud_period_s,  
            baud_locked => baud_locked_s,  -- Gates the receiver's IDLE state
            data        => data,
            data_valid  => data_valid,
            frame_err   => frame_err_s     -- Drives the top-level pin and estimator reset
        );

END structural;
