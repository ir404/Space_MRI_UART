----------------------------------------------------------------------------------
-- Module Name:     host_interface
-- Author:          Imran
-- Last Modified:   16 September 2026
--
-- Description: A Host Interface Controller and packet parser. It receives 
--              incoming bytes from the UART receiver, decodes the header, 
--              assembles a 48-bit payload if applicable, and manages the 
--              hardware handshaking with the Accelerator.
--
-- Command Codes:
--   CMD_ACC : 0xA5 (8-byte packet: Header + 6 Payload + 1 CRC)
--   CMD_HK  : 0x5A (2-byte packet: Header + 1 CRC)
--
-- Ports:
--   clk        : System clock input.
--   rst_n      : Asynchronous active-low reset.
--   rx_data    : 8-bit data input from the UART receiver.
--   rx_valid   : Pulse HIGH when new rx_data is available.
--   acc_data   : 48-bit assembled payload sent to the Accelerator.
--   acc_en     : Enable flag; HIGH to trigger the Accelerator.
--   acc_done   : Done flag; HIGH when the Accelerator finishes processing.
--   header_err : Error flag; HIGH if an unknown header is received.
--   crc_err    : Error flag; HIGH if the CRC check fails (placeholder).
----------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY host_interface IS
    PORT (
        clk        : IN STD_LOGIC;
        rst_n      : IN STD_LOGIC;
        
        -- UART RX Interface
        rx_data    : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
        rx_valid   : IN STD_LOGIC;
        
        -- Hardware Accelerator Interface
        acc_data   : OUT STD_LOGIC_VECTOR(47 DOWNTO 0);
        acc_en     : OUT STD_LOGIC;
        acc_done   : IN STD_LOGIC;
        
        -- Diagnostic Outputs
        header_err : OUT STD_LOGIC;
        crc_err    : OUT STD_LOGIC
    );
END host_interface;

ARCHITECTURE behavioural OF host_interface IS 

    -- Command Constants
    CONSTANT CMD_ACC : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"A5";
    CONSTANT CMD_HK  : STD_LOGIC_VECTOR(7 DOWNTO 0) := x"5A";

    -- State Machine Definition
    TYPE state_type IS (IDLE, PROCESS_HEADER, FORM_PAYLOAD, CRC, ACC, HK);
    SIGNAL state_s : state_type := IDLE;

    -- Internal Registers
    SIGNAL header_reg_s  : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL payload_reg_s : STD_LOGIC_VECTOR(47 DOWNTO 0) := (OTHERS => '0');
    SIGNAL crc_value_s   : STD_LOGIC_VECTOR(7 DOWNTO 0) := (OTHERS => '0');
    
    SIGNAL byte_count_s  : INTEGER RANGE 0 TO 5 := 0;
    
    -- Output Register Signals
    SIGNAL acc_en_s      : STD_LOGIC := '0';
    SIGNAL header_err_s  : STD_LOGIC := '0';
    SIGNAL crc_err_s     : STD_LOGIC := '0';

BEGIN 

    PROCESS (clk, rst_n)
    BEGIN
        IF rst_n = '0' THEN 
            state_s       <= IDLE;
            header_reg_s  <= (OTHERS => '0');
            payload_reg_s <= (OTHERS => '0');
            crc_value_s   <= (OTHERS => '0');
            byte_count_s  <= 0;
            acc_en_s      <= '0';
            header_err_s  <= '0';
            crc_err_s     <= '0';
            
        ELSIF rising_edge(clk) THEN 
            
            -- Output default assignments
            acc_en_s     <= '0';
            header_err_s <= '0';
            crc_err_s    <= '0';

            CASE state_s IS 
                WHEN IDLE =>
                    IF rx_valid = '1' THEN
                        header_reg_s <= rx_data;
                        state_s      <= PROCESS_HEADER;
                    END IF;

                WHEN PROCESS_HEADER =>
                    IF header_reg_s = CMD_ACC THEN
                        byte_count_s <= 0;
                        state_s      <= FORM_PAYLOAD;
                        
                    ELSIF header_reg_s = CMD_HK THEN
                        state_s      <= HK;
                        
                    ELSE
                        header_err_s <= '1'; -- Flag the error for one clock cycle
                        state_s      <= IDLE;
                    END IF;

                WHEN FORM_PAYLOAD =>
                    IF rx_valid = '1' THEN
                        -- Shift register: push old bytes left, append new byte to the right
                        payload_reg_s <= payload_reg_s(39 DOWNTO 0) & rx_data;
                        
                        IF byte_count_s = 5 THEN
                            state_s <= CRC;
                        ELSE
                            byte_count_s <= byte_count_s + 1;
                        END IF;
                    END IF;

                WHEN CRC =>
                    IF rx_valid = '1' THEN
                        crc_value_s <= rx_data;
                        -- TODO: Implement hardware CRC comparison here
                        state_s <= ACC;
                    END IF;

                WHEN ACC =>
                    acc_en_s <= '1'; -- Assert enable to wake up the accelerator
                    
                    IF acc_done = '1' THEN
                        acc_en_s <= '0';
                        state_s  <= IDLE;
                    END IF;

                WHEN HK =>
                    IF rx_valid = '1' THEN
                        crc_value_s <= rx_data;
                        -- TODO: Implement hardware CRC comparison here
                        -- TODO: Trigger housekeeping logic here
                        state_s <= IDLE;
                    END IF;

            END CASE;
        END IF;
    END PROCESS;

    -- Output Pin Assignments
    acc_data   <= payload_reg_s;
    acc_en     <= acc_en_s;
    header_err <= header_err_s;
    crc_err    <= crc_err_s;

END behavioural;
