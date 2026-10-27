/*
 * Module: pid_top.v
 * Description: Top-level ForgeFPGA module for the Shrike-Fi PID Line Follower.
 * Target: Renesas ForgeFPGA SLG47910 (BB silicon)
 *
 * Board Interface (Shrike-Fi Hardware Interconnect):
 * - Pin 3: SPI_SCK      (ESP32 GPIO 12)
 * - Pin 4: SPI_SS_N     (ESP32 GPIO 10)
 * - Pin 5: SPI_MOSI     (ESP32 GPIO 11)
 * - Pin 6: SPI_MISO     (ESP32 GPIO 13)
 * - Pin 16: User LED    (On-board green LED)
 */

`timescale 1ns / 1ps

(* top *) module pid_top (
    (* iopad_external_pin, clkbuf_inhibit *) input clk,
    (* iopad_external_pin *) output clk_en,
    (* iopad_external_pin *) input  rst_n,

    // SPI Interconnect to ESP32-S3
    (* iopad_external_pin *) input  spi_ss_n,
    (* iopad_external_pin *) input  spi_sck,
    (* iopad_external_pin *) input  spi_mosi,
    (* iopad_external_pin *) output spi_miso,
    (* iopad_external_pin *) output spi_miso_en,

    // Direct 8-channel IR Sensor inputs (PMOD header option)
    (* iopad_external_pin *) input  [7:0] direct_sensor_pins,

    // FPGA Onboard User LED
    (* iopad_external_pin *) output led,
    (* iopad_external_pin *) output led_en
);

    // Enable internal 50 MHz oscillator
    assign clk_en = 1'b1;
    assign led_en = 1'b1;

    // -------------------------------------------------------------------------
    // Power-on Reset Generator
    // -------------------------------------------------------------------------
    reg [7:0] rst_counter = 8'd0;
    reg       internal_rst_n = 1'b0;

    always @(posedge clk) begin
        if (rst_counter < 8'hFF) begin
            rst_counter    <= rst_counter + 1'b1;
            internal_rst_n <= 1'b0;
        end else begin
            internal_rst_n <= rst_n;
        end
    end

    // -------------------------------------------------------------------------
    // SPI Slave Target Instance
    // -------------------------------------------------------------------------
    wire [7:0] spi_rx_data;
    wire       spi_rx_valid;
    reg  [7:0] spi_tx_data;

    spi_target #( .WIDTH(8) ) u_spi_target (
        .i_clk(clk),
        .i_rst_n(internal_rst_n),
        .i_enable(1'b1),
        .i_ss_n(spi_ss_n),
        .i_sck(spi_sck),
        .i_mosi(spi_mosi),
        .o_miso(spi_miso),
        .o_miso_oe(spi_miso_en),
        .o_rx_data(spi_rx_data),
        .o_rx_data_valid(spi_rx_valid),
        .i_tx_data(spi_tx_data),
        .o_tx_data_hold()
    );

    // -------------------------------------------------------------------------
    // Synchronize SS_N for frame demarcation
    // -------------------------------------------------------------------------
    reg [1:0] ss_sync;
    wire ss_falling;
    wire ss_rising;

    always @(posedge clk or negedge internal_rst_n) begin
        if (!internal_rst_n) begin
            ss_sync <= 2'b11;
        end else begin
            ss_sync <= {ss_sync[0], spi_ss_n};
        end
    end

    assign ss_falling =  ss_sync[1] & ~ss_sync[0];
    assign ss_rising  = ~ss_sync[1] &  ss_sync[0];

    // -------------------------------------------------------------------------
    // Protocol Registers & State Machine
    // -------------------------------------------------------------------------
    reg [1:0]  byte_index;
    reg [7:0]  rx_cmd;
    reg [7:0]  rx_sensor;
    reg [7:0]  rx_speed;
    reg [7:0]  rx_parity;

    // Configurable PID gains (Default: Kp=32, Ki=2, Kd=48)
    reg [7:0]  kp_reg = 8'd32;
    reg [7:0]  ki_reg = 8'd2;
    reg [7:0]  kd_reg = 8'd48;

    // Heartbeat and diagnostic counter
    reg [24:0] heartbeat_cnt = 25'd0;
    reg        heartbeat_bit = 1'b0;

    always @(posedge clk) begin
        heartbeat_cnt <= heartbeat_cnt + 1'b1;
        if (heartbeat_cnt == 25'd25_000_000) begin
            heartbeat_cnt <= 25'd0;
            heartbeat_bit <= ~heartbeat_bit;
        end
    end

    // Line Position & PID Wires
    wire [7:0]        w_line_error;
    wire              w_line_lost;
    wire              w_last_dir;
    wire signed [7:0] w_steer_out;
    wire              w_inter_sat;
    wire              w_steer_sat;
    wire [7:0]        w_pwm_left;
    wire [7:0]        w_pwm_right;
    reg               pid_sample_tick;
    reg               parity_error_flag;

    // Status Byte Assembly
    wire [7:0] w_status_byte = {
        heartbeat_bit,          // Bit 7: Heartbeat
        w_line_lost,            // Bit 6: Line lost
        w_inter_sat,            // Bit 5: Integral saturated
        w_steer_sat,            // Bit 4: Steering saturated
        parity_error_flag,      // Bit 3: Parity error
        w_last_dir,             // Bit 2: Last known direction (0=L, 1=R)
        2'b00                   // Bit 1:0: Reserved
    };

    // 4-byte SPI Frame Dispatcher
    always @(posedge clk or negedge internal_rst_n) begin
        if (!internal_rst_n) begin
            byte_index        <= 2'd0;
            rx_cmd            <= 8'h10;
            rx_sensor         <= 8'h00;
            rx_speed          <= 8'd100;
            rx_parity         <= 8'h00;
            spi_tx_data       <= 8'h00;
            pid_sample_tick   <= 1'b0;
            parity_error_flag <= 1'b0;
        end else begin
            pid_sample_tick <= 1'b0;

            if (ss_falling) begin
                byte_index  <= 2'd0;
                spi_tx_data <= w_status_byte; // Pre-load Byte 0 on SS assertion
            end else if (spi_rx_valid) begin
                case (byte_index)
                    2'd0: begin
                        rx_cmd      <= spi_rx_data;
                        spi_tx_data <= w_pwm_left;     // Output for Byte 1
                        byte_index  <= 2'd1;
                    end
                    2'd1: begin
                        rx_sensor   <= spi_rx_data;
                        spi_tx_data <= w_pwm_right;    // Output for Byte 2
                        byte_index  <= 2'd2;
                    end
                    2'd2: begin
                        rx_speed    <= spi_rx_data;
                        spi_tx_data <= w_line_error;  // Output for Byte 3
                        byte_index  <= 2'd3;
                    end
                    2'd3: begin
                        rx_parity   <= spi_rx_data;
                        byte_index  <= 2'd0;

                        // Check XOR Parity
                        if (spi_rx_data == (rx_cmd ^ rx_sensor ^ rx_speed)) begin
                            parity_error_flag <= 1'b0;
                            // Command Decoding
                            case (rx_cmd)
                                8'h10: begin // Normal Run Mode
                                    pid_sample_tick <= 1'b1;
                                end
                                8'h20: begin // Set Kp
                                    kp_reg <= rx_sensor;
                                end
                                8'h21: begin // Set Ki
                                    ki_reg <= rx_sensor;
                                end
                                8'h22: begin // Set Kd
                                    kd_reg <= rx_sensor;
                                end
                                8'hFF: begin // Reset PID Gains
                                    kp_reg <= 8'd32;
                                    ki_reg <= 8'd2;
                                    kd_reg <= 8'd48;
                                end
                            endcase
                        end else begin
                            parity_error_flag <= 1'b1;
                        end
                    end
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Line Position Centroid Encoder (Supports 8 Separate Inputs)
    // -------------------------------------------------------------------------
    // Select input: Direct PMOD hardware pins (Cmd 0x11) or MCU SPI bus (Cmd 0x10)
    wire [7:0] w_sensor_source = (rx_cmd == 8'h11) ? direct_sensor_pins : rx_sensor;

    line_position_encoder u_encoder (
        .clk(clk),
        .rst_n(internal_rst_n),
        .sensor_bits(w_sensor_source),
        .error_out(w_line_error),
        .line_lost(w_line_lost),
        .last_dir(w_last_dir)
    );

    // -------------------------------------------------------------------------
    // Fixed-Point PID Controller
    // -------------------------------------------------------------------------
    pid_controller #(
        .SCALE_SHIFT(4),
        .IMAX(16'sh01FF)
    ) u_pid (
        .clk(clk),
        .rst_n(internal_rst_n),
        .sample_tick(pid_sample_tick),
        .error_in(w_line_error),
        .line_lost(w_line_lost),
        .kp(kp_reg),
        .ki(ki_reg),
        .kd(kd_reg),
        .steer_out(w_steer_out),
        .inter_sat(w_inter_sat),
        .steer_sat(w_steer_sat)
    );

    // -------------------------------------------------------------------------
    // Differential Motor Mixer
    // -------------------------------------------------------------------------
    motor_mixer #(
        .SEARCH_SPEED(8'd60)
    ) u_mixer (
        .clk(clk),
        .rst_n(internal_rst_n),
        .base_speed(rx_speed),
        .steer_in(w_steer_out),
        .line_lost(w_line_lost),
        .last_dir(w_last_dir),
        .pwm_left(w_pwm_left),
        .pwm_right(w_pwm_right)
    );

    // Drive User LED: ON when line detected, blinks heartbeat when lost
    assign led = w_line_lost ? heartbeat_bit : 1'b1;

endmodule
