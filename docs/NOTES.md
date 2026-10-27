# Developer Notes & Hardware Info

Quick collection of notes, architecture details, and troubleshooting tips for the Shrike-Fi PID Line Follower.

---

## 1. FPGA Datapath & Resource Usage

The FPGA implementation runs on the Renesas ForgeFPGA SLG47910 (BB silicon) on the Shrike-Fi board.

- **Clock**: 50 MHz internal oscillator (`OSC_CLK`).
- **PWM Carrier Frequency**:
  - Formula: $f_{PWM} = \frac{50\text{ MHz}}{\text{PRESCALER} \times 2^{\text{WIDTH}}} = \frac{50\text{ MHz}}{10 \times 256} = 19.53125\text{ kHz}$.
  - Ultrasonic carrier eliminates motor coil whine.
- **Duty Cycle Endpoints**:
  - `duty = 0`: strictly 0% (continuous low, motor stopped).
  - `duty = 255`: 255/256 = 99.6% high (full speed).
  - `enable = 0`: forces PWM immediately to 0.
- **Resource Analysis (Generic Yosys AST vs Vendor Synthesis)**:
  - *Generic Elaboration*: 212 abstract AST cells (`$_DFF_`, `$add`, `$mux`, 3 unexpanded `$mul` primitives).
  - *Vendor Technology Mapping (`synth_xilinx -nodsp` for EFLX-1K)*:
    - Multipliers mapped to soft-logic carry adder arrays (no hard DSP blocks on SLG47910).
    - Total Estimated Logic Cells: **637 LCs** out of 1,120 total capacity (**56.8% utilization**).
    - Flip-Flops: 203.
    - LUTs: 289 (LUT2: 77, LUT3: 28, LUT4: 20, LUT5: 41, LUT6: 123).
    - Carry primitives (`CARRY4`): 40.
- **Safety Interlocks**:
  - `motor_en_out` (PMOD J5 Pin 7, Package Pin 2) is driven low during power-on reset and immediately trips low upon SPI parity error.
  - Line lost recovery: When all 8 sensors read 0, asserts `LINE_LOST` and uses last-known error direction to pivot at `SEARCH_SPEED` (60) until the line is reacquired.

---

## 2. SPI Protocol & Timing Feasibility (ESP32-S3 <-> FPGA)

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
- Even at 1.0 MHz SPI clock, transaction time is $32\,\mu\text{s}$ (3.2% bus utilization). 1 kHz real-time deterministic updates are easily achieved with massive timing margin.

### Packet Format (4 bytes full-duplex per 1ms cycle)

```
Downlink (MCU -> FPGA):
  Byte 0: CMD       (0x10 = Run, 0x20 = Set Kp, 0x21 = Set Ki, 0x22 = Set Kd, 0xFF = Reset)
  Byte 1: SENSORS   (Bit 7 = Far Left ... Bit 0 = Far Right. 1 = Line detected)
  Byte 2: SPEED     (Base forward motor PWM, 0-255)
  Byte 3: CHECKSUM  (CMD ^ SENSORS ^ SPEED)

Uplink (FPGA -> MCU):
  Byte 0: STATUS    (Bit 7: Heartbeat toggle, Bit 6: Line Lost, Bit 5: I-Sat, Bit 4: Steer-Sat)
  Byte 1: PWM_LEFT  (Calculated Left motor speed, 0-255)
  Byte 2: PWM_RIGHT (Calculated Right motor speed, 0-255)
  Byte 3: ERROR     (Signed line error, -7 to +7)
```

---

## 3. Power & Battery Notes

- **Battery**: 2S 18650 cells in series (~7.4V nominal, up to 8.4V fully charged).
- **DO NOT** feed raw 7.4V directly into the Shrike-Fi board or sensors!
- Power split:
  - 7.4V -> Step-down buck converter (e.g. MP1584 / LM2596) -> **5.0V** -> Shrike-Fi 5V input pin.
  - 7.4V -> L298N motor driver power input (`VMS`).
- **L298N Voltage Drop Trick**: The L298N has internal bipolar transistor drops ($V_{CE(sat)}$) of roughly 1.5V - 1.8V total. This means an 7.4V - 8.0V battery voltage naturally drops down to ~5.6V - 6.2V across the N20 motors, which is right in their safe sweet spot (rated 3-6V).
- Connect all GNDs together (Battery GND, Buck GND, Shrike GND, L298N GND, Sensor GND).

---

## 4. Serial Debug & Tuning Commands

Connect over USB-C at 115200 baud. Available interactive commands:

| Command | Action |
|:---|:---|
| `arm` | Arm motors (starts driving) |
| `stop` | Disarm motors (safe stop) |
| `speed <0-255>` | Set base forward speed (default 110) |
| `kp <0-255>` | Set proportional gain (default 32) |
| `ki <0-255>` | Set integral gain (default 2) |
| `kd <0-255>` | Set derivative gain (default 48) |
| `polarity <0|1>` | Invert sensor polarity (0 = active-low, 1 = active-high) |
| `csv` | Toggle CSV telemetry streaming for plotting |
| `reset` | Reset PID accumulator and motor state |
| `status` | Print full system diagnostic readout |

---

## 5. TODOs / Future Improvements

- [ ] Fine-tune PID gains on real track with black electrical tape (current defaults Kp=32, Ki=2, Kd=48 work well in sim).
- [ ] Measure motor current draw during aggressive turns to verify 2S battery runtime.
- [ ] Try direct PMOD sensor wiring if lower latency is ever needed (FPGA RTL already supports `direct_sensor_pins` via command `0x11`).
