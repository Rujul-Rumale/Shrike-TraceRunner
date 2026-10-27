# Build & Flash Guide

Instructions for building the Verilog RTL, compiling the ESP32-S3 firmware, flashing over USB, and tuning over the serial console.

---

## 1. Quick Start: One-Click Build & Regression

From the root workspace directory `C:\Projects\Vicharak\`:

```powershell
# 1. Run all unit tests, RTL linting, Yosys elaboration, and environment checks
powershell -ExecutionPolicy Bypass -File .\workspace\fpga_pid_line_follower\scripts\test-all.ps1

# 2. Run complete end-to-end build (Verilator + Yosys + Arduino CLI Firmware)
powershell -ExecutionPolicy Bypass -File .\workspace\fpga_pid_line_follower\scripts\build-all.ps1
```

---

## 2. Flashing the Firmware to Shrike-Fi

Connect the Vicharak Shrike-Fi board to your PC via USB-C.

```powershell
# 1. Identify active COM port
python -m serial.tools.list_ports

# 2. Upload firmware (replace COM14 with your active port)
C:\Projects\Vicharak\tools\arduino-cli\arduino-cli.exe upload `
  -p COM14 `
  --fqbn esp32:esp32:esp32s3 `
  C:\Projects\Vicharak\workspace\fpga_pid_line_follower\firmware\shrike_line_follower\shrike_line_follower.ino
```

---

## 3. Renesas Go Configure Software Hub Workflow (FPGA Synthesis)

If you modify the Verilog RTL and wish to regenerate the bitstream:

1. Launch **Go Configure Software Hub**:
   `C:\Program Files\Renesas Electronics\Go Configure Software Hub\GP6.exe`
2. Under the **Develop** tab, select **ForgeFPGA** $\to$ **SLG47910 (BB silicon)**.
3. Add the synthesizable source files from `workspace/fpga_pid_line_follower/ffpga/src/`:
   - `pid_top.v`
   - `spi_target.v`
   - `line_position_encoder.v`
   - `pid_controller.v`
   - `motor_mixer.v`
4. Open the **IO Planner** and map the top-level signals:
   - `clk` $\to$ `OSC_CLK`
   - `clk_en` $\to$ `OSC_EN`
   - `spi_sck` $\to$ `Pin 3` (SPI_SCLK)
   - `spi_ss_n` $\to$ `Pin 4` (SPI_SS)
   - `spi_mosi` $\to$ `Pin 5` (SPI_SI)
   - `spi_miso` $\to$ `Pin 6` (SPI_SO)
   - `spi_miso_en` $\to$ `Pin 6_OE`
   - `led` $\to$ `Pin 16`
   - `led_en` $\to$ `Pin 16_OE`
5. Click **Synthesize $\to$ Generate Bitstream**.
6. The generated bitstream will be in `ffpga/build/bitstream/FPGA_bitstream_MCU.bin` (exactly 46,408 bytes).
7. Convert the `.bin` into C header array format using:
   ```powershell
   python -c "b = open('FPGA_bitstream_MCU.bin','rb').read(); open('pid_bitstream.h','w').write('#pragma once\n#define PID_BITSTREAM_SIZE 46408\nconst uint8_t pid_bitstream[PID_BITSTREAM_SIZE] PROGMEM = {' + ','.join(hex(x) for x in b) + '};\n')"
   ```

---

## 4. Interactive Serial Console & Calibration

Open the Serial Monitor at **115200 baud** (via Arduino IDE, PuTTY, or Python):

```powershell
python -m serial.tools.miniterm COM14 115200
```

### Commissioning Steps:
1. **Lift wheels off ground**: Ensure robot chassis is elevated so wheels spin freely.
2. **Observe Boot Messages**:
   - Verify `[BOOT] ForgeFPGA successfully configured and running!`
   - Verify `[BOOT] Initial sensor reading: 0x...`
3. **Sensor Alignment Check**:
   - Slide a piece of white paper with black tape under the 8 sensors.
   - Observe the live sensor ASCII display: `Sensors: [..##....] | Err:  0`.
   - When tape moves left: `Sensors: [####....] | Err: -4`.
   - When tape moves right: `Sensors: [....####] | Err: +4`.
4. **Motor Direction Test**:
   - Type `arm` in the terminal to activate motors.
   - Verify left wheel speeds up when line deviates left, and right wheel speeds up when line deviates right.
   - Type `stop` to disarm motors.
5. **Track Testing**:
   - Place robot on physical track.
   - Type `speed 80` (low test speed) and type `arm`.
   - Tune $K_p, K_i, K_d$ dynamically using `kp <val>`, `ki <val>`, `kd <val>` until tracking is smooth without oscillations.
