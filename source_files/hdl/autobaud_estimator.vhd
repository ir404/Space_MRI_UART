----------------------------------------------------------------------------------
-- Module Name:     autobaud_estimator
-- Author:          Imran
-- Last Modified:   1 September 2026
--
-- Description: A minimum-pulse auto-baud estimator for UART communication. It 
--              monitors the serial line for the shortest incoming pulse (using 
--              the 0x55 sync byte) to dynamically calculate the baud period. 
--              It includes timeout protection and self-healing error recovery,
--              dropping the lock to force recalibration if an error is detected.
--
-- Ports:
--   clk          : System clock input.
--   rst_n        : Asynchronous active-low reset.
--   uart_rx_bit  : Serial data input line.
--   frame_err_in : Error trigger from UART RX; drops lock to force recalibration.
--   baud_period  : Calculated baud period (in clock cycles) sent to the receiver.
--   baud_locked  : Lock flag; HIGH when a valid baud period is found and saved.
----------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY autobaud_estimator IS
    PORT (
        clk          : IN STD_LOGIC;
        rst_n        : IN STD_LOGIC;                -- Active-low reset
        uart_rx_bit  : IN STD_LOGIC;                -- Serial input line
        frame_err_in : IN STD_LOGIC;                -- Reset trigger from UART RX
        baud_period  : OUT INTEGER;                 -- Calculated clock cycles per bit
        baud_locked  : OUT STD_LOGIC                -- HIGH when a valid minimum is found and saved
    );
END autobaud_estimator;

ARCHITECTURE behavioural OF autobaud_estimator IS 
    
    CONSTANT RX_HIGH      : STD_LOGIC := '1';
    CONSTANT RX_LOW       : STD_LOGIC := '0';
    CONSTANT MAX_VAL      : INTEGER := 1000000;     -- Max clk cycles for a pulses. Used for initialisation.
    CONSTANT GLITCH_LIMIT : INTEGER := 5;           -- Min clk cycles a pulse must be to avoid glitches 

    TYPE state_type IS (IDLE, MEASURING);
    
    SIGNAL state_s        : state_type := IDLE;
    SIGNAL rx_sync1_s     : STD_LOGIC := RX_HIGH;
    SIGNAL rx_sync2_s     : STD_LOGIC := RX_HIGH;
    SIGNAL rx_prev_s      : STD_LOGIC := RX_HIGH;
    
    SIGNAL timer_s        : INTEGER := 0;
    SIGNAL min_pulse_s    : INTEGER := MAX_VAL;
    SIGNAL locked_s       : STD_LOGIC := '0';

BEGIN
    PROCESS (clk, rst_n)
        VARIABLE state_v     : state_type;
        VARIABLE timer_v     : INTEGER;
        VARIABLE min_pulse_v : INTEGER;
        VARIABLE locked_v    : STD_LOGIC;
    BEGIN
        IF rst_n = '0' THEN
            state_s     <= IDLE;
            rx_sync1_s  <= RX_HIGH;
            rx_sync2_s  <= RX_HIGH;
            rx_prev_s   <= RX_HIGH;
            timer_s     <= 0;
            min_pulse_s <= MAX_VAL;
            locked_s    <= '0';
            
        ELSIF rising_edge(clk) THEN
            -- 2-FF synchroniser
            rx_sync1_s <= uart_rx_bit;
            rx_sync2_s <= rx_sync1_s;
            rx_prev_s  <= rx_sync2_s;
            
            state_v     := state_s;
            timer_v     := timer_s;
            min_pulse_v := min_pulse_s;
            locked_v    := locked_s;

            -- Self-healing error recovery when rx detects a frame error
            IF frame_err_in = '1' THEN
                min_pulse_v := MAX_VAL;   -- reset the bad baud period to max
                locked_v    := '0';       -- drop the lock
                state_v     := IDLE;
            ELSE
                CASE state_v IS
                    WHEN IDLE =>                                                -- Wait for the sync byte 0b01010101
                        -- On falling edge, start timing the pulse 
                        IF rx_prev_s = RX_HIGH AND rx_sync2_s = RX_LOW THEN
                            state_v := MEASURING;
                            timer_v := 0;
                        END IF;
                        
                    WHEN MEASURING =>                                           -- Measure how long a bit stays low and determines the baud period
                        -- On rising edge, evaluate the measured pulse 
                        IF rx_prev_s = RX_LOW AND rx_sync2_s = RX_HIGH THEN
                            -- Ensure it wasn't a glitch
                            IF timer_v > GLITCH_LIMIT THEN
                                -- If this pulse is the shorter than the current minimum, make it the new minimum
                                IF timer_v < min_pulse_v THEN
                                    min_pulse_v := timer_v;
                                    locked_v    := '1';
                                END IF;
                            END IF;

                            state_v := IDLE;
                        
                        ELSIF timer_v = MAX_VAL THEN     -- Timeout protection (eg. if the line is disconnected) 
                            min_pulse_v := MAX_VAL;         -- reset the baud period to max
                            locked_v := '0';                -- drop the lock
                            state_v  := IDLE;
                        ELSE
                            timer_v := timer_v + 1;
                        END IF;
                END CASE;
            END IF;
            
            state_s     <= state_v;
            timer_s     <= timer_v;
            min_pulse_s <= min_pulse_v;
            locked_s    <= locked_v;
        END IF;
    END PROCESS;

    -- Output signal assignment
    baud_period <= min_pulse_s;
    baud_locked <= locked_s;
        
END behavioural;