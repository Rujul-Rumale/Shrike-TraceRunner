# Shrike-TraceRunner - Electrical & Wiring Guide

Wiring specifications, safety interlocks, pin mappings, and electrical standards for the Vicharak Shrike-Fi line-following robot.

---

## 1. Electrical Architecture & Safety Rules

> [!CAUTION]
> **CRITICAL ELECTRICAL SAFETY RULES:**
> 1. **Do not use the L298N internal voltage drop ($V_{CE(sat)}$) as a regulator.** N20 geared DC motors are rated for **3.0V – 6.0V**. A freshly charged 2S Li-ion battery delivers **8.4V**. At light motor load or low current, the voltage drop across the H-bridge is minimal, exposing the motor coils and brushes to excessive over-voltage. **Always use a dedicated, regulated 5.0V or 6.0V DC-DC step-down buck converter for motor power.**
> 2. **Battery Protection is Mandatory.** Loose 18650 cells must be connected through a dedicated **2S BMS (Battery Management System)** board providing:
>    - Over-discharge cutoff ($\le 3.0\,\text{V}$ per cell / $6.0\,\text{V}$ total pack).
>    - Over-charge cutoff ($\ge 4.25\,\text{V}$ per cell / $8.5\,\text{V}$ pack).
>    - Short-circuit and over-current trip.
> 3. **Physical Protection:** Install a **3A fast-acting fuse** and a master power switch on the positive lead directly after the BMS before distributing power.
> 4. **Driver Enable Pull-Downs:** Install external **$10\,\text{k}\Omega$ pull-down resistors** from L298N `ENA` and `ENB` to GND. During power-up, MCU reset, or FPGA bitstream loading, FPGA I/O pins are high-impedance. Pull-downs ensure the motor driver remains safely disabled (0V).

---

## 2. Power Distribution Topology

```
                  +------------------------------------------------+
                  |  2S Li-ion Battery (7.4V Nom, 6.0V - 8.4V)      |
                  |  with Integrated 2S BMS (Over-discharge Cutoff)|
                  +-----------------------+------------------------+
                                          | (+) Pack Positive
                                   [Master Switch]
                                          |
                                   [ 3A Fast Fuse ]
                                          |
                 +------------------------+------------------------+
                 | (+) Raw Bat (6-8.4V)                            | (+) Raw Bat (6-8.4V)
                 v                                                 v
  +------------------------------+                  +------------------------------+
  | Motor Buck Converter         |                  | System Logic Buck Converter  |
  | Vin: 6.0V - 8.4V             |                  | Vin: 6.0V - 8.4V             |
  | Vout: Regulated 5.0V or 6.0V |                  | Vout: Regulated 5.0V DC      |
  | Rating: >= 2.5A Peak         |                  | Rating: >= 2.0A Continuous   |
  +--------------+---------------+                  +--------------+---------------+
                 | (+) Regulated 5V/6V                             | (+) Regulated 5.0V
                 v                                                 v
  +------------------------------+                  +------------------------------+
  | L298N Dual H-Bridge Driver   |                  | Vicharak Shrike-Fi Board     |
  | - VCC (Motor In): 5.0V / 6.0V|                  | - Header 5V: +5.0V Logic In  |
  | - 5V Logic In: +5.0V (Reg)   | <---+ 5.0V Logic | - Header GND: Star Ground    |
  | - GND: Common Star Ground    |     |            | - Header 3V3: +3.3V Out      |
  +--------------+---------------+     |            +--------------+---------------+
                 |                     |                           | (+) 3.3V
                 |                     +---------------------------+ (Power for 5V pin
                 |                                                 |  & Sensor Array)
                 |                                                 v
                 |                                  +------------------------------+
                 |                                  | 8-Channel Digital IR Sensor  |
                 |                                  | - VCC: +3.3V (from Shrike)   |
                 |                                  | - GND: Common Star Ground    |
                 |                                  +------------------------------+
                 v
   Dual N20 Geared Motors (3-6V)
   with 100nF Ceramic Snubber Caps
```

*Note on L298N 5V Jumper:* Remove the onboard 12V-to-5V regulator jumper on the L298N module. Connect the L298N 5V logic terminal directly to the regulated 5.0V system logic rail.

---

## 3. Pin Interconnect & Interface Feasibility Tables

### 3.1 8-Channel Digital IR Sensor Array to Shrike-Fi (ESP32-S3)

The 8 sensor signals are connected directly to the ESP32-S3 GPIO headers. Power is sourced strictly from the Shrike-Fi **3.3V** rail:

| Sensor Module Pin | Shrike-Fi Header Pin | Function | Electrical Standard |
|:---:|:---:|:---|:---:|
| **VCC** | **3.3V** Rail | Sensor Array Power ($\le 150\,\text{mA}$) | 3.3V DC |
| **GND** | **GND** Rail | Common Signal Ground | 0V |
| **D0 (Far Right)** | **GPIO 1** | Digital Sensor Bit 0 | 3.3V LVCMOS |
| **D1 (Right Outer)** | **GPIO 2** | Digital Sensor Bit 1 | 3.3V LVCMOS |
| **D2 (Right Mid)** | **GPIO 4** | Digital Sensor Bit 2 | 3.3V LVCMOS |
| **D3 (Right Center)** | **GPIO 5** | Digital Sensor Bit 3 | 3.3V LVCMOS |
| **D4 (Left Center)** | **GPIO 6** | Digital Sensor Bit 4 | 3.3V LVCMOS |
| **D5 (Left Mid)** | **GPIO 7** | Digital Sensor Bit 5 | 3.3V LVCMOS |
| **D6 (Left Outer)** | **GPIO 15** | Digital Sensor Bit 6 | 3.3V LVCMOS |
| **D7 (Far Left)** | **GPIO 16** | Digital Sensor Bit 7 | 3.3V LVCMOS |

*Why Sensors Connect to ESP32 instead of FPGA:* The ForgeFPGA PMOD connector (J5) only exposes 4 usable GPIOs (pins 9..12 are tied to internal SPI). The 8 sensor lines physically require the ESP32 GPIO header. The ESP32 aggregates the sensor byte and streams it to the FPGA over SPI at 1 kHz.

---

### 3.2 ForgeFPGA PMOD Connector J5 (Verified Hardware Netlist)

Derived directly from the official Shrike-Fi KiCad schematic (`FPGA.kicad_sch`):

| PMOD J5 Pin | Schematic Net | SLG47910 Pin | Function / Destination | Notes |
|:---:|:---:|:---:|:---|:---|
| **Pin 1** | `+3.3V` | VDDIO Rail | 3.3V Logic Rail | Power Rail |
| **Pin 2** | `+3.3V` | VDDIO Rail | 3.3V Logic Rail | Power Rail |
| **Pin 3** | `GND` | Ground Rail | Common Signal Ground | Power Rail |
| **Pin 4** | `GND` | Ground Rail | Common Signal Ground | Power Rail |
| **Pin 5** | `F_GPIO9` | **Pin 24** | **`pwm_left_out` $\rightarrow$ L298N ENA** | Hardware PWM (19.53 kHz, 3.3V LVCMOS) |
| **Pin 6** | `F_GPIO8` | **Pin 23** | **`pwm_right_out` $\rightarrow$ L298N ENB** | Hardware PWM (19.53 kHz, 3.3V LVCMOS) |
| **Pin 7** | `F_GPIO11` | **Pin 2** | **`motor_en_out` $\rightarrow$ Failsafe E-Stop** | Hardware Enable (LOW = Safe Disable) |
| **Pin 8** | `F_GPIO10` | **Pin 1** | Spare / Status Indicator | 3.3V LVCMOS |
| **Pin 9** | `F_GPIO13` | **Pin 4** | *ESP32 SPI_SS (GPIO 10)* | **DO NOT WIRE** (Internal PCB SPI Bus) |
| **Pin 10** | `F_GPIO12` | **Pin 3** | *ESP32 SPI_SCLK (GPIO 12)* | **DO NOT WIRE** (Internal PCB SPI Bus) |
| **Pin 11** | `F_GPIO15` | **Pin 6** | *ESP32 SPI_MISO (GPIO 13)* | **DO NOT WIRE** (Internal PCB SPI Bus) |
| **Pin 12** | `F_GPIO14` | **Pin 5** | *ESP32 SPI_MOSI (GPIO 11)* | **DO NOT WIRE** (Internal PCB SPI Bus) |

> [!WARNING]
> PMOD pins 9 through 12 are hardwired on the PCB to the ESP32-to-FPGA SPI communication bus. Do not connect motor driver leads or external wires to PMOD pins 9..12!

---

### 3.3 Motor Direction Controls (ESP32-S3 $\rightarrow$ L298N)

Motor direction and braking states are controlled by the ESP32-S3:

| L298N Input | ESP32-S3 Pin | Forward State | Coast / Stop State | Reverse State |
|:---:|:---:|:---:|:---:|:---:|
| **IN1** (Left Phase A) | **GPIO 17** | **HIGH** (3.3V) | **LOW** (0V) | **LOW** (0V) |
| **IN2** (Left Phase B) | **GPIO 18** | **LOW** (0V) | **LOW** (0V) | **HIGH** (3.3V) |
| **IN3** (Right Phase A) | **GPIO 40** | **HIGH** (3.3V) | **LOW** (0V) | **LOW** (0V) |
| **IN4** (Right Phase B) | **GPIO 41** | **LOW** (0V) | **LOW** (0V) | **HIGH** (3.3V) |

*Logic Compatibility:* L298N input high threshold is $V_{IH,min} \approx 2.3\,\text{V}$. The 3.3V LVCMOS output from the ESP32-S3 drives the inputs with $\ge 1.0\,\text{V}$ noise margin.

---

### 3.4 Motor Terminal Wiring (L298N $\rightarrow$ N20 Motors)

| L298N Output | Motor Terminal | Forward Polarity | Reverse Polarity |
|:---:|:---:|:---:|:---:|
| **OUT1** | Left Motor (+) | $V_{motor}$ | GND |
| **OUT2** | Left Motor (-) | GND | $V_{motor}$ |
| **OUT3** | Right Motor (+) | $V_{motor}$ | GND |
| **OUT4** | Right Motor (-) | GND | $V_{motor}$ |

*Snubber Capacitors:* Solder a $100\,\text{nF}$ ceramic capacitor directly across the terminals of each N20 motor to suppress inductive commutator noise and prevent EMI resets.

---

## 4. Pre-Power Connection Checklist

Before connecting the battery or motors:
- [ ] Verify battery polarity: Positive to fuse/switch, negative to common ground.
- [ ] Measure buck converter outputs with a multimeter: Ensure logic rail is strictly **$5.0\,\text{V} \pm 0.1\,\text{V}$** and motor rail is strictly **$5.0\,\text{V}$ or $6.0\,\text{V}$**.
- [ ] Verify $10\,\text{k}\Omega$ pull-down resistors are installed on L298N `ENA` and `ENB`.
- [ ] Ensure PMOD pins 9..12 have NO external wiring connected.
- [ ] Verify star ground continuity: $0\,\Omega$ resistance between Battery (-), L298N GND, and Shrike-Fi GND.
