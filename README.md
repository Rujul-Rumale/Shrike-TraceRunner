# Shrike-TraceRunner: FPGA-Primary PID Line Follower on Vicharak Shrike-Fi

An FPGA-accelerated autonomous line-following robot built around the **Vicharak Shrike-Fi** board (Espressif ESP32-S3 MCU + Renesas ForgeFPGA SLG47910).

The core design principle is hardware-accelerated deterministic control: line centroid decoding, discrete fixed-point PID arithmetic, anti-windup clamping, differential motor mixing, a 50 ms SPI watchdog timeout, and 50 Hz continuous rotation RC servo pulse generation all run directly in hardware RTL on the ForgeFPGA at 50 MHz.

The ESP32-S3 handles 8-channel IR sensor sampling, initial FPGA bitstream bootstrap over SPI on power-up, and an interactive USB serial console for runtime telemetry and gain tuning.

---

## 1. System Architecture

```text
 [ 8-Channel Digital IR Sensor Bar ]
                  |
                  v (8 independent digital GPIO lines)
      +-----------------------+
      |    ESP32-S3 (MCU)     | --- Sensor sampling & SPI master
      +-----------------------+
                  |
                  | 4-Byte Full-Duplex SPI (2.0 MHz, 1 kHz loop)
                  v
      +-----------------------+
      |  ForgeFPGA (SLG47910) | --- PRIMARY REAL-TIME CONTROL ENGINE
      |  - Centroid Decoder   |     (50 MHz clock, deterministic execution)
      |  - 2-Stage Pipeline   |
      |  - Fixed-Point PID    |
      |  - Anti-Windup Clamps |
      |  - Motor Mixer        |
      |  - 50ms SPI Watchdog  | --- Auto-failsafe if communication drops
      |  - 50 Hz Servo Engine | --- 1000us - 2000us RC servo pulses (1500us neutral)
      +-----------------------+
                  |
                  v (Direct 50 Hz RC pulses from PMOD J5 Pins 5 & 6)
       [ Dual 360° Continuous Rotation 9g Servos ]
          (FS90R / SG90-360 directly on chassis)
```

> **Why FPGA + MCU?**  
> Running the PID loop and pulse generation in FPGA hardware eliminates interrupt latency, RTOS context-switch jitter, and timer drift. The ESP32 is free to handle Wi-Fi, sensor filtering, and interactive serial communication without impacting motor timing.

---

## 2. Hardware Pinout & Wiring

### 2.1 8-Channel IR Sensors $\rightarrow$ ESP32-S3
The sensor bar connects to the ESP32 GPIO headers. Power the module strictly from the Shrike-Fi **3.3V** rail:
- `D0 (Far Right)` $\rightarrow$ **GPIO 1**
- `D1 (Right Outer)` $\rightarrow$ **GPIO 2**
- `D2 (Right Mid)` $\rightarrow$ **GPIO 4**
- `D3 (Right Center)` $\rightarrow$ **GPIO 5**
- `D4 (Left Center)` $\rightarrow$ **GPIO 6**
- `D5 (Left Mid)` $\rightarrow$ **GPIO 7**
- `D6 (Left Outer)` $\rightarrow$ **GPIO 15**
- `D7 (Far Left)` $\rightarrow$ **GPIO 16**

### 2.2 Dual 360° Continuous Rotation Servos $\rightarrow$ PMOD J5
The servos receive standard 50 Hz PWM control pulses directly from the ForgeFPGA on PMOD J5:

| Servo Lead | Destination | Net / Pin | Function |
| :--- | :--- | :---: | :--- |
| **Left Signal** (White / Orange) | PMOD J5 Pin 5 | `F_GPIO9` (FPGA Pin 24) | `pwm_left_out` (50 Hz RC pulse) |
| **Right Signal** (White / Orange) | PMOD J5 Pin 6 | `F_GPIO8` (FPGA Pin 23) | `pwm_right_out` (50 Hz RC pulse, mirrored) |
| **Servo Power** (Red) | Power Distribution | **+5.0V** Regulated Rail | Dedicated 5V buck converter |
| **Servo Ground** (Black / Brown) | Ground Rail | Common Star Ground | Must share GND with Shrike-Fi |

> [!CAUTION]
> **Never power servos from the 3.3V rail or directly from FPGA pins.** Servos draw 150–400 mA under load and will brown out the board or damage the I/O pins. Always power servo VCC from a dedicated 5.0V buck converter sharing a common ground with the Shrike-Fi.

### 2.3 ForgeFPGA PMOD Connector J5 Reference
Verified against the Shrike-Fi schematic (`FPGA.kicad_sch`):

| PMOD J5 Pin | FPGA Net | SLG47910 Pin | Function / Usage | Notes |
| :---: | :---: | :---: | :--- | :--- |
| **Pin 1, 2** | `+3.3V` | VDDIO Rail | 3.3V Logic Rail | Power rail |
| **Pin 3, 4** | `GND` | Ground Rail | Common Signal Ground | Power ground |
| **Pin 5** | `F_GPIO9` | **Pin 24** | **`pwm_left_out`** | 50 Hz RC servo pulse (Left) |
| **Pin 6** | `F_GPIO8` | **Pin 23** | **`pwm_right_out`** | 50 Hz RC servo pulse (Right) |
| **Pin 7** | `F_GPIO11` | **Pin 2** | `motor_en_out` | Hardware enable / failsafe |
| **Pin 8** | `F_GPIO10` | **Pin 1** | Spare / Status Indicator | 3.3V LVCMOS |
| **Pins 9..12** | `F_GPIO13..14` | Pins 4, 3, 6, 5 | **Internal SPI Bus to ESP32** | **DO NOT WIRE** (Dedicated PCB traces) |

> [!WARNING]
> PMOD pins 9 through 12 are hardwired on the PCB to the ESP32-to-FPGA SPI communication bus. Do not connect external wires to PMOD pins 9–12.

---

## 3. FPGA RTL Architecture

The RTL is written in synthesizable Verilog in `ffpga/src/`:

1. **`line_position_encoder.v`**: Centroid lookup table mapping 8 sensor bits to a signed error ($e \in [-7, +7]$) with last-known direction memory.
2. **`pid_controller.v`**: Discrete fixed-point PID with configurable 8-bit gains, anti-windup accumulator clamp ($\pm 511$), backward-difference derivative, and arithmetic right shift (`SCALE_SHIFT = 4`).
3. **`motor_mixer.v`**: Differential steering mixer ($PWM_L = \text{speed} - \text{steer}$, $PWM_R = \text{speed} + \text{steer}$). If the line is lost, executes a pivot recovery search toward `last_dir` only when `base_speed > 0`. If `base_speed == 0`, motor outputs are strictly forced to 0.
4. **`pid_top.v`**: Top-level module integrating:
   - 2-stage execution pipeline to eliminate combinational timing pressure.
   - Dedicated 50 Hz RC servo pulse generators ($1000\,\mu\text{s} - 2000\,\mu\text{s}$, $1500\,\mu\text{s}$ center neutral, right mirrored for chassis symmetry, flat 0V pulse silence on disarm).
   - 50 ms SPI safety watchdog auto-shutdown.
   - Synchronous SPI slave interface responding to 4-byte frames at 2.0 MHz.

---

## 4. Verification & Toolchain Status

| Check / Stage | Tool / Framework | Status | Notes |
| :--- | :--- | :---: | :--- |
| **Python Unit & Servo Tests** | `pytest` (13 test cases) | **PASS** | Bit-accurate reference model & pulse timing |
| **Verilog Static Lint** | `verilator_bin.exe` (v5.034) | **PASS** | 0 errors, 0 warnings (IEEE 1800-2023 timing) |
| **Yosys Netlist Elaboration** | `yosys.exe` (v59) | **PASS** | Clean hierarchy, 0 undriven signals, 0 latches |
| **HDL Timing Simulation** | Icarus Verilog (`iverilog` + `vvp`) | **PASS** | 89.1 ms testbench, 5/5 hardware checks passed |
| **Vendor Synthesis & PnR** | Renesas Go Configure Hub v6.56 | **PASS** | Place-and-Route completed, bitstream generated |
| **MCU Firmware Compilation** | `arduino-cli` (esp32:esp32s3) | **PASS** | Compiled cleanly (366 kB flash, 27%) |

---

## 5. Quick Start: Build, Simulate & Flash

### 5.1 Run Automated Regression Suite
Runs the Python test suite, cycle-accurate waveform generator, Verilator static lint, and Yosys synthesis check:
```powershell
powershell -ExecutionPolicy Bypass -File .\workspace\fpga_pid_line_follower\scripts\test-all.ps1
```

### 5.2 Run HDL Simulation in Icarus Verilog
Runs the self-checking hardware testbench:
```powershell
iverilog -o sim.vvp ffpga/sim/tb_pid_top.v ffpga/src/pid_top.v
vvp sim.vvp
```
To inspect waveforms in GTKWave:
```powershell
gtkwave tb_pid_top.vcd
```

### 5.3 Flash ESP32 Firmware
Connect the Shrike-Fi board over USB-C, identify the COM port, and upload:
```powershell
arduino-cli compile --fqbn esp32:esp32:esp32s3 firmware/shrike_line_follower/shrike_line_follower.ino
arduino-cli upload -p <COM_PORT> --fqbn esp32:esp32:esp32s3 firmware/shrike_line_follower/shrike_line_follower.ino
```

---

## 6. Serial Console & Track Tuning

Open the serial monitor at **115200 baud** (via Arduino IDE, PuTTY, or `python -m serial.tools.miniterm <COM_PORT> 115200`):

### Bench Commissioning (Wheels Elevated):
1. **Boot Check**: Verify the startup banner:
   ```text
   [BOOT] Streaming 46408 bytes to ForgeFPGA...
   [BOOT] ForgeFPGA successfully configured and running!
   ```
2. **Sensor Sweep**: Wave black tape under the sensor bar:
   - Tape centered &rarr; both wheels spin forward at equal speed.
   - Tape left &rarr; left wheel accelerates, right wheel slows down (steers right).
   - Tape right &rarr; right wheel accelerates, left wheel slows down (steers left).
   - No line detected &rarr; LineLost flag asserts, initiates memory pivot search.
   - Type `disarm` &rarr; both wheels stop dead (pulse generator silenced).

### Runtime Serial Commands:
- `arm` &mdash; Enable motor outputs and start PID tracking.
- `disarm` &mdash; Immediately silence servo pulses and stop robot.
- `speed <val>` &mdash; Set base forward speed (`0`–`255`, recommended starting speed: `70`–`90`).
- `kp <val>` &mdash; Set proportional gain.
- `ki <val>` &mdash; Set integral gain.
- `kd <val>` &mdash; Set derivative gain.
- `telemetry` &mdash; Toggle live 10 Hz telemetry streaming (`PWM_L`, `PWM_R`, `Error`, `Status`).
- `status` &mdash; Print current gains, speed, and safety state.

---

## 7. Project Structure

```text
workspace/fpga_pid_line_follower/
├── README.md                                 # Master architecture & project documentation
├── .gitignore                                # Git ignore rules (clean repository state)
├── docs/
│   ├── WIRING.md                             # Complete wiring schematics, power & pinout reference
│   ├── BUILD_AND_FLASH.md                    # Compilation, bitstream packing & upload guide
│   └── NOTES.md                              # Technical audit, SPI packet spec & verification notes
├── ffpga/
│   ├── src/
│   │   ├── pid_top.v                         # Top-level FPGA module (pipeline, servos, watchdog)
│   │   ├── line_position_encoder.v           # 8-bit centroid decoder
│   │   ├── pid_controller.v                  # Fixed-point PID with anti-windup clamp
│   │   ├── motor_mixer.v                     # Differential motor mixer with pivot recovery
│   │   ├── pwm_generator.v                   # Dual PWM generator
│   │   └── spi_target.v                      # SPI slave communication core
│   └── sim/
│       ├── tb_pid_top.v                      # Self-checking 5-test hardware testbench
│       └── tb_pwm_generator.v                # PWM verification testbench
├── firmware/
│   └── shrike_line_follower/
│       ├── shrike_line_follower.ino          # Main 1 kHz control loop sketch
│       ├── config.h                          # Pin mappings & safety parameters
│       ├── pid_bitstream.h                   # Synthesized FPGA bitstream header
│       ├── sensors.h / sensors.cpp           # IR sensor GPIO sampling
│       ├── motors.h / motors.cpp             # Servo pulse & motor interface
│       ├── fpga_interface.h / .cpp           # SPI bootstrap & runtime communication
│       └── telemetry.h / telemetry.cpp       # Serial CLI & diagnostics
├── Go/
│   └── Shriketracerunner/                    # Official Renesas Go Configure Hub project
│       └── Shriketracerunner.ffpga           # Project XML with pin mappings & synthesis config
├── tests/
│   ├── reference_model.py                    # Bit-accurate Python reference model
│   ├── test_pid_golden.py                    # Golden unit tests for PID arithmetic
│   ├── test_pwm.py                           # PWM duty cycle tests
│   └── test_servo_engine.py                  # Continuous rotation servo pulse verification
└── scripts/
    ├── build-all.ps1                         # Builds RTL + compiles MCU firmware
    ├── test-all.ps1                          # Automated regression test suite
    ├── run-tb.ps1                            # Dedicated testbench & lint runner
    └── generate_waveforms.py                 # Cycle-accurate ASCII & VCD waveform generator
```
