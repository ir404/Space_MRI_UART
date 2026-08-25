--------------------------------------------------------------------------------
-- File Name    : uart_rx_top.vhd
-- Author       : Imran
-- Description  : Top-level structural wrapper for the UART Receiver system.
--                Wires the Autobaud Estimator directly to the Standard Receiver,
--                including the self-healing error feedback loop.
--
-- Parameters   : DATA_WIDTH - Payload width in bits (default: 8)
--------------------------------------------------------------------------------

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
