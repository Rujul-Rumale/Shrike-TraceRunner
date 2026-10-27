# Shrike-TraceRunner: FPGA-Primary PID Line Follower on Vicharak Shrike-Fi

An FPGA-primary line-following robot built around the **Vicharak Shrike-Fi** (ESP32-S3 + Renesas ForgeFPGA SLG47910).

The core design principle is true hardware/software co-design where the **FPGA is the primary real-time control engine**: line centroid decoding, discrete fixed-point PID arithmetic, anti-windup clamping, differential motor mixing, safety watchdog timeout gating, and ultrasonic ~19.53 kHz PWM signal generation all run directly in hardware RTL on the ForgeFPGA at 50 MHz.

The ESP32-S3 provides 8-channel IR sensor sampling, supervisory safety gating, power-on FPGA bitstream bootstrap, a Wi-Fi Soft-AP web server for live tuning/telemetry, and an interactive USB serial console.

---

## 1. System Architecture

```text
 [ 8-Channel Digital IR Sensor Bar ]
                  |
                  v (8 independent digital GPIO lines)
      +-----------------------+
      |    ESP32-S3 (MCU)     | --- Sensor sampling & normalization
      +-----------------------+
                  |
                  | 4-Byte Full-Duplex SPI (2.0 MHz, ~16 us transfer)
                  v
      +-----------------------+
      |  ForgeFPGA (SLG47910) | --- PRIMARY REAL-TIME CONTROL ENGINE
      |  - Centroid Decoder   |     (50 MHz clock, deterministic execution)
      |  - Fixed-Point PID    |
      |  - Anti-Windup Clamps |
      |  - Motor Mixer        |
      |  - Hardware Watchdog  | --- 50 ms SPI loss auto-shutdown
      |  - Dual Hardware PWM  | --- 19.53125 kHz Ultrasonic Motor Drive
      +-----------------------+
                  |
                  v (Direct Hardware PWM from PMOD J5 Pins 5, 6, 7)
      [ L298N Dual H-Bridge Motor Driver ]
                  |
                  v
      [ Dual N20 Geared DC Motors (3-6V) ]
```

---

## 2. Hardware Pinout & Wiring Specifications

### 2.1 8-Channel IR Sensors $\rightarrow$ Shrike-Fi
Power the sensor array strictly from the Shrike-Fi **3.3V** rail:
- `D0 (Far Right)` $\rightarrow$ **GPIO 1**
- `D1 (Right Outer)` $\rightarrow$ **GPIO 2**
- `D2 (Right Mid)` $\rightarrow$ **GPIO 4**
- `D3 (Right Center)` $\rightarrow$ **GPIO 5**
- `D4 (Left Center)` $\rightarrow$ **GPIO 6**
- `D5 (Left Mid)` $\rightarrow$ **GPIO 7**
- `D6 (Left Outer)` $\rightarrow$ **GPIO 15**
- `D7 (Far Left)` $\rightarrow$ **GPIO 16**

### 2.2 PMOD Connector J5 (Verified SLG47910 Hardware Wiring)

Verified against the official Shrike-Fi KiCad schematic (`FPGA.kicad_sch`):

| PMOD J5 Pin | FPGA Net | SLG47910 Pin | Destination / Function | Notes |
|:---:|:---:|:---:|:---|:---|
| **Pin 1, 2** | `+3.3V` | VDDIO Rail | 3.3V Logic Rail | Power |
| **Pin 3, 4** | `GND` | Ground Rail | Common Signal Ground | Power |
| **Pin 5** | `F_GPIO9` | **Pin 24** | **L298N ENA (Left PWM)** | 19.53 kHz Hardware PWM (3.3V LVCMOS) |
| **Pin 6** | `F_GPIO8` | **Pin 23** | **L298N ENB (Right PWM)** | 19.53 kHz Hardware PWM (3.3V LVCMOS) |
| **Pin 7** | `F_GPIO11` | **Pin 2** | **L298N Motor Enable** | Hardware Failsafe E-Stop |
| **Pin 8** | `F_GPIO10` | **Pin 1** | Spare / Status Indicator | 3.3V LVCMOS |
| **Pins 9..12** | `F_GPIO13..14` | Pins 4, 3, 6, 5 | **Internal SPI Bus to ESP32** | **DO NOT WIRE** (Dedicated PCB SPI Bus) |

> [!WARNING]
> PMOD pins 9 through 12 are hardwired on the PCB to the ESP32-to-FPGA SPI communication bus. Do not attach motor driver lines or external sensor wires to PMOD pins 9..12!

### 2.3 Motor Direction Controls (ESP32-S3 $\rightarrow$ L298N)
- `IN1 (Left Phase A)` $\rightarrow$ **ESP32 GPIO 17** (HIGH for forward)
- `IN2 (Left Phase B)` $\rightarrow$ **ESP32 GPIO 18** (LOW for forward)
- `IN3 (Right Phase A)` $\rightarrow$ **ESP32 GPIO 40** (HIGH for forward)
- `IN4 (Right Phase B)` $\rightarrow$ **ESP32 GPIO 41** (LOW for forward)

### 2.4 Power Architecture & Electrical Safety
- **Battery Protection**: 2S Li-ion pack (7.4V nominal, 6.0V–8.4V operating range) MUST use a 2S BMS protection board with over-discharge cut-off ($\le 3.0\text{V/cell}$ / 6.0V total), overcharge protection, and short-circuit protection.
- **Over-Current Protection**: A master switch and a **3A fast-acting fuse** on the battery positive lead.
- **Regulated Motor Supply**:
  - **Do NOT feed raw battery voltage into the L298N or rely on internal transistor saturation drops as a regulator.**
  - A dedicated DC-DC step-down buck converter adjusted to **5.0V or 6.0V DC** (rated $\ge 2.5\text{A}$) supplies the L298N motor input (`VMS`), keeping motor voltages strictly within the 3V–6V rating of the N20 motors.
- **Regulated Logic Supply**: A separate 5.0V DC-DC buck converter (rated $\ge 2.0\text{A}$) supplies the Shrike-Fi 5V input header.
- **Driver Pull-Downs**: External $10\,\text{k}\Omega$ pull-down resistors to GND on L298N `ENA` and `ENB` ensure motors remain safely disabled when FPGA I/O pins are floating or high-impedance.
- **Common Ground**: Common star ground connecting Battery (-), Buck GNDs, Shrike-Fi GND, L298N GND, and Sensor GND.
- See [`docs/WIRING.md`](docs/WIRING.md) for full schematics and details.

---

## 3. Quick Start: Build & Verification

### 3.1 Run Automated Regression Test Suite
Runs Python golden reference model tests, cycle-accurate PWM waveform generator, Verilator static timing/linting, Yosys netlist elaboration check, and toolchain checks:
```powershell
powershell -ExecutionPolicy Bypass -File .\workspace\fpga_pid_line_follower\scripts\test-all.ps1
```

### 3.2 Build FPGA RTL & MCU Firmware
Lints Verilog with Verilator, elaborates netlist with Yosys, and compiles the ESP32-S3 sketch with Arduino CLI:
```powershell
powershell -ExecutionPolicy Bypass -File .\workspace\fpga_pid_line_follower\scripts\build-all.ps1
```

---

## 4. FPGA RTL Implementation & Synthesis Status

The control RTL is split into modular Verilog blocks in `ffpga/src/`:
- `line_position_encoder.v`: Centroid lookup table mapping 8 sensor bits to signed line position error ($e \in [-7, +7]$) with last-known direction memory.
- `pid_controller.v`: Discrete fixed-point PID with configurable 8-bit gains, anti-windup clamping at $\pm 511$, backward-difference derivative, and arithmetic right shift by 4 (`SCALE_SHIFT = 4`).
- `motor_mixer.v`: Differential steering mixer ($PWM_L = \text{speed} - \text{steer}$, $PWM_R = \text{speed} + \text{steer}$). If the line is lost, executes pivot recovery search toward `last_dir` only when `base_speed > 0`. If `base_speed == 0`, motor outputs are strictly forced to 0.
- `pwm_generator.v`: 2-channel 19.53125 kHz ultrasonic PWM generator with clock prescaler, synchronous counter, and safety enable gating.
- `spi_target.v`: Synchronous SPI slave interface responding to 4-byte frames at 2.0 MHz with CDC synchronizers.
- `pid_top.v`: Top-level integration module with status registers, heartbeat LED, power-on reset, and a 50 ms SPI timeout safety watchdog.

### Verification & Synthesis Audit:
- **Generic Yosys Netlist Elaboration**: **PASSED (244 generic AST cells)**. Passes hierarchy check, process conversion, optimization, and rule checking without undriven signals or latches.
- **Verilator Static Lint**: **PASSED (0 errors, 0 warnings)** with IEEE 1800-2023 timing enabled.
- **ForgeFPGA Vendor Placement & Routing**: **UNVERIFIED IN HARDWARE**. The Renesas ForgeFPGA SLG47910 EFLX-1K architecture requires synthesis and placement through the official Renesas Go Configure Software Hub GUI (`GP6.exe`). Generic Yosys cells or third-party targets (such as Xilinx) do not establish ForgeFPGA vendor resource utilization.
- **Physical Robot Track Testing**: **NOT PERFORMED**. Verification has been conducted in bit-accurate Python models, cycle-accurate timing simulations, and static linting. Physical robot track testing is pending bench commissioning.

---

## 5. Project Structure

```text
workspace/fpga_pid_line_follower/
├── README.md                                 # Master architecture & audit guide
├── docs/
│   ├── WIRING.md                             # Electrical schematics, pinout & safety checklist
│   ├── BUILD_AND_FLASH.md                    # Compilation & upload instructions
│   └── NOTES.md                              # Technical audit, SPI spec & verification status
├── ffpga/
│   ├── src/
│   │   ├── pid_top.v                         # Top-level FPGA module with watchdog & failsafe
│   │   ├── line_position_encoder.v           # 8-bit centroid decoder
│   │   ├── pid_controller.v                  # Fixed-point PID with anti-windup
│   │   ├── motor_mixer.v                     # Differential motor mixer with zero-speed safety
│   │   ├── pwm_generator.v                   # 19.53 kHz dual PWM generator
│   │   └── spi_target.v                      # SPI slave communication core
│   └── sim/
│       ├── tb_pid_top.v                      # Self-checking testbench
│       └── tb_pwm_generator.v                # PWM verification testbench
├── firmware/
│   └── shrike_line_follower/
│       ├── shrike_line_follower.ino          # Main 1 kHz control loop sketch
│       ├── config.h                          # Pin mappings & safety parameters
│       ├── pid_bitstream.h                   # Synthesized FPGA bitstream header
│       ├── sensors.h / sensors.cpp           # IR sensor GPIO sampling
│       ├── motors.h / motors.cpp             # L298N direction & PWM interface
│       ├── fpga_interface.h / .cpp           # SPI bootstrap & runtime communication
│       └── telemetry.h / telemetry.cpp       # Serial CLI & diagnostics
├── tests/
│   ├── reference_model.py                    # Bit-accurate Python reference model
│   ├── test_pid_golden.py                    # Golden unit test suite (5 tests)
│   └── test_pwm.py                           # PWM duty cycle & safety interlock tests
└── scripts/
    ├── build-all.ps1                         # Builds RTL + compiles MCU firmware
    ├── test-all.ps1                          # Automated regression test suite
    └── generate_waveforms.py                 # Cycle-accurate ASCII & VCD waveform generator
```
