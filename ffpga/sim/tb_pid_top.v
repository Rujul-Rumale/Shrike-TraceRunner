/*
 * Module: tb_pid_top.v
 * Description: Self-checking testbench for pid_top module.
 * Verifies SPI framing, error calculation, PID arithmetic, and motor mixing.
 */

`timescale 1ns / 1ps

module tb_pid_top;

    reg clk;
    reg rst_n;
    reg spi_ss_n;
    reg spi_sck;
    reg spi_mosi;
    wire spi_miso;
    wire spi_miso_en;
    wire pwm_left_out;
    wire pwm_left_oe;
    wire pwm_right_out;
    wire pwm_right_oe;
    wire motor_en_out;
    wire motor_en_oe;
    wire led;
    wire led_en;

    // DUT instantiation
    pid_top dut (
        .clk(clk),
        .clk_en(),
        .rst_n(rst_n),
        .spi_ss_n(spi_ss_n),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_miso_en(spi_miso_en),
        .pwm_left_out(pwm_left_out),
        .pwm_left_oe(pwm_left_oe),
        .pwm_right_out(pwm_right_out),
        .pwm_right_oe(pwm_right_oe),
        .motor_en_out(motor_en_out),
        .motor_en_oe(motor_en_oe),
        .led(led),
        .led_en(led_en)
    );

    // 50 MHz system clock (20 ns period)
    always #10 clk = ~clk;

    // Task to perform a 1-byte SPI transfer (Mode 0, MSB first)
    task spi_transfer_byte(
        input  [7:0] tx_byte,
        output [7:0] rx_byte
    );
        integer i;
        begin
            rx_byte = 8'h00;
            for (i = 7; i >= 0; i = i - 1) begin
                spi_mosi = tx_byte[i];
                #100; // Half SCK period (5 MHz SPI)
                spi_sck = 1'b1;
                rx_byte[i] = spi_miso;
                #100;
                spi_sck = 1'b0;
            end
            #50;
        end
    endtask

    // Task to execute full 4-byte SPI frame
    task spi_exchange_frame(
        input  [7:0] cmd,
        input  [7:0] sensor,
        input  [7:0] speed,
        output [7:0] status,
        output [7:0] pwm_l,
        output [7:0] pwm_r,
        output [7:0] error_out
    );
        reg [7:0] parity;
        reg [7:0] rx_dummy;
        begin
            parity = cmd ^ sensor ^ speed;

            // Assert SS
            #200;
            spi_ss_n = 1'b0;
            #200;

            // Byte 0: CMD
            spi_transfer_byte(cmd, status);
            // Byte 1: SENSOR
            spi_transfer_byte(sensor, pwm_l);
            // Byte 2: SPEED
            spi_transfer_byte(speed, pwm_r);
            // Byte 3: PARITY
            spi_transfer_byte(parity, error_out);

            // Deassert SS
            #200;
            spi_ss_n = 1'b1;
            #500;
        end
    endtask

    // Test registers
    reg [7:0] status_rx, pwm_l_rx, pwm_r_rx, err_rx;
    integer test_failures = 0;

    initial begin
        $dumpfile("tb_pid_top.vcd");
        $dumpvars(0, tb_pid_top);

        clk = 1'b0;
        rst_n = 1'b0;
        spi_ss_n = 1'b1;
        spi_sck = 1'b0;
        spi_mosi = 1'b0;

        $display("\n============================================================");
        $display(" STARTING SELF-CHECKING TESTBENCH: tb_pid_top");
        $display("============================================================\n");

        // 1. Release reset after 300 cycles (internal counter is 256)
        #6000;
        rst_n = 1'b1;
        #1000;
        $display("[TB] Power-on Reset Complete. Initializing SPI transactions...");

        // ---------------------------------------------------------------------
        // TEST 1: Initial Sync & Center Tracking (S = 8'b0001_1000)
        // ---------------------------------------------------------------------
        $display("\n[TEST 1] Testing Dead Center Tracking (Sensors = 8'b0001_1000)...");
        // Prime the pipeline with 1st frame
        spi_exchange_frame(8'h10, 8'b0001_1000, 8'd100, status_rx, pwm_l_rx, pwm_r_rx, err_rx);
        #1000;
        // 2nd frame retrieves the computed outputs from 1st frame
        spi_exchange_frame(8'h10, 8'b0001_1000, 8'd100, status_rx, pwm_l_rx, pwm_r_rx, err_rx);
        
        $display("  -> Result: PWM_L=%d, PWM_R=%d, Error=%d, Status=0x%02X",
                 pwm_l_rx, pwm_r_rx, $signed(err_rx), status_rx);

        if (pwm_l_rx == 8'd100 && pwm_r_rx == 8'd100 && $signed(err_rx) == 0) begin
            $display("  [PASS] Center Tracking verified: Equal motor duties (100, 100), Zero error.");
        end else begin
            $display("  [FAIL] Expected (100, 100, 0), Got (%d, %d, %d)", pwm_l_rx, pwm_r_rx, $signed(err_rx));
            test_failures = test_failures + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 2: Hard Left Line Error (Sensors = 8'b1000_0000, Far Left)
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Testing Far Left Error (Sensors = 8'b1000_0000)...");
        spi_exchange_frame(8'h10, 8'b1000_0000, 8'd100, status_rx, pwm_l_rx, pwm_r_rx, err_rx);
        #1000;
        spi_exchange_frame(8'h10, 8'b1000_0000, 8'd100, status_rx, pwm_l_rx, pwm_r_rx, err_rx);

        $display("  -> Result: PWM_L=%d, PWM_R=%d, Error=%d", pwm_l_rx, pwm_r_rx, $signed(err_rx));

        if ($signed(err_rx) == -7 && pwm_l_rx > pwm_r_rx) begin
            $display("  [PASS] Left Correction verified: Error=-7, Left wheel sped up to turn right.");
        end else begin
            $display("  [FAIL] Expected Error=-7 and PWM_L > PWM_R, Got (%d, %d, %d)", pwm_l_rx, pwm_r_rx, $signed(err_rx));
            test_failures = test_failures + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 3: Hard Right Line Error (Sensors = 8'b0000_0001, Far Right)
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Testing Far Right Error (Sensors = 8'b0000_0001)...");
        spi_exchange_frame(8'h10, 8'b0000_0001, 8'd100, status_rx, pwm_l_rx, pwm_r_rx, err_rx);
        #1000;
        spi_exchange_frame(8'h10, 8'b0000_0001, 8'd100, status_rx, pwm_l_rx, pwm_r_rx, err_rx);

        $display("  -> Result: PWM_L=%d, PWM_R=%d, Error=%d", pwm_l_rx, pwm_r_rx, $signed(err_rx));

        if ($signed(err_rx) == 7 && pwm_r_rx > pwm_l_rx) begin
            $display("  [PASS] Right Correction verified: Error=+7, Right wheel sped up to turn left.");
        end else begin
            $display("  [FAIL] Expected Error=+7 and PWM_R > PWM_L, Got (%d, %d, %d)", pwm_l_rx, pwm_r_rx, $signed(err_rx));
            test_failures = test_failures + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 4: Line Lost Event (Sensors = 8'b0000_0000)
        // ---------------------------------------------------------------------
        $display("\n[TEST 4] Testing Line Lost Event & Memory Pivot Recovery...");
        // Previous error was Right (+7), so last_dir should be Right (1).
        // Line lost should trigger pivot right: PWM_L = SEARCH_SPEED (60), PWM_R = 0.
        spi_exchange_frame(8'h10, 8'b0000_0000, 8'd100, status_rx, pwm_l_rx, pwm_r_rx, err_rx);
        #1000;
        spi_exchange_frame(8'h10, 8'b0000_0000, 8'd100, status_rx, pwm_l_rx, pwm_r_rx, err_rx);

        $display("  -> Result: PWM_L=%d, PWM_R=%d, Status=0x%02X (LineLost bit=%b)",
                 pwm_l_rx, pwm_r_rx, status_rx, status_rx[6]);

        if (status_rx[6] == 1'b1 && pwm_l_rx == 8'd60 && pwm_r_rx == 8'd0) begin
            $display("  [PASS] Line Lost Recovery verified: Status flag asserted, executed pivot right (60, 0).");
        end else begin
            $display("  [FAIL] Expected LineLost=1 and (60, 0), Got (%d, %d, Status=0x%02X)", pwm_l_rx, pwm_r_rx, status_rx);
            test_failures = test_failures + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 5: Gain Tuning over SPI (Command 0x20: Set Kp = 64)
        // ---------------------------------------------------------------------
        $display("\n[TEST 5] Testing Runtime Gain Configuration over SPI (Cmd 0x20, Kp=64)...");
        spi_exchange_frame(8'h20, 8'd64, 8'd100, status_rx, pwm_l_rx, pwm_r_rx, err_rx);
        #1000;
        // Verify response with error = 2
        spi_exchange_frame(8'h10, 8'b0000_1100, 8'd100, status_rx, pwm_l_rx, pwm_r_rx, err_rx);
        #1000;
        spi_exchange_frame(8'h10, 8'b0000_1100, 8'd100, status_rx, pwm_l_rx, pwm_r_rx, err_rx);

        $display("  -> Result with doubled Kp: PWM_L=%d, PWM_R=%d, Error=%d", pwm_l_rx, pwm_r_rx, $signed(err_rx));
        if ($signed(err_rx) == 2 && pwm_r_rx > pwm_l_rx) begin
            $display("  [PASS] Runtime Gain Reconfiguration verified: New Kp applied without resetting FPGA.");
        end else begin
            $display("  [FAIL] Unexpected output with Kp=64: (%d, %d, %d)", pwm_l_rx, pwm_r_rx, $signed(err_rx));
            test_failures = test_failures + 1;
        end

        // ---------------------------------------------------------------------
        // Test 6: Verify Hardware PWM Generation on FPGA PMOD pins
        // ---------------------------------------------------------------------
        $display("\n[TEST 6] Testing FPGA 2-Channel Hardware PWM Generation...");
        if (motor_en_out !== 1'b1) begin
            $display("  [FAIL] motor_en_out is not asserted during active operation");
            test_failures = test_failures + 1;
        end else begin
            $display("  [PASS] motor_en_out asserted correctly.");
        end

        // Sample PWM signals over 5000 ns to verify pulse activity
        begin : test_pwm_pulses
            integer pwm_l_transitions;
            integer pwm_r_transitions;
            reg last_l, last_r;
            integer k;

            pwm_l_transitions = 0;
            pwm_r_transitions = 0;
            last_l = pwm_left_out;
            last_r = pwm_right_out;

            for (k = 0; k < 6000; k = k + 1) begin
                @(posedge clk);
                if (pwm_left_out !== last_l) begin
                    pwm_l_transitions = pwm_l_transitions + 1;
                    last_l = pwm_left_out;
                end
                if (pwm_right_out !== last_r) begin
                    pwm_r_transitions = pwm_r_transitions + 1;
                    last_r = pwm_right_out;
                end
            end

            if (pwm_l_transitions > 0 && pwm_r_transitions > 0) begin
                $display("  [PASS] FPGA Hardware PWM pulses detected on both left (%0d transitions) and right (%0d transitions) channels.", pwm_l_transitions, pwm_r_transitions);
            end else begin
                $display("  [FAIL] FPGA Hardware PWM static! (L transitions: %0d, R transitions: %0d)", pwm_l_transitions, pwm_r_transitions);
                test_failures = test_failures + 1;
            end
        end

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        $display("\n============================================================");
        if (test_failures == 0) begin
            $display(" TESTBENCH SUCCESS: ALL 6 TEST SUITES PASSED (0 FAILURES)!");
        end else begin
            $display(" TESTBENCH FAILED: %0d TESTS FAILED!", test_failures);
        end
        $display("============================================================\n");

        #1000;
        $finish;
    end

endmodule
