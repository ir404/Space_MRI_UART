--------------------------------------------------------------------------------
-- File Name    : tb_uart_rx_top.vhd
-- Author       : Imran
-- Description  : Testbench for the auto-baud UART receiver system.
--                Verifies sync lock, data reception, and error recovery.
--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY tb_uart_rx_top IS
END tb_uart_rx_top;

ARCHITECTURE behavioural OF tb_uart_rx_top IS

    -- Constants
    CONSTANT CLK_PERIOD  : TIME := 10 ns;      -- 100 MHz system clk
    CONSTANT BAUD_PERIOD : TIME := 1000 ns;    -- 1 Mbps simulated baud rate (100 clk cycles)
    CONSTANT DATA_WIDTH  : INTEGER := 8;

    -- DUT Signals
    SIGNAL clk_s         : STD_LOGIC := '0';
    SIGNAL rst_n_s       : STD_LOGIC := '0';
    SIGNAL uart_rx_bit_s : STD_LOGIC := '1';
    SIGNAL data_s        : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL data_valid_s  : STD_LOGIC;
    SIGNAL frame_err_s   : STD_LOGIC;
    SIGNAL baud_locked_s : STD_LOGIC;

BEGIN

    -- Instantiate the Device Under Test (DUT)
    dut : ENTITY work.uart_rx_top
        GENERIC MAP (
            DATA_WIDTH => DATA_WIDTH
        )
        PORT MAP (
            clk         => clk_s,
            rst_n       => rst_n_s,
            uart_rx_bit => uart_rx_bit_s,
            data        => data_s,
            data_valid  => data_valid_s,
            frame_err   => frame_err_s,
            baud_locked => baud_locked_s
        );

    -- Clock generation process
    clk_process : PROCESS
    BEGIN
        clk_s <= '0';
        WAIT FOR CLK_PERIOD / 2;
        clk_s <= '1';
        WAIT FOR CLK_PERIOD / 2;
    END PROCESS;

    -- Main stimulus process
    stim_process : PROCESS
        
        -- Procedure to simulate the DPU sending a UART byte
        PROCEDURE send_uart_byte (
            CONSTANT byte_to_send : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
            CONSTANT force_err    : IN BOOLEAN := FALSE
        ) IS
        BEGIN
            -- Send start bit
            uart_rx_bit_s <= '0';
            WAIT FOR BAUD_PERIOD;
            
            -- Send data bits (LSB first)
            FOR i IN 0 TO 7 LOOP
                uart_rx_bit_s <= byte_to_send(i);
                WAIT FOR BAUD_PERIOD;
            END LOOP;
            
            -- Send Stop bit
            IF force_err THEN
                uart_rx_bit_s <= '0';  -- Deliberate framing error
            ELSE
                uart_rx_bit_s <= '1';  -- Normal stop bit
            END IF;
            WAIT FOR BAUD_PERIOD;
        END PROCEDURE;

    BEGIN
        -- Apply reset
        rst_n_s <= '0';
        WAIT FOR 50 ns;
        rst_n_s <= '1';
        WAIT FOR 100 ns;

        REPORT "--- TEST PHASE 1: Auto-Baud Lock ---";
        -- Send the 0x55 sync byte
        send_uart_byte(x"55", FALSE);
        -- Wait a bit to observe the lock asserting
        WAIT FOR 2000 ns;
        ASSERT baud_locked_s = '1' REPORT "Error: Receiver failed to lock on 0x55." SEVERITY error;

        REPORT "--- TEST PHASE 2: Normal Data Reception ---";
        -- Send a normal payload byte (0x3C)
        send_uart_byte(x"3C", FALSE);
        WAIT FOR 2000 ns;
        ASSERT data_s = x"3C" REPORT "Error: Data payload incorrectly read." SEVERITY error;
        
        REPORT "--- TEST PHASE 3: Error Injection & Unlock ---";
        -- Send a byte but force the stop bit to 0 to simulate a fault
        send_uart_byte(x"A5", TRUE);
        WAIT FOR 2000 ns;
        -- The frame_err_s should have pulsed, causing baud_locked_s to drop
        ASSERT baud_locked_s = '0' REPORT "Error: Receiver failed to drop lock after framing error." SEVERITY error;
        
        -- Ensure line returns to idle before next test
        uart_rx_bit_s <= '1';
        WAIT FOR 5000 ns;

        REPORT "--- TEST PHASE 4: Self-Healing Re-lock ---";
        -- Send the 0x55 sync byte again to recalibrate
        send_uart_byte(x"55", FALSE);
        WAIT FOR 2000 ns;
        ASSERT baud_locked_s = '1' REPORT "Error: Receiver failed to re-lock after an error." SEVERITY error;

        REPORT "--- ALL TESTS COMPLETE ---";
        WAIT; -- Suspend simulation
    END PROCESS;

END behavioural;
