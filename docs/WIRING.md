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

### 2.2 L298N Motor Driver to Shrike-Fi

| L298N Terminal | Shrike-Fi / Power Pin | Function | Notes |
|:---:|:---:|:---|:---|
| **VCC (+12V)** | Battery Positive (+) via Switch | Motor Power (7.4V – 8.4V) | Connect through 3A Fuse |
| **GND** | Common Ground | Ground Reference | Must be tied to Shrike-Fi GND |
| **5V Terminal** | NC (Not Connected) | L298N internal logic | Remove jumper if powered externally |
| **ENA** | **GPIO 38** | Left Motor PWM Speed | ESP32 LEDC Channel 0 (20 kHz) |
| **IN1** | **GPIO 17** | Left Motor Direction A | Digital Output |
| **IN2** | **GPIO 18** | Left Motor Direction B | Digital Output |
| **IN3** | **GPIO 40** | Right Motor Direction A | Digital Output |
| **IN4** | **GPIO 41** | Right Motor Direction B | Digital Output |
| **ENB** | **GPIO 39** | Right Motor PWM Speed | ESP32 LEDC Channel 1 (20 kHz) |

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
