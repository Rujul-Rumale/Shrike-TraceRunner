# Developer Notes & Hardware Technical Audit

Technical notes, verified hardware interconnects, electrical safety, and toolchain audit details for the Shrike-TraceRunner project.

---

## 1. FPGA Control Datapath & Resource Status

The control datapath is targeted for the **Renesas ForgeFPGA SLG47910** (BB silicon) on the Shrike-Fi board:

- **Clock Source**: 50 MHz internal relaxation oscillator (`OSC_CLK`).
- **PWM Carrier Frequency**:
  $$f_{PWM} = \frac{50\text{ MHz}}{\text{PRESCALER} \times 2^{\text{WIDTH}}} = \frac{50\text{ MHz}}{10 \times 256} = 19.53125\text{ kHz}$$
  Ultrasonic carrier eliminates acoustic coil whine and minimizes motor ripple currents.
- **Duty Cycle Endpoints**:
  - `duty = 0`: strictly 0.0% (continuous LOW; motor off).
  - `duty = 255`: 255/256 = 99.6% HIGH (near full drive).
  - `enable = 0`: synchronous immediate force to 0.
- **Resource Utilization Status (Audit Findings)**:
  - **Generic Yosys Netlist Elaboration**: Elaborates to **244 generic AST cells** (`$_DFF_`, `$add`, `$mux`, 3 `$mul` primitives) with zero syntax errors, zero latch warnings, and clean hierarchy (`hierarchy -check`).
  - **Vendor ForgeFPGA Bitstream Flow**: **UNVERIFIED IN HARDWARE**. The Renesas ForgeFPGA EFLX-1K architecture uses a proprietary macro-cell structure and placement tool (`eda-placer.exe`) integrated into the Go Configure Software Hub GUI (`GP6.exe`). Generic Yosys cells or third-party targets (such as Xilinx) do not represent SLG47910 vendor cell utilization. Bitstream generation must be confirmed via the official GUI project flow before programming hardware.
- **RTL Safety Interlocks**:
  - **Power-on Safe Reset**: All PWM outputs and `motor_en_out` are held strictly LOW during power-on reset. Speed register initializes to `0`.
  - **Hardware SPI Watchdog**: A 50 ms timeout counter (2,500,000 cycles at 50 MHz) automatically trips `watchdog_tripped` and drops `motor_en_out` to 0 if valid SPI frames stop arriving.
  - **Parity / Checksum Trip**: Any SPI frame failing the XOR checksum immediately asserts `parity_error_flag` and drops `motor_en_out` to 0.
  - **Zero-Speed Interlock**: If `base_speed == 0`, motor outputs remain strictly 0 even if `line_lost` is asserted.

---

## 2. SPI Protocol & Interface Feasibility (ESP32-S3 <-> FPGA)

The Shrike-Fi connects the ESP32-S3 and ForgeFPGA via 4 dedicated SPI lines:
- `SCK`: ESP32 GPIO 12 -> FPGA Pin 3 (PMOD J5 Pin 10)
- `SS_N`: ESP32 GPIO 10 -> FPGA Pin 4 (PMOD J5 Pin 9)
- `MOSI`: ESP32 GPIO 11 -> FPGA Pin 5 (PMOD J5 Pin 12)
- `MISO`: FPGA Pin 6 -> ESP32 GPIO 13 (PMOD J5 Pin 11)

Bus config: 2.0 MHz SPI clock, Mode 0 (`CPOL=0, CPHA=0`), MSB first.

### 1 kHz Loop Feasibility:
- A 4-byte SPI transaction at 2.0 MHz takes:
  $$T_{\text{tx}} = \frac{32\text{ bits}}{2\text{ MHz}} = 16.0\,\mu\text{s}$$
- In a 1 kHz (1,000 $\mu$s) control loop:
  - SPI transmission overhead: $16\,\mu\text{s}$ (only **1.6% bus utilization**).
  - Remaining CPU time for ESP32 sensor read and Wi-Fi handling: $984\,\mu\text{s}$ (98.4%).
- 1 kHz deterministic updates are feasible with substantial timing margin.

### Packet Format (4 bytes full-duplex per 1ms cycle)

```text
Downlink (MCU -> FPGA):
  Byte 0: CMD       (0x00 = Disarm, 0x10 = Run, 0x20 = Set Kp, 0x21 = Set Ki, 0x22 = Set Kd, 0xFF = Reset)
  Byte 1: SENSORS   (Bit 7 = Far Left ... Bit 0 = Far Right. 1 = Line detected)
  Byte 2: SPEED     (Base forward motor PWM, 0-255)
  Byte 3: CHECKSUM  (CMD ^ SENSORS ^ SPEED)

Uplink (FPGA -> MCU):
  Byte 0: STATUS    (Bit 7: Heartbeat, Bit 6: Line Lost, Bit 5: I-Sat, Bit 4: Steer-Sat,
                     Bit 3: Parity Err, Bit 2: Last Dir, Bit 1: Watchdog Trip, Bit 0: Armed)
  Byte 1: PWM_LEFT  (Calculated Left motor speed, 0-255)
  Byte 2: PWM_RIGHT (Calculated Right motor speed, 0-255)
  Byte 3: ERROR     (Signed line error, -7 to +7)
```

---

## 3. Power Architecture & Electrical Safety

- **Battery Protection**: 2S Li-ion battery pack (7.4V nominal, 6.0V–8.4V operating range) MUST use a 2S BMS protection board with over-discharge cut-off ($\le 3.0\text{V/cell}$ / 6.0V total), overcharge protection, and short-circuit protection.
- **Over-Current Protection**: A master toggle switch and an inline **3A fast-acting fuse** must be installed on the battery positive lead.
- **Regulated Motor Supply**:
  - **Do NOT feed unregulated battery voltage into the L298N or rely on internal transistor saturation drops as a voltage regulator.**
  - A dedicated DC-DC step-down buck converter (or high-efficiency regulator) adjusted to **5.0V or 6.0V DC** (rated $\ge 2.5\text{A}$) must supply the L298N motor power input (`VMS`). This guarantees motor voltages strictly respect the 3V–6V rating of N20 motors.
- **Regulated Logic Supply**: A separate 5.0V DC-DC buck converter (rated $\ge 2.0\text{A}$) supplies the Shrike-Fi 5V input header.
- **L298N Logic Supply**: Remove the onboard 12V-to-5V regulator jumper on the L298N and connect the 5V terminal directly to the regulated 5.0V logic rail.
- **Driver Pull-Downs**: External $10\,\text{k}\Omega$ pull-down resistors to GND on L298N `ENA` and `ENB` ensure motors remain safely disabled when FPGA I/O pins are floating or high-impedance.
- **Common Ground**: Strict star ground topology tying Battery (-), Buck GNDs, Shrike-Fi GND, L298N GND, and Sensor GND at a single point.

---

## 4. Current Verification & Testing Status

| Stage | Feature / Component | Status | Verification Method |
|---|---|---|---|
| **RTL Source** | Line position centroid encoder | Implemented | Verilog source (`line_position_encoder.v`) |
| **RTL Source** | Fixed-point PID w/ anti-windup | Implemented | Verilog source (`pid_controller.v`) |
| **RTL Source** | Differential motor mixer & pivot | Implemented | Verilog source (`motor_mixer.v`) |
| **RTL Source** | 2-channel 19.53 kHz PWM generators | Implemented | Verilog source (`pwm_generator.v`) |
| **RTL Source** | Synchronous SPI slave interface | Implemented | Verilog source (`spi_target.v`) |
| **RTL Source** | Hardware safety watchdog & interlocks | Implemented | Verilog source (`pid_top.v`) |
| **Simulation** | Bit-accurate PID reference model | **PASSED** | Python model (`tests/test_pid_golden.py`) |
| **Simulation** | PWM duty cycle & safety interlocks | **PASSED** | Python simulation (`tests/test_pwm.py`) |
| **Simulation** | Cycle-accurate Verilog PWM & VCD | **PASSED** | Python simulator (`scripts/generate_waveforms.py`) |
| **Static Check**| Verilator lint & static timing check | **PASSED** | Verilator v5.034 (0 errors, 0 warnings) |
| **Synthesis** | Generic Yosys Netlist Elaboration | **PASSED** | Yosys v59 AST elaboration (244 cells) |
| **Vendor Flow** | Renesas ForgeFPGA Bitstream Placement | **UNVERIFIED** | Requires Go Configure Hub GUI execution |
| **Hardware** | Bench testing (logic analyzers / scope) | **NOT RUN** | Blocked on bitstream flash & bench setup |
| **Hardware** | Physical robot track validation | **NOT RUN** | Chassis / motors not yet powered |

---

## 5. Next Steps

- [ ] Import RTL into Renesas Go Configure Software Hub GUI (`GP6.exe`) to generate verified vendor bitstream.
- [ ] Connect oscilloscope / logic analyzer to PMOD J5 Pins 5, 6, 7 to bench-verify physical PWM waveforms and failsafe trip before connecting motors.
- [ ] Implement ESP32-S3 Wi-Fi Soft-AP and responsive tuning webpage (Milestone 2).
