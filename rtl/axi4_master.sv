`timescale 1ns/1ps
// Simple AXI4-Full Master
// Drives AW, W, B, AR, and R channels using independent Write and Read FSMs.

module axi4_master (
    input  logic        aclk,
    input  logic        aresetn,

    // Control inputs from testbench
    input  logic        start_write,
    input  logic        start_read,
    input  logic [31:0] in_addr,
    input  logic [7:0]  in_len,    // beats = in_len + 1
    input  logic [1:0]  in_burst,  // 2'b00: FIXED, 2'b01: INCR, 2'b10: WRAP
    input  logic [3:0]  in_wstrb,  // byte lane write strobe
    input  logic [31:0] in_wdata,  // base write data (incremented by 1 per beat)

    // Write Address Channel (AW)
    output logic [31:0] awaddr,
    output logic [7:0]  awlen,
    output logic [2:0]  awsize,
    output logic [1:0]  awburst,
    output logic        awvalid,
    input  logic        awready,

    // Write Data Channel (W)
    output logic [31:0] wdata,
    output logic [3:0]  wstrb,
    output logic        wlast,
    output logic        wvalid,
    input  logic        wready,

    // Write Response Channel (B)
    input  logic [1:0]  bresp,
    input  logic        bvalid,
    output logic        bready,

    // Read Address Channel (AR)
    output logic [31:0] araddr,
    output logic [7:0]  arlen,
    output logic [2:0]  arsize,
    output logic [1:0]  arburst,
    output logic        arvalid,
    input  logic        arready,

    // Read Data Channel (R)
    input  logic [31:0] rdata,
    input  logic [1:0]  rresp,
    input  logic        rlast,
    input  logic        rvalid,
    output logic        rready
);

    // Write FSM (AW -> W -> B)
    typedef enum logic [1:0] {
        W_IDLE = 2'b00,
        W_ADDR = 2'b01,
        W_DATA = 2'b10,
        W_RESP = 2'b11
    } w_state_e;

    w_state_e    w_state;
    logic [7:0]  saved_awlen;
    logic [7:0]  w_beat_cnt;
    logic [31:0] saved_wdata;
    logic [3:0]  saved_wstrb;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            w_state     <= W_IDLE;
            awaddr      <= 32'd0;
            awlen       <= 8'd0;
            awsize      <= 3'b010; // 4 bytes (32-bit)
            awburst     <= 2'b01;  // INCR
            awvalid     <= 1'b0;
            wdata       <= 32'd0;
            wstrb       <= 4'b0000;
            wlast       <= 1'b0;
            wvalid      <= 1'b0;
            bready      <= 1'b0;
            saved_awlen <= 8'd0;
            w_beat_cnt  <= 8'd0;
            saved_wdata <= 32'd0;
            saved_wstrb <= 4'b1111;
        end else begin
            case (w_state)
                W_IDLE: begin
                    if (start_write) begin
                        awaddr      <= in_addr;
                        awlen       <= in_len;
                        awsize      <= 3'b010; // 4 bytes
                        awburst     <= in_burst;
                        awvalid     <= 1'b1;
                        saved_awlen <= in_len;
                        saved_wdata <= in_wdata;
                        saved_wstrb <= in_wstrb;
                        w_beat_cnt  <= 8'd0;
                        w_state     <= W_ADDR;
                    end
                end

                // Hold AW signals stable until slave asserts AWREADY
                W_ADDR: begin
                    if (awvalid && awready) begin
                        awvalid <= 1'b0;
                        // Drive first write beat (beat 0)
                        wvalid  <= 1'b1;
                        wdata   <= saved_wdata;
                        wstrb   <= saved_wstrb;
                        wlast   <= (saved_awlen == 8'd0);
                        w_state <= W_DATA;
                    end
                end

                // Send write beats until WLAST handshake completes
                W_DATA: begin
                    if (wvalid && wready) begin
                        if (wlast) begin
                            wvalid  <= 1'b0;
                            wlast   <= 1'b0;
                            wstrb   <= 4'b0000;
                            bready  <= 1'b0; // Wait for BVALID before asserting BREADY
                            w_state <= W_RESP;
                        end else begin
                            w_beat_cnt <= w_beat_cnt + 8'd1;
                            wdata      <= wdata + 32'd1;
                            wlast      <= ((w_beat_cnt + 8'd1) == saved_awlen);
                        end
                    end
                end

                // Wait for BVALID, assert BREADY on next cycle to complete handshake
                W_RESP: begin
                    if (bvalid && !bready) begin
                        bready <= 1'b1;
                    end else if (bvalid && bready) begin
                        bready  <= 1'b0;
                        w_state <= W_IDLE;
                    end
                end
            endcase
        end
    end

    // Read FSM (AR -> R)
    typedef enum logic [1:0] {
        R_IDLE = 2'b00,
        R_ADDR = 2'b01,
        R_DATA = 2'b10
    } r_state_e;

    r_state_e r_state;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            r_state <= R_IDLE;
            araddr  <= 32'd0;
            arlen   <= 8'd0;
            arsize  <= 3'b010; // 4 bytes
            arburst <= 2'b01;  // INCR
            arvalid <= 1'b0;
            rready  <= 1'b0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    if (start_read) begin
                        araddr  <= in_addr;
                        arlen   <= in_len;
                        arsize  <= 3'b010;
                        arburst <= in_burst;
                        arvalid <= 1'b1;
                        r_state <= R_ADDR;
                    end
                end

                // Hold AR signals stable until slave asserts ARREADY
                R_ADDR: begin
                    if (arvalid && arready) begin
                        arvalid <= 1'b0;
                        rready  <= 1'b0; // Wait 1 cycle after RVALID before asserting RREADY
                        r_state <= R_DATA;
                    end
                end

                // Assert RREADY after seeing RVALID, then accept beats until RLAST
                R_DATA: begin
                    if (rvalid && !rready) begin
                        rready <= 1'b1;
                    end else if (rvalid && rready) begin
                        if (rlast) begin
                            rready  <= 1'b0;
                            r_state <= R_IDLE;
                        end
                    end
                end

                default: r_state <= R_IDLE;
            endcase
        end
    end

endmodule
