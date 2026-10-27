# Shrike-TraceRunner: FPGA-Primary PID Line Follower on Vicharak Shrike-Fi

An FPGA-primary line-following robot built around the **Vicharak Shrike-Fi** (ESP32-S3 + Renesas ForgeFPGA SLG47910). Implements fixed-point PID control and dual-channel motor PWM in the ForgeFPGA, with the ESP32-S3 handling sensor acquisition, motor supervision, and a web-based dashboard for live PID tuning and telemetry.

The core design principle is true hardware/software co-design where the **FPGA is the primary real-time control engine**: line centroid decoding, discrete fixed-point PID arithmetic, anti-windup clamping, differential motor mixing, and ultrasonic ~19.53 kHz PWM signal generation all run directly in hardware RTL on the ForgeFPGA at 50 MHz (sub-microsecond calculation latency, zero jitter).

The ESP32-S3 handles 8-channel IR sensor sampling, supervisory safety gating, power-on FPGA bitstream bootstrap, Wi-Fi Soft-AP web server for live tuning/telemetry, and an interactive USB serial console.

---

## Architecture Overview

```
 [ 8-Channel Digital IR Sensor Bar ]
                  |
                  v (8 individual digital GPIO lines)
      +-----------------------+
      |    ESP32-S3 (MCU)     | --- Sensor sampling & normalization
      +-----------------------+
                  |
                  | 4-Byte Full-Duplex SPI (2.0 MHz, ~16 us transfer)
                  v
      +-----------------------+
      |  ForgeFPGA (SLG47910) | --- PRIMARY REAL-TIME CONTROL ENGINE
      |  - Centroid Decoder   |     (50 MHz clock, ~20 ns calc latency)
      |  - Fixed-Point PID    |
      |  - Anti-Windup Clamps |
      |  - Motor Mixer        |
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

## Hardware Pinout & Wiring

### 1. 8-Channel IR Sensors -> Shrike-Fi
Power the sensor array from the Shrike-Fi **3.3V** rail:
- `D0 (Far Right)` -> **GPIO 1**
- `D1 (Right Outer)` -> **GPIO 2**
- `D2 (Right Mid)` -> **GPIO 4**
- `D3 (Right Center)` -> **GPIO 5**
- `D4 (Left Center)` -> **GPIO 6**
- `D5 (Left Mid)` -> **GPIO 7**
- `D6 (Left Outer)` -> **GPIO 15**
- `D7 (Far Left)` -> **GPIO 16**

*(Note: Sensor module polarity defaults to active-low: black line = 0, white surface = 1. Can be toggled live via serial CLI or Web UI).*

### 2. PMOD Connector J5 (Verified SLG47910 Hardware Wiring)

| PMOD J5 Pin | FPGA Net | SLG47910 Pin | Destination / Function | Notes |
|:---:|:---:|:---:|:---|:---|
| **Pin 1, 2** | `+3.3V` | VDDIO Rail | 3.3V Logic Rail | Power |
| **Pin 3, 4** | `GND` | Ground Rail | Common Ground | Power |
| **Pin 5** | `F_GPIO9` | **Pin 24** | **L298N ENA (Left PWM)** | 19.53 kHz Hardware PWM |
| **Pin 6** | `F_GPIO8` | **Pin 23** | **L298N ENB (Right PWM)** | 19.53 kHz Hardware PWM |
| **Pin 7** | `F_GPIO11` | **Pin 2** | **L298N Motor Enable** | Hardware E-Stop Failsafe |
| **Pin 8** | `F_GPIO10` | **Pin 1** | Spare / Status | Telemetry |
| **Pins 9..12** | `F_GPIO13..14` | Pins 4, 3, 6, 5 | **Internal SPI Bus to ESP32** | **DO NOT WIRE** (Dedicated to MCU SPI) |

### 3. Motor Direction Controls (ESP32-S3 -> L298N)
- `IN1 (Left Dir A)` -> **ESP32 GPIO 17** (HIGH for forward)
- `IN2 (Left Dir B)` -> **ESP32 GPIO 18** (LOW for forward)
- `IN3 (Right Dir A)` -> **ESP32 GPIO 40** (HIGH for forward)
- `IN4 (Right Dir B)` -> **ESP32 GPIO 41** (LOW for forward)

### 4. Power Architecture
- **Battery**: 2S Li-ion 18650 cells (~7.4V nominal, up to 8.4V charged).
- **Shrike-Fi Power**: Step down 7.4V to **5.0V** using a DC-DC buck converter into Shrike-Fi 5V header pin.
- **Motor Power**: Feed 7.4V directly into L298N motor input (`VMS`). The L298N internal bipolar transistors drop ~1.8V ($V_{CE(sat)}$), delivering a safe ~5.6V to the 3-6V rated N20 motors.
- See [`docs/WIRING.md`](docs/WIRING.md) for full schematic.

---

## Quick Start: Build & Test

### 1. Run Automated Test Suite
Runs Python golden reference model tests, cycle-accurate PWM waveform generator, Verilator static timing/linting, Yosys netlist synthesis check, and toolchain checks:
```powershell
powershell -ExecutionPolicy Bypass -File .\workspace\fpga_pid_line_follower\scripts\test-all.ps1
```
*(All 5 test suites pass).*

### 2. Build FPGA RTL & MCU Firmware
Lints Verilog with Verilator, elaborates netlist with Yosys, and compiles the ESP32-S3 sketch with Arduino CLI:
```powershell
powershell -ExecutionPolicy Bypass -File .\workspace\fpga_pid_line_follower\scripts\build-all.ps1
```

### 3. Flash to Shrike-Fi over USB
```powershell
C:\Projects\Vicharak\tools\arduino-cli\arduino-cli.exe upload -p COM14 --fqbn esp32:esp32:esp32s3 C:\Projects\Vicharak\workspace\fpga_pid_line_follower\firmware\shrike_line_follower\shrike_line_follower.ino
```

---

## Serial Console & Live Tuning

Open a serial monitor at **115200 baud** over USB-C.

Interactive commands:
- `arm` : Arm motors and start line following
- `stop` : Disarm motors (failsafe stop)
- `speed <0-255>` : Change base forward speed (default: `110`)
- `kp <0-255>` : Update proportional gain (default: `32`)
- `ki <0-255>` : Update integral gain (default: `2`)
- `kd <0-255>` : Update derivative gain (default: `48`)
- `polarity <0|1>` : Switch sensor polarity (`0` = active-low, `1` = active-high)
- `csv` : Toggle 20 Hz CSV telemetry streaming (error, PWM left/right, status)
- `status` : Print diagnostic readout
- `reset` : Clear PID accumulator and state

---

## FPGA Design & Resource Footprint

The control RTL is split into modular Verilog blocks in `ffpga/src/`:
- `line_position_encoder.v`: Centroid lookup table mapping 8 sensor bits to signed line position error ($e \in [-7, +7]$) with last-known direction memory.
- `pid_controller.v`: Discrete fixed-point PID with configurable 8-bit gains, anti-windup clamping at $\pm 511$, backward-difference derivative, and arithmetic right shift by 4 (`SCALE_SHIFT = 4`).
- `motor_mixer.v`: Differential steering mixer ($PWM_L = \text{speed} + \text{steer}$, $PWM_R = \text{speed} - \text{steer}$). If the line is completely lost, automatically enters pivot recovery search at `SEARCH_SPEED` (60) in the last-known error direction.
- `pwm_generator.v`: 2-channel 19.53125 kHz ultrasonic PWM generator with clock prescaler, synchronous counter, and safety enable gating.
- `spi_target.v`: Synchronous SPI slave interface responding to 4-byte frames at 2.0 MHz.
- `pid_top.v`: Top-level integration module with status registers and heartbeat LED.

**Resource Utilization in Yosys & Vendor Mapping**:
- Generic Elaboration: 212 abstract AST cells.
- Vendor Technology Mapping (`synth_xilinx -nodsp` for EFLX-1K): **637 Logic Cells** out of 1,120 total capacity (**56.8% utilization**).
- Zero DSP blocks required (multipliers map to carry-chain logic).

---

## Project Structure

```
workspace/fpga_pid_line_follower/
├── README.md                                 # This file
├── docs/
│   ├── WIRING.md                             # Pin-to-pin wiring & schematic
│   ├── BUILD_AND_FLASH.md                    # Compilation & upload instructions
│   └── NOTES.md                              # Dev notes, SPI spec & power notes
├── ffpga/
│   ├── src/
│   │   ├── pid_top.v                         # Top-level FPGA module
│   │   ├── line_position_encoder.v           # 8-bit centroid decoder
│   │   ├── pid_controller.v                  # Fixed-point PID with anti-windup
│   │   ├── motor_mixer.v                     # Differential motor mixer
│   │   ├── pwm_generator.v                   # 19.53 kHz dual PWM generator
│   │   └── spi_target.v                      # SPI slave communication core
│   └── sim/
│       ├── tb_pid_top.v                      # Self-checking testbench
│       └── tb_pwm_generator.v                # PWM verification testbench
├── firmware/
│   └── shrike_line_follower/
│       ├── shrike_line_follower.ino          # Main 1 kHz control loop sketch
│       ├── config.h                          # Pin mappings & tuning defaults
│       ├── pid_bitstream.h                   # Synthesized FPGA bitstream header
│       ├── sensors.h / sensors.cpp           # IR sensor GPIO sampling
│       ├── motors.h / motors.cpp             # L298N LEDC 20 kHz PWM driver
│       ├── fpga_interface.h / .cpp           # SPI bootstrap & runtime communication
│       └── telemetry.h / telemetry.cpp       # Serial CLI & diagnostics
├── tests/
│   ├── reference_model.py                    # Bit-accurate Python reference model
│   ├── test_pid_golden.py                    # Golden unit test suite (5 tests)
│   └── test_pwm.py                           # PWM duty cycle & endpoint tests
└── scripts/
    ├── build-all.ps1                         # Builds RTL + compiles MCU firmware
    ├── test-all.ps1                          # Automated regression test suite
    └── generate_waveforms.py                 # Cycle-accurate ASCII & VCD waveform generator
```

---

## Practical Notes & Tips

1. **Physical Track Tuning**: Default gains ($K_p=32, K_i=2, K_d=48$, divided by 16 in hardware) were validated in Python and Verilog simulation. On an actual track with 19mm black electrical tape and varying floor reflectivity, use serial commands or the upcoming Web UI to fine-tune without re-flashing.
2. **ForgeFPGA Bitstream**: Verilog sources are synthesizable and pass Yosys elaboration and Verilator linting. To regenerate the C header after changing RTL, load `.v` files into Renesas Go Configure Hub (`GP6.exe`), assign pins in IO Planner, and export C array to `pid_bitstream.h`.
3. **Sensor Polarity**: If your 8-channel IR sensor outputs active-high (1 on black line), send `polarity 1` over serial.
4. **Emergency Stop**: If SPI communication drops for $> 30\,\text{ms}$, the MCU safety watchdog trips and forces both motor PWM channels to 0.
