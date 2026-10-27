"""
Unit test for FPGA Hardware PWM Generator logic.
Simulates clock ticks, prescaler, duty comparison, and enable/reset behavior.
"""

def simulate_pwm(duty_val: int, prescaler: int = 10, total_periods: int = 2, enabled: bool = True):
    period_ticks = 256
    total_clocks = total_periods * period_ticks * prescaler

    pwm_cnt = 0
    prescaler_cnt = 0
    pwm_out = 0
    high_clocks = 0

    for _ in range(total_clocks):
        tick = (prescaler_cnt == (prescaler - 1))
        if tick:
            prescaler_cnt = 0
        else:
            prescaler_cnt += 1

        if not enabled:
            pwm_cnt = 0
            pwm_out = 0
        elif tick:
            pwm_cnt = (pwm_cnt + 1) & 0xFF
            pwm_out = 1 if (pwm_cnt < duty_val) else 0

        if pwm_out:
            high_clocks += 1

    duty_fraction = high_clocks / total_clocks
    return duty_fraction

def test_pwm_ratios():
    # Test 0% duty
    assert simulate_pwm(0) == 0.0, "Duty 0 must yield exactly 0%"

    # Test 50% duty (128 / 256 = 0.5)
    ratio_50 = simulate_pwm(128)
    assert abs(ratio_50 - 0.5) < 0.005, f"Duty 128 expected ~50%, got {ratio_50}"

    # Test 25% duty (64 / 256 = 0.25)
    ratio_25 = simulate_pwm(64)
    assert abs(ratio_25 - 0.25) < 0.005, f"Duty 64 expected ~25%, got {ratio_25}"

    # Test 75% duty (192 / 256 = 0.75)
    ratio_75 = simulate_pwm(192)
    assert abs(ratio_75 - 0.75) < 0.005, f"Duty 192 expected ~75%, got {ratio_75}"

    # Test ~99.6% duty (255 / 256 = 0.996)
    ratio_max = simulate_pwm(255)
    assert abs(ratio_max - (255/256)) < 0.005, f"Duty 255 expected ~99.6%, got {ratio_max}"

    # Test disabled state
    assert simulate_pwm(128, enabled=False) == 0.0, "Disabled PWM must yield 0%"

    print("All PWM logic simulation assertions PASSED!")

if __name__ == "__main__":
    test_pwm_ratios()
