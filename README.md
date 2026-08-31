# Space MRI - UART

## 1. SYSTEM DESCRIPTION
The Space_MRI_UART repository contains the VHDL hardware design files for a high-reliability serial communication interface. This system is designed for the Space MRI project. The architecture includes an automatic baud rate estimator, a dynamic receiver, and a static transmitter. The system uses an 8N2 configuration to guarantee data frame separation and prevent data collisions during continuous transmission.

## 2. COMPONENT OVERVIEW

*   **autobaud_estimator.vhd**
    This module measures the initial synchronisation byte to calculate the operational baud period. It monitors the serial input for the shortest logic-low pulse. It includes fault-recovery logic to drop the lock and reset the system if a timeout occurs or if the receiver detects a framing error.

*   **uart_rx.vhd**
    This is the main receiver module. It uses the dynamic baud period calculated by the estimator. It implements a bus-idle gatekeeper that waits for 1.5 baud periods of continuous logic-high to confirm the end of the synchronisation byte. The receiver operates in an 8N2-compatible mode.

*   **uart_rx_top.vhd**
    This is the top-level structural wrapper for the receiver subsystem. It connects the automatic baud rate estimator to the main receiver module. It establishes the internal feedback loop required for the self-healing error recovery sequence.

*   **uart_tx.vhd**
    This is the main transmitter module. It operates at a fixed baud rate defined by generic parameters. It transmits data using a strict 8N2 protocol (1 start bit, 8 data bits, 2 stop bits). 

*   **uart_loopback_top.vhd**
    This is a top-level structural module used for hardware verification. It connects the receiver output data bus directly to the transmitter input data bus. This creates a continuous echo loop back to the primary command computer.

## 3. TECHNICAL SPECIFICATIONS

| Parameter | Specification |
| :--- | :--- |
| **Target Hardware** | Digilent Basys 3 |
| **FPGA Part Number** | xc7a35tcpg236-1 |
| **System Clock Frequency** | 100 MHz |
| **Data Protocol** | 8N2 (8 Data Bits, No Parity, 2 Stop Bits) |
| **Synchronisation Byte** | `0x55` or `0b01010101` (ASCII 'U') |
| **Hardware Reset** | Active-low (Mapped to Slide Switch) |

## 4. DIRECTORY STRUCTURE

The repository is organised into three distinct directories to separate synthesiseable logic, simulation environments, and physical hardware constraints.

```text
Space_MRI_UART/
├── hdl/                  
│   ├── autobaud_estimator.vhd
│   ├── uart_rx.vhd
│   ├── uart_rx_top.vhd
│   ├── uart_tx.vhd
│   └── uart_loopback_top.vhd
├── sim/                  
│   └── tb_uart_rx_top.vhd
└── xdc/                  
    └── basys3_loopback.xdc
```

## 5. FAULT RECOVERY

The system contains two self-healing mechanisms to ensure continuous operation in adverse conditions.

*   **Link Disconnect (Timeout):** If the physical receiver line remains at a logic-low state for a maximum threshold limit, the estimator declares a break condition. It resets the saved baud period and prepares for a new synchronization byte.
*   **Framing Error:** If the receiver fails to detect a valid stop bit at the expected time interval, it asserts a framing error signal. This signal commands the estimator to immediately drop the baud lock and halt data reception until recalibration occurs.
