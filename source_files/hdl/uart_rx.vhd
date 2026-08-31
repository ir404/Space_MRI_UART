--------------------------------------------------------------------------------
-- File Name    : uart_rx.vhd
-- Author       : Imran
-- Description  : Standard UART Receiver using external baud period.
--                Waits for the baud estimator to lock, then dynamically tracks
--                the baud period to securely receive payload data.
--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY uart_rx IS
    GENERIC (
        DATA_WIDTH : INTEGER := 8
    );
    PORT (
        clk         : IN STD_LOGIC;
        rst_n       : IN STD_LOGIC;
        uart_rx_bit : IN STD_LOGIC;
        baud_period : IN INTEGER;       -- Dynamic baud calculated from the estimator 
        baud_locked : IN STD_LOGIC;     -- Gates the receiver to ignore the sync byte - 0x55 or 0b01010101
        data        : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
        data_valid  : OUT STD_LOGIC;
        frame_err   : OUT STD_LOGIC
    );
END uart_rx;

ARCHITECTURE behavioural OF uart_rx IS 

    CONSTANT START_BIT : STD_LOGIC := '0';
    CONSTANT STOP_BIT  : STD_LOGIC := '1';

    TYPE state_type IS (WAIT_BUS_IDLE, IDLE, START_SYNC, READ_DATA, CHECK_STOP);

    SIGNAL state_s        : state_type := WAIT_BUS_IDLE;
    SIGNAL timer_s        : INTEGER := 0;
    SIGNAL bit_ix_s       : INTEGER RANGE 0 TO DATA_WIDTH - 1 := 0;
    SIGNAL data_reg_s     : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL frame_err_s    : STD_LOGIC := '0';
    SIGNAL data_valid_s   : STD_LOGIC := '0';
    
    SIGNAL rx_sync1_s     : STD_LOGIC := STOP_BIT;
    SIGNAL rx_sync2_s     : STD_LOGIC := STOP_BIT;
    SIGNAL rx_prev_s      : STD_LOGIC := STOP_BIT;

BEGIN 

    PROCESS (clk, rst_n)
        VARIABLE state_v      : state_type;
        VARIABLE timer_v      : INTEGER;
        VARIABLE bit_ix_v     : INTEGER RANGE 0 TO DATA_WIDTH - 1;
        VARIABLE data_reg_v   : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
        VARIABLE frame_err_v  : STD_LOGIC;
        VARIABLE data_valid_v : STD_LOGIC;
    BEGIN
        IF rst_n = '0' THEN 
            state_s       <= WAIT_BUS_IDLE;
            timer_s       <= 0;
            bit_ix_s      <= 0;
            data_reg_s    <= (OTHERS => '0');
            frame_err_s   <= '0';
            data_valid_s  <= '0';
            rx_sync1_s    <= STOP_BIT;
            rx_sync2_s    <= STOP_BIT;
            rx_prev_s     <= STOP_BIT;
            
        ELSIF rising_edge(clk) THEN 
            -- 2-FF synchroniser
            rx_sync1_s <= uart_rx_bit;
            rx_sync2_s <= rx_sync1_s;
            rx_prev_s  <= rx_sync2_s;

            state_v      := state_s;
            timer_v      := timer_s;
            bit_ix_v     := bit_ix_s;
            data_reg_v   := data_reg_s;
            frame_err_v  := '0';
            data_valid_v := '0'; 

            CASE state_v IS 
                WHEN WAIT_BUS_IDLE =>
                    -- Wait until estimator is locked AND the bus has returned to a HIGH state
                    IF baud_locked = '1' THEN
                        IF rx_sync2_s = STOP_BIT THEN
                            -- Wait for 2 full baud periods of continuous HIGH to ensure 
                            -- the sync byte 0x55 is completely finished so that we don't read a garbage payload
                            IF timer_v >= (baud_period * 2) THEN
                                timer_v := 0;
                                state_v := IDLE;
                            ELSE
                                timer_v := timer_v + 1;
                            END IF;
                        ELSE
                            timer_v := 0;
                        END IF;
                    ELSE
                        timer_v := 0;
                    END IF;

                WHEN IDLE =>
                    timer_v := 0;
                    
                    IF baud_locked = '0' THEN                                       -- Drop back to waiting if the estimator loses lock
                        state_v := WAIT_BUS_IDLE;
                    ELSIF rx_prev_s = STOP_BIT AND rx_sync2_s = START_BIT THEN      -- Leave IDLE only when there's a falling edge
                        state_v := START_SYNC;
                    END IF;

                WHEN START_SYNC =>
                    -- Wait to reach the centre of the start bit
                    IF timer_v >= (baud_period / 2) THEN 
                        timer_v := 0;
                        
                        -- Ensure that it's still low and not a glitch
                        IF rx_sync2_s = START_BIT THEN
                            bit_ix_v := 0;
                            state_v  := READ_DATA;
                        ELSE 
                            state_v  := IDLE;       -- Abort if it was a glitch
                        END IF;
                    ELSE 
                        timer_v := timer_v + 1;
                    END IF;

                WHEN READ_DATA => 
                    -- Sample the data starting from the middle of the first data bit
                    IF timer_v >= baud_period THEN 
                        timer_v := 0;
                        data_reg_v(bit_ix_v) := rx_sync2_s;

                        IF bit_ix_v = DATA_WIDTH - 1 THEN
                            state_v := CHECK_STOP;
                        ELSE
                            bit_ix_v := bit_ix_v + 1;
                        END IF;
                    ELSE 
                        timer_v := timer_v + 1;
                    END IF;

                WHEN CHECK_STOP =>
                    -- Wait a full baud period before moving to the centre point of the stop bit
                    IF timer_v >= baud_period THEN
                        IF rx_sync2_s = STOP_BIT THEN
                            frame_err_v  := '0';
                            data_valid_v := '1';
                        ELSE 
                            frame_err_v  := '1';
                        END IF;
                        state_v := IDLE;
                    ELSE 
                        timer_v := timer_v + 1;
                    END IF;
            END CASE;

            state_s      <= state_v;
            timer_s      <= timer_v;
            bit_ix_s     <= bit_ix_v;
            data_reg_s   <= data_reg_v;
            frame_err_s  <= frame_err_v;
            data_valid_s <= data_valid_v;
        END IF;
    END PROCESS;

    -- Output signal assignment
    data       <= data_reg_s;
    data_valid <= data_valid_s;
    frame_err  <= frame_err_s;
    
END behavioural;