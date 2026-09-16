----------------------------------------------------------------------------------
-- Module Name:     space_mri_top
-- Author:          Imran
-- Last Modified:   17 September 2026
--
-- Description: Top-level structural wrapper for the Space MRI receiver system.
--              It integrates the UART receiver subsystem, the Host Interface 
--              parser, and the dummy hardware accelerator, wiring all data 
--              buses and hardware handshaking signals together.
----------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY space_mri_top IS
    PORT (
        clk              : IN STD_LOGIC;
        rst_n            : IN STD_LOGIC;
        
        -- Serial Input
        uart_rx_bit      : IN STD_LOGIC;
        
        -- Encoded Output (from Accelerator)
        encoded_data_out : OUT STD_LOGIC_VECTOR(47 DOWNTO 0);
        acc_done_out     : OUT STD_LOGIC;
        
        -- Status & Diagnostic Flags
        baud_locked_out  : OUT STD_LOGIC;
        frame_err_out    : OUT STD_LOGIC;
        header_err_out   : OUT STD_LOGIC;
        crc_err_out      : OUT STD_LOGIC
    );
END space_mri_top;

ARCHITECTURE structural OF space_mri_top IS

    -- Signals between UART RX and Host Interface
    SIGNAL rx_data_s       : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL rx_data_valid_s : STD_LOGIC;
    SIGNAL frame_err_s     : STD_LOGIC;
    SIGNAL baud_locked_s   : STD_LOGIC;

    -- Signals between Host Interface and Accelerator
    SIGNAL acc_data_in_s   : STD_LOGIC_VECTOR(47 DOWNTO 0);
    SIGNAL acc_en_s        : STD_LOGIC;
    SIGNAL acc_done_s      : STD_LOGIC;
    
    -- Signal for encoded data out
    SIGNAL acc_data_out_s  : STD_LOGIC_VECTOR(47 DOWNTO 0);

BEGIN

    -- Route internal status signals to top-level pins for monitoring
    baud_locked_out  <= baud_locked_s;
    frame_err_out    <= frame_err_s;
    acc_done_out     <= acc_done_s;
    encoded_data_out <= acc_data_out_s;

    -- 1. UART Receiver Subsystem
    uart_rx_inst : ENTITY work.uart_rx_top
        GENERIC MAP (
            DATA_WIDTH  => 8
        )
        PORT MAP (
            clk         => clk,
            rst_n       => rst_n,
            uart_rx_bit => uart_rx_bit,
            data        => rx_data_s,
            data_valid  => rx_data_valid_s,
            frame_err   => frame_err_s,
            baud_locked => baud_locked_s
        );

    -- 2. Host Interface / Packet Parser
    host_interface_inst : ENTITY work.host_interface
        PORT MAP (
            clk         => clk,
            rst_n       => rst_n,
            rx_data     => rx_data_s,
            rx_valid    => rx_data_valid_s,
            acc_data    => acc_data_in_s,
            acc_en      => acc_en_s,
            acc_done    => acc_done_s,
            header_err  => header_err_out,
            crc_err     => crc_err_out
        );

    -- 3. Dummy Hardware Accelerator (Caesar Cipher)
    dummy_acc_inst : ENTITY work.dummy_accelerator
        PORT MAP (
            clk         => clk,
            rst_n       => rst_n,
            acc_en      => acc_en_s,
            data_in     => acc_data_in_s,
            data_out    => acc_data_out_s,
            acc_done    => acc_done_s
        );

END structural;