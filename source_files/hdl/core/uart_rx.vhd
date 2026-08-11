--------------------------------------------------------------------------------
-- File Name    : uart_rx.vhd
-- Author       : Imran
-- Description  : Universal Asynchronous Receiver-Transmitter (UART) Receiver 
--                with Auto-Baud Detection for space applications.
--                
--                The module utilises a Finite State Machine (FSM) to manage 
--                transmission states and handles internal logic using variables 
--                to prevent signal scheduling delays.
--
-- Parameters   : DATA_WIDTH - Payload width in bits (default: 8)
--
-- Dependencies : IEEE.STD_LOGIC_1164, IEEE.NUMERIC_STD
--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY uart_rx IS
    GENERIC (
        DATA_WIDTH  : INTEGER := 8
    );
    PORT (
        clk         : IN STD_LOGIC;
        rst_n       : IN STD_LOGIC;                                 -- Active-low reset for fault recovery
        uart_rx_bit : IN STD_LOGIC;                                 -- Serial input data line
        data        : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);-- Full data payload received 
        data_valid  : OUT STD_LOGIC;                                -- HIGH for one clk cycle when data is valid
        frame_err   : OUT STD_LOGIC;                                -- HIGH if framing error occurs (missing stop bit)
        baud_err    : OUT STD_LOGIC                                 -- HIGH if auto-baud times out
    );
END uart_rx;

ARCHITECTURE behavioural OF uart_rx IS 

    CONSTANT START_BIT   : STD_LOGIC := '0';
    CONSTANT STOP_BIT    : STD_LOGIC := '1';
    CONSTANT FILTER_MAX  : INTEGER   := 5;          -- Clock cycles to wait for glitch filtering
    CONSTANT TIMEOUT_MAX : INTEGER   := 1000000;    -- Max clock cycles before auto-baud timeout

    -- State definition
    TYPE state_type IS (IDLE, DETECT_START, MEASURE_PULSE, LATCH_BAUD, READ_DATA, CHECK_STOP);

    -- Internal signals
    SIGNAL state_s          : state_type := IDLE;
    SIGNAL timer_s          : INTEGER := 0;
    SIGNAL baud_period_s    : INTEGER := 0;
    SIGNAL bit_ix_s         : INTEGER RANGE 0 TO DATA_WIDTH - 1 := 0;
    SIGNAL data_reg_s       : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL frame_err_s      : STD_LOGIC := '0';
    SIGNAL baud_err_s       : STD_LOGIC := '0';
    SIGNAL data_valid_s     : STD_LOGIC := '0';
    
    -- Double-flop synchroniser signals
    SIGNAL rx_sync1_s       : STD_LOGIC := STOP_BIT;
    SIGNAL rx_sync2_s       : STD_LOGIC := STOP_BIT;
    SIGNAL rx_prev_s        : STD_LOGIC := STOP_BIT;
    
    -- Glitch filter counter
    SIGNAL filter_cnt_s     : INTEGER RANGE 0 TO 7 := 0;

BEGIN 

    PROCESS (clk, rst_n)
        -- Variables for seq logic
        VARIABLE state_v      : state_type;
        VARIABLE timer_v      : INTEGER;
        VARIABLE baud_period_v: INTEGER;
        VARIABLE bit_ix_v     : INTEGER RANGE 0 TO DATA_WIDTH - 1;
        VARIABLE data_reg_v   : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
        VARIABLE frame_err_v  : STD_LOGIC;
        VARIABLE baud_err_v   : STD_LOGIC;
        VARIABLE data_valid_v : STD_LOGIC;
        VARIABLE filter_cnt_v : INTEGER RANGE 0 TO 7;
    BEGIN
        IF rst_n = '0' THEN 
            -- Asynchronous reset safe defaults
            state_s       <= IDLE;
            timer_s       <= 0;
            baud_period_s <= 0;
            bit_ix_s      <= 0;
            data_reg_s    <= (OTHERS => '0');
            frame_err_s   <= '0';
            baud_err_s    <= '0';
            data_valid_s  <= '0';
            rx_sync1_s    <= STOP_BIT;
            rx_sync2_s    <= STOP_BIT;
            rx_prev_s     <= STOP_BIT;
            filter_cnt_s  <= 0;
            
        ELSIF rising_edge(clk) THEN 
            
            -- 2-stage synchroniser to safely bring rx into the clock domain
            rx_sync1_s <= uart_rx_bit;
            rx_sync2_s <= rx_sync1_s;
            rx_prev_s  <= rx_sync2_s;

            -- Load variables from signals
            state_v       := state_s;
            timer_v       := timer_s;
            baud_period_v := baud_period_s;
            bit_ix_v      := bit_ix_s;
            data_reg_v    := data_reg_s;
            frame_err_v   := frame_err_s;
            baud_err_v    := baud_err_s;
            filter_cnt_v  := filter_cnt_s;
            data_valid_v  := '0'; -- Default low so it only pulses for 1 cycle

            CASE state_v IS 
                WHEN IDLE =>
                    baud_err_v := '0';
                    -- Check for transition from idle to start
                    IF rx_prev_s = STOP_BIT AND rx_sync2_s = START_BIT THEN  
                        state_v      := DETECT_START;
                        filter_cnt_v := 0;
                    END IF;

                WHEN DETECT_START =>
                    -- Ensure the line stays at the start bit level to filter glitches
                    IF rx_sync2_s = STOP_BIT THEN 
                        state_v := IDLE; 
                    ELSE 
                        IF filter_cnt_v = FILTER_MAX THEN
                            state_v := MEASURE_PULSE;
                            timer_v := 0;
                        ELSE
                            filter_cnt_v := filter_cnt_v + 1;
                        END IF;
                    END IF;

                WHEN MEASURE_PULSE =>
                    timer_v := timer_v + 1;
                    
                    -- Check for transition back to stop/idle level (End of Start bit / Beginning of D0)
                    IF rx_prev_s = START_BIT AND rx_sync2_s = STOP_BIT THEN  
                        state_v := LATCH_BAUD;
                        
                    -- Timeout protection in case line goes completely dead
                    ELSIF timer_v = TIMEOUT_MAX THEN 
                        baud_err_v := '1';
                        state_v    := IDLE;
                    END IF;

                WHEN LATCH_BAUD =>
                    baud_period_v := timer_v;
                    -- Halve the timer to sample the next bit exactly in its centre
                    timer_v       := timer_v / 2; 
                    bit_ix_v      := 0;
                    state_v       := READ_DATA;

                WHEN READ_DATA => 
                    IF timer_v = 0 THEN 
                        -- Reset timer for a full baud period and sample data
                        timer_v := baud_period_v;
                        data_reg_v(bit_ix_v) := rx_sync2_s;

                        IF bit_ix_v = DATA_WIDTH - 1 THEN
                            state_v := CHECK_STOP;
                        ELSE
                            bit_ix_v := bit_ix_v + 1;
                        END IF;
                    ELSE 
                        timer_v := timer_v - 1;
                    END IF;

                WHEN CHECK_STOP =>
                    IF timer_v = 0 THEN
                        IF rx_sync2_s = STOP_BIT THEN
                            frame_err_v  := '0';
                            data_valid_v := '1';
                        ELSE 
                            frame_err_v  := '1';
                        END IF;
                        state_v := IDLE;
                    ELSE 
                        timer_v := timer_v - 1;
                    END IF;

            END CASE;

            -- Update signals from variables at the end of the process
            state_s       <= state_v;
            timer_s       <= timer_v;
            baud_period_s <= baud_period_v;
            bit_ix_s      <= bit_ix_v;
            data_reg_s    <= data_reg_v;
            frame_err_s   <= frame_err_v;
            baud_err_s    <= baud_err_v;
            data_valid_s  <= data_valid_v;
            filter_cnt_s  <= filter_cnt_v;
        END IF;
    END PROCESS;

    -- Update the output ports
    data       <= data_reg_s;
    data_valid <= data_valid_s;
    frame_err  <= frame_err_s;
    baud_err   <= baud_err_s;
    
END behavioural;