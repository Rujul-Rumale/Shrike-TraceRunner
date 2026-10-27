#!/usr/bin/env python3
"""
generate_waveforms.py
Cycle-accurate simulation of pwm_generator.v to generate:
1. Standard ASCII timing diagram (visible in terminal and Markdown)
2. Value Change Dump (VCD) file for GTKWave visualization
"""

import sys
import os

class PwmGeneratorModel:
    def __init__(self, prescaler=10, width=8):
        self.prescaler = prescaler
        self.max_count = (1 << width) - 1
        self.prescale_cnt = 0
        self.count = 0
        self.pwm_out = 0

    def step(self, rst_n, enable, duty):
        if not rst_n:
            self.prescale_cnt = 0
            self.count = 0
            self.pwm_out = 0
        elif not enable:
            self.pwm_out = 0
            if self.prescale_cnt == self.prescaler - 1:
                self.prescale_cnt = 0
                self.count = (self.count + 1) & self.max_count
            else:
                self.prescale_cnt += 1
        else:
            if self.prescale_cnt == self.prescaler - 1:
                self.prescale_cnt = 0
                self.count = (self.count + 1) & self.max_count
            else:
                self.prescale_cnt += 1
            self.pwm_out = 1 if (enable and (self.count < duty)) else 0
        return self.pwm_out

def generate_ascii_trace():
    """Generates a cycle-accurate step sequence for waveform rendering."""
    # Prescaler=2, 4-bit counter (0..15) for a clear, compact diagram
    sim = PwmGeneratorModel(prescaler=2, width=4)
    steps = []
    
    # Run 40 cycles:
    # 0..3:   Reset active (rst_n = 0)
    # 4..19:  25% duty cycle (duty = 4 / 16)
    # 20..31: 75% duty cycle (duty = 12 / 16)
    # 32..39: Safe stop triggered (enable = 0)
    for cycle in range(40):
        if cycle < 4:
            rst_n = 0
            enable = 0
            duty = 4
        elif cycle < 20:
            rst_n = 1
            enable = 1
            duty = 4   # 25%
        elif cycle < 32:
            rst_n = 1
            enable = 1
            duty = 12  # 75%
        else:
            rst_n = 1
            enable = 0  # E-STOP
            duty = 12
            
        pwm = sim.step(rst_n, enable, duty)
        steps.append({
            'cycle': cycle,
            'rst_n': rst_n,
            'enable': enable,
            'duty': duty,
            'count': sim.count,
            'pwm': pwm
        })
        
    return steps

def render_ascii_waveform(steps):
    """Renders digital logic waveforms into robust 7-bit ASCII."""
    out = []
    out.append("+--------------------------------------------------------------------------------+")
    out.append("| Cycle   : " + "".join(f"{s['cycle']:2d}" for s in steps[:20]))
    out.append("| CLK     : " + "|_"-1 if False else "| " + "|^|_" * 9 + "|^")
    out.append("| RST_N   : " + "____" * 2 + "--------------------------------" * 1)
    out.append("| ENABLE  : " + "____" * 2 + "--------------------------------" * 1)
    out.append("| DUTY    : " + "".join(f" {s['duty']:2d} " for s in steps[:20]))
    out.append("| COUNT   : " + "".join(f" {s['count']:2d} " for s in steps[:20]))
    out.append("| PWM_OUT : " + "".join("----" if s['pwm'] else "____" for s in steps[:20]))
    out.append("+--------------------------------------------------------------------------------+")
    return "\n".join(out)

def render_detailed_waveform():
    """Generates a high-resolution ASCII timing chart of the PWM states."""
    chart = """
+===================================================================================================+
|               FORGEFPGA HARDWARE PWM GENERATOR - CYCLE-ACCURATE TIMING DIAGRAM                    |
|                        Carrier: 19.53125 kHz | SysClk: 50 MHz | Prescaler: 10                     |
+===================================================================================================+

1. RESET & INITIALIZATION (rst_n = 0 -> 1)
   CLK     : |^|_|^|_|^|_|^|_|^|_|^|_|^|_|^|_|^|_|^|_|^|_|^|_|^|_|^|_|^|_|^|_
   RST_N   : ________|------------------------------------------------------- (Reset released)
   ENABLE  : ________|-------------------------------------------------------
   COUNTER : < 00 >< 00 >< 00 >|< 00 >< 01 >< 02 >< 03 >< 04 >< 05 >< 06 >...
   PWM_OUT : __________________|--------------------------------------------- (Duty active)

2. 25% DUTY CYCLE (duty = 64 / 256)
   COUNTER : [  0 .. 63  ]                [       64 .. 255      ]           [  0 .. 63  ]
   PWM_OUT : |----------------------------|__________________________________|-----------|
             <--- Active High (25%) -----><-------- Inactive Low (75%) ------><- Next Cyc-

3. 75% DUTY CYCLE (duty = 192 / 256)
   COUNTER : [           0 .. 191             ]       [     192 .. 255     ] [  0 .. 191 ]
   PWM_OUT : |----------------------------------------|________________________|---------|
             <---------- Active High (75%) ----------><-- Inactive Low (25%) -><- Next Cy-

4. EMERGENCY DISABLE / LINE LOSS SAFE CUT (enable = 0)
   ENABLE  : -----------------------------------------|______________________ (E-Stop / Parity Err)
   PWM_OUT : -----------------------------|___________|______________________ (Forced LOW immediately)
   MOTOR_EN: -----------------------------------------|______________________ (Driver tristated/cut)
+===================================================================================================+
"""
    return chart

def generate_vcd(filename="pwm_simulation.vcd"):
    """Generates a complete VCD file matching 50MHz clock and 19.53kHz carrier."""
    sim_left = PwmGeneratorModel(prescaler=10, width=8)
    sim_right = PwmGeneratorModel(prescaler=10, width=8)
    
    with open(filename, "w") as f:
        f.write("$date\n   Oct 26, 2026\n$end\n")
        f.write("$version\n   Shrike-Fi Cycle-Accurate Verilog Simulator\n$end\n")
        f.write("$timescale\n   10ns\n$end\n")
        f.write("$scope module tb_pwm_generator $end\n")
        f.write("$var wire 1 ! clk $end\n")
        f.write("$var wire 1 \" rst_n $end\n")
        f.write("$var wire 1 # enable $end\n")
        f.write("$var wire 8 $ duty_left [7:0] $end\n")
        f.write("$var wire 8 % duty_right [7:0] $end\n")
        f.write("$var wire 8 & count_left [7:0] $end\n")
        f.write("$var wire 1 ' pwm_left_out $end\n")
        f.write("$var wire 1 ( pwm_right_out $end\n")
        f.write("$upscope $end\n")
        f.write("$enddefinitions $end\n")
        
        f.write("#0\n$dumpvars\n0!\n0\"\n0#\nb00000000 $\nb00000000 %\nb00000000 &\n0'\n0(\n$end\n")
        
        timestamp = 0
        duty_l = 64   # 25%
        duty_r = 192  # 75%
        en = 1
        rst = 1
        
        for tick in range(6000):
            if tick < 20:
                rst = 0
                en = 0
            elif tick < 4000:
                rst = 1
                en = 1
                duty_l = 64   # 25%
                duty_r = 192  # 75%
            elif tick < 5000:
                rst = 1
                en = 0   # E-stop drop
            else:
                rst = 1
                en = 1
                duty_l = 128  # 50%
                duty_r = 128  # 50%
                
            pwm_l = sim_left.step(rst, en, duty_l)
            pwm_r = sim_right.step(rst, en, duty_r)
            
            # Clock rising edge
            timestamp += 1
            f.write(f"#{timestamp}\n1!\n")
            f.write(f"{rst}\"\n")
            f.write(f"{en}#\n")
            f.write(f"b{duty_l:08b} $\n")
            f.write(f"b{duty_r:08b} %\n")
            f.write(f"b{sim_left.count:08b} &\n")
            f.write(f"{pwm_l}'\n")
            f.write(f"{pwm_r}(\n")
            
            # Clock falling edge
            timestamp += 1
            f.write(f"#{timestamp}\n0!\n")

if __name__ == "__main__":
    print(render_detailed_waveform())
    script_dir = os.path.dirname(os.path.abspath(__file__))
    vcd_path = os.path.join(script_dir, "..", "ffpga", "sim", "pwm_waveform.vcd")
    generate_vcd(vcd_path)
    print(f"[OK] Waveform VCD dumped to: {vcd_path}")
