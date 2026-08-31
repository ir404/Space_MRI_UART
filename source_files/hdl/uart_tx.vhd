----------------------------------------------------------------------------------
-- Module Name:     uart_tx
-- Author:          Imran
-- Last Modified:   1 September 2026
--
-- Description: A customisable UART transmitter module. It takes parallel data 
--              and transmits it serially based on a configurable baud rate and 
--              system clock frequency. 
--              Configuration: 8N2
--              The transmission frame format consists of:
--                  1 Start bit ('0') + Data bits + 2 Stop bits ('1').
--
-- Generics:
--   CLK_FREQ   : System clock frequency in Hz.
--   BAUD_RATE  : Target transmission baud rate in bps.
--   DATA_WIDTH : Width of the data payload in bits (usually 8 bits).
--
-- Ports:
--   clk        : System clock input.
--   rst_n      : Asynchronous active-low reset.
--   data       : Parallel data payload to transmit.
--   tx_en      : Transmission enable; drive HIGH to start sending.
--   tx_rdy     : Ready flag; HIGH when the module is idle and ready for new data.
--   tx_bit     : Serial data output line.
----------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY uart_tx IS
    GENERIC (
        CLK_FREQ   : INTEGER := 100000000;  -- System clock frequency in Hz
        BAUD_RATE  : INTEGER := 9600;       -- Target baud rate in bps
        DATA_WIDTH : INTEGER := 8           -- Payload width in bits
    );
    PORT (
        clk     : IN STD_LOGIC;
        rst_n   : IN STD_LOGIC;         -- Active-low reset (asynchronous)
        data    : IN STD_LOGIC_VECTOR(DATA_WIDTH-1 DOWNTO 0);
        tx_en   : IN STD_LOGIC;         -- HIGH to start serial transmission
        tx_rdy  : OUT STD_LOGIC;        -- HIGH when ready for new data (IDLE state)
        tx_bit  : OUT STD_LOGIC         -- Serial output data line
    );
END uart_tx;

ARCHITECTURE behavioural OF uart_tx IS

    CONSTANT BAUD_PERIOD    : INTEGER   := CLK_FREQ / BAUD_RATE;
    CONSTANT PACKET_WIDTH   : INTEGER   := DATA_WIDTH + 3;      -- Start(1) + Data + Stop(2)
    CONSTANT START_BIT      : STD_LOGIC := '0';
    CONSTANT STOP_BIT       : STD_LOGIC := '1';
    
    -- State definition
    TYPE state_type IS (IDLE, LOAD_BIT, SEND_BIT);

    -- Internal signals
    SIGNAL state_s  : state_type := IDLE;
    SIGNAL timer_s  : INTEGER RANGE 0 TO BAUD_PERIOD := 0;
    SIGNAL packet_s : STD_LOGIC_VECTOR(PACKET_WIDTH - 1 DOWNTO 0) := (OTHERS => '1'); 
    SIGNAL bit_ix_s : INTEGER RANGE 0 TO PACKET_WIDTH - 1 := 0;
    SIGNAL tx_reg_s : STD_LOGIC := STOP_BIT;

BEGIN 

    PROCESS (clk, rst_n)
        VARIABLE state_v  : state_type; 
        VARIABLE bit_ix_v : INTEGER RANGE 0 TO PACKET_WIDTH - 1;
    BEGIN 
        
        IF rst_n = '0' THEN                 -- Asynchronous reset 
            state_s  <= IDLE;
            timer_s  <= 0;
            packet_s <= (OTHERS => '1');
            bit_ix_s <= 0;      -- Bit index to track which bit to transmit serially
            tx_reg_s <= STOP_BIT;
            
        ELSIF rising_edge(clk) THEN         -- On clk rising edge 
            state_v  := state_s;
            bit_ix_v := bit_ix_s;

            CASE state_v IS
                WHEN IDLE => 
                    tx_reg_s <= STOP_BIT;
                    bit_ix_v := 0;
                    
                    IF tx_en = '1' THEN 
                        -- Assemble full frame: [Stop, Stop, Data, Start]
                        packet_s <= STOP_BIT & STOP_BIT & data & START_BIT; 
                        state_v  := LOAD_BIT;
                    END IF;

                WHEN LOAD_BIT => 
                    -- Latch the current bit to the output register
                    tx_reg_s <= packet_s(bit_ix_v);
                    state_v  := SEND_BIT;

                WHEN SEND_BIT => 
                    -- Hold bit for the duration of the baud period.
                    IF timer_s = BAUD_PERIOD - 1 THEN
                        timer_s <= 0;
                        
                        IF bit_ix_v = PACKET_WIDTH - 1 THEN
                            state_v := IDLE;
                        ELSE
                            bit_ix_v := bit_ix_v + 1; -- Move to next bit index
                            state_v  := LOAD_BIT;
                        END IF;
                    ELSE 
                        timer_s <= timer_s + 1;
                    END IF;
            END CASE;

            -- Synchronise signals from variables
            state_s  <= state_v;
            bit_ix_s <= bit_ix_v;
        END IF;
    END PROCESS;

    -- Assign values to output signals
    tx_rdy <= '1' WHEN (state_s = IDLE) ELSE '0';
    tx_bit <= tx_reg_s;

END behavioural;