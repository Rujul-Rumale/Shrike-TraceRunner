# Shrike-Fi PID Line Follower - Wiring Guide

Wiring connections between the Shrike-Fi board, 8-channel IR sensor bar, L298N driver, and battery pack.

---

## 1. Master Wiring Schematic

```
                                    +-----------------------+
                                    |  2S Li-ion Battery    |
                                    |  (7.4V - 8.4V Pack)   |
                                    +-----------+-----------+
                                                | (+)
                                          [Switch & Fuse]
                                                |
                       +------------------------+------------------------+
                       |                                                 |
                       v (+)                                             v
        +-----------------------------+                   +-----------------------------+
        | L298N Dual H-Bridge Driver  |                   | 5V DC-DC Buck Converter     |
        | 12V / Bat In: 7.4V - 8.4V   |                   | Vin: 7.4V - 8.4V            |
        | GND: Common Ground          |                   | Vout: 5.0V / 2A             |
        +--------------+--------------+                   +--------------+--------------+
                       |                                                 | (+) 5V
                       |                                                 v
                       |                                  +-----------------------------+
                       |                                  | Vicharak Shrike-Fi Board    |
                       |                                  | Header 5V: +5.0V Input      |
                       |                                  | Header GND: Common Ground   |
                       |                                  | Header 3V3: +3.3V Output    |
                       |                                  +--------------+--------------+
                       |                                                 | (+) 3.3V
                       |                                                 v
                       |                                  +-----------------------------+
                       |                                  | 8-Channel Digital IR Sensor |
                       |                                  | VCC: +3.3V (From Shrike-Fi) |
                       |                                  | GND: Common Ground          |
                       |                                  +-----------------------------+
                       |
                       +=======> MOTOR_L (N20) & MOTOR_R (N20)
```

---

## 2. Pin-to-Pin Interconnect Tables

### 2.1 8-Channel Digital IR Sensor to Shrike-Fi

| Sensor Board Pin | Shrike-Fi Header Pin | Function | Electrical Standard |
|:---:|:---:|:---|:---:|
| **VCC** | **3.3V** Rail | Sensor Power (Power from Shrike 3.3V!) | 3.3V DC |
| **GND** | **GND** Rail | Power & Signal Ground | 0V |
| **D0 (Far Right)** | **GPIO 1** | Digital Sensor Bit 0 | 3.3V LVCMOS |
| **D1 (Right Outer)** | **GPIO 2** | Digital Sensor Bit 1 | 3.3V LVCMOS |
| **D2 (Right Mid)** | **GPIO 4** | Digital Sensor Bit 2 | 3.3V LVCMOS |
| **D3 (Right Center)** | **GPIO 5** | Digital Sensor Bit 3 | 3.3V LVCMOS |
| **D4 (Left Center)** | **GPIO 6** | Digital Sensor Bit 4 | 3.3V LVCMOS |
| **D5 (Left Mid)** | **GPIO 7** | Digital Sensor Bit 5 | 3.3V LVCMOS |
| **D6 (Left Outer)** | **GPIO 15** | Digital Sensor Bit 6 | 3.3V LVCMOS |
| **D7 (Far Left)** | **GPIO 16** | Digital Sensor Bit 7 | 3.3V LVCMOS |

*(Alternative Direct FPGA Mode: If using the FPGA PMOD header, wire D0..D7 directly to PMOD Pins 1..4, 7..10).*

---

### 2.2 Motor Driver Interface (FPGA-Primary Co-Design)

The robot uses an **FPGA-primary control architecture**:
- Real-time ultrasonic motor PWM waveforms (~19.53 kHz) are generated directly in **hardware RTL on the ForgeFPGA** and routed out via PMOD connector **J5**.
- Motor direction signals (IN1..IN4) and system supervisor gating are controlled by the ESP32-S3.

#### PMOD Connector J5 Pin Mapping (SLG47910 Verified Wiring)

| PMOD J5 Pin | FPGA Net Name | SLG47910 Package Pin | Function / Destination | Notes |
|:---:|:---:|:---:|:---|:---|
| **Pin 1** | `+3.3V` | VDDIO Rail | Logic Power (3.3V) | Power Rail |
| **Pin 2** | `+3.3V` | VDDIO Rail | Logic Power (3.3V) | Power Rail |
| **Pin 3** | `GND` | Ground Rail | Common Signal Ground | Power Rail |
| **Pin 4** | `GND` | Ground Rail | Common Signal Ground | Power Rail |
| **Pin 5** | `F_GPIO9` | **Pin 24** | **`pwm_left_out` -> L298N ENA** | Left Motor Hardware PWM (19.53 kHz) |
| **Pin 6** | `F_GPIO8` | **Pin 23** | **`pwm_right_out` -> L298N ENB** | Right Motor Hardware PWM (19.53 kHz) |
| **Pin 7** | `F_GPIO11` | **Pin 2** | **`motor_en_out`** | Hardware Safety E-Stop (Active-High) |
| **Pin 8** | `F_GPIO10` | **Pin 1** | `spare_gpio` | Spare / Status telemetry indicator |
| **Pin 9** | `F_GPIO13` | **Pin 4** | *ESP32 SPI_SS (GPIO 10)* | **DO NOT WIRE (Internal SPI Bus)** |
| **Pin 10** | `F_GPIO12` | **Pin 3** | *ESP32 SPI_SCLK (GPIO 12)* | **DO NOT WIRE (Internal SPI Bus)** |
| **Pin 11** | `F_GPIO15` | **Pin 6** | *ESP32 SPI_MISO (GPIO 13)* | **DO NOT WIRE (Internal SPI Bus)** |
| **Pin 12** | `F_GPIO14` | **Pin 5** | *ESP32 SPI_MOSI (GPIO 11)* | **DO NOT WIRE (Internal SPI Bus)** |

> [!WARNING]
> PMOD pins 9 through 12 are hardwired on the PCB to the ESP32-to-FPGA SPI communication bus. Never attach external sensors or motor leads to PMOD pins 9..12!

#### L298N Terminal Connections

| L298N Terminal | Source Pin | Function | Notes |
|:---:|:---:|:---|:---|
| **VCC (+12V)** | Battery Positive (+) via Switch | Motor Power (7.4V – 8.4V) | Connect through 3A Fuse |
| **GND** | Common Ground | Ground Reference | Must be tied to Shrike-Fi GND |
| **5V Terminal** | NC (Not Connected) | L298N internal logic | Remove jumper if 5V fed externally |
| **ENA** | **PMOD J5 Pin 5** (FPGA Pin 24) | Left Motor PWM Speed | Hardware PWM directly from FPGA |
| **IN1** | **ESP32 GPIO 17** | Left Motor Direction A | Digital Output (High for Fwd) |
| **IN2** | **ESP32 GPIO 18** | Left Motor Direction B | Digital Output (Low for Fwd) |
| **IN3** | **ESP32 GPIO 40** | Right Motor Direction A | Digital Output (High for Fwd) |
| **IN4** | **ESP32 GPIO 41** | Right Motor Direction B | Digital Output (Low for Fwd) |
| **ENB** | **PMOD J5 Pin 6** (FPGA Pin 23) | Right Motor PWM Speed | Hardware PWM directly from FPGA |


---

### 2.3 L298N to N20 Motors

| L298N Output | Motor Terminal | Rotation Direction | Notes |
|:---:|:---:|:---|:---|
| **OUT1** | Left Motor (+) | Forward when IN1=H, IN2=L | If motor spins backward, swap OUT1 & OUT2 |
| **OUT2** | Left Motor (-) | | |
| **OUT3** | Right Motor (+) | Forward when IN3=H, IN4=L | If motor spins backward, swap OUT3 & OUT4 |
| **OUT4** | Right Motor (-) | | |

---

## 3. Grounding & Noise Suppression

1. **Star Ground Topology:**
   - Tie the battery negative lead directly to the L298N ground terminal.
   - Run a thick wire from L298N ground to Shrike-Fi ground.
   - Run a wire from Shrike-Fi ground to the IR sensor ground.
   - This prevents high motor ripple currents from causing ground bounces on the sensitive 3.3V logic rails.
2. **Motor Decoupling Capacitors:**
   - Solder a $100\,\text{nF}$ ceramic capacitor directly across the two terminals of each N20 motor to suppress brush arc RF noise.
