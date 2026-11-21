`timescale 1ns/1ps
// Simple AXI4-Full Memory Slave
// 256x32-bit internal memory array (valid byte address range: 0x000 .. 0x3FC).
// Supports FIXED, INCR, and WRAP bursts, byte-lane WSTRB, and OKAY/DECERR responses.

module axi4_slave (
    input  logic        aclk,
    input  logic        aresetn,

    // Write Address Channel (AW)
    input  logic [31:0] awaddr,
    input  logic [7:0]  awlen,
    input  logic [2:0]  awsize,
    input  logic [1:0]  awburst,
    input  logic        awvalid,
    output logic        awready,

    // Write Data Channel (W)
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        wlast,
    input  logic        wvalid,
    output logic        wready,

    // Write Response Channel (B)
    output logic [1:0]  bresp,
    output logic        bvalid,
    input  logic        bready,

    // Read Address Channel (AR)
    input  logic [31:0] araddr,
    input  logic [7:0]  arlen,
    input  logic [2:0]  arsize,
    input  logic [1:0]  arburst,
    input  logic        arvalid,
    output logic        arready,

    // Read Data Channel (R)
    output logic [31:0] rdata,
    output logic [1:0]  rresp,
    output logic        rlast,
    output logic        rvalid,
    input  logic        rready
);

    // 256 words x 32-bit memory (0x0000_0000 to 0x0000_03FC)
    logic [31:0] mem [0:255];

    // Calculate next beat address based on burst type
    function automatic logic [31:0] calc_next_addr(
        input logic [31:0] cur_addr,
        input logic [1:0]  burst_type,
        input logic [7:0]  burst_len
    );
        logic [31:0] wrap_bytes;
        logic [31:0] wrap_base;
        case (burst_type)
            2'b00: begin // FIXED
                return cur_addr;
            end
            2'b01: begin // INCR
                return cur_addr + 32'd4;
            end
            2'b10: begin // WRAP
                wrap_bytes = (32'(burst_len) + 32'd1) * 32'd4;
                wrap_base  = (cur_addr / wrap_bytes) * wrap_bytes;
                if ((cur_addr + 32'd4) >= (wrap_base + wrap_bytes))
                    return wrap_base;
                else
                    return cur_addr + 32'd4;
            end
            default: return cur_addr + 32'd4;
        endcase
    endfunction

    // Slave Write FSM
    typedef enum logic [1:0] {
        SW_IDLE = 2'b00,
        SW_ADDR = 2'b01,
        SW_DATA = 2'b10,
        SW_RESP = 2'b11
    } sw_state_e;

    sw_state_e   sw_state;
    logic [31:0] w_cur_addr;
    logic [7:0]  saved_awlen;
    logic [1:0]  saved_awburst;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            sw_state      <= SW_IDLE;
            awready       <= 1'b0;
            wready        <= 1'b0;
            bvalid        <= 1'b0;
            bresp         <= 2'b00;
            w_cur_addr    <= 32'd0;
            saved_awlen   <= 8'd0;
            saved_awburst <= 2'b01;
            for (int i = 0; i < 256; i++) begin
                mem[i] <= 32'd0;
            end
        end else begin
            case (sw_state)
                SW_IDLE: begin
                    if (awvalid) begin
                        awready  <= 1'b1;
                        sw_state <= SW_ADDR;
                    end
                end

                // Latch AW request and transition to SW_DATA
                SW_ADDR: begin
                    if (awvalid && awready) begin
                        w_cur_addr    <= awaddr;
                        saved_awlen   <= awlen;
                        saved_awburst <= awburst;
                        awready       <= 1'b0;
                        wready        <= 1'b0; // Wait 1 cycle after seeing WVALID before asserting WREADY
                        sw_state      <= SW_DATA;
                    end
                end

                // Assert WREADY after seeing WVALID, then write active byte lanes per beat
                SW_DATA: begin
                    if (wvalid && !wready) begin
                        wready <= 1'b1;
                    end else if (wvalid && wready) begin
                        if (w_cur_addr < 32'h0000_0400) begin
                            if (wstrb[0]) mem[w_cur_addr[9:2]][ 7: 0] <= wdata[ 7: 0];
                            if (wstrb[1]) mem[w_cur_addr[9:2]][15: 8] <= wdata[15: 8];
                            if (wstrb[2]) mem[w_cur_addr[9:2]][23:16] <= wdata[23:16];
                            if (wstrb[3]) mem[w_cur_addr[9:2]][31:24] <= wdata[31:24];
                        end

                        w_cur_addr <= calc_next_addr(w_cur_addr, saved_awburst, saved_awlen);

                        if (wlast) begin
                            wready   <= 1'b0;
                            bvalid   <= 1'b1;
                            // Return DECERR (2'b11) if address is out of range (>= 0x400)
                            bresp    <= (w_cur_addr >= 32'h0000_0400) ? 2'b11 : 2'b00;
                            sw_state <= SW_RESP;
                        end
                    end
                end

                SW_RESP: begin
                    if (bvalid && bready) begin
                        bvalid   <= 1'b0;
                        sw_state <= SW_IDLE;
                    end
                end
            endcase
        end
    end

    // Slave Read FSM
    typedef enum logic [1:0] {
        SR_IDLE = 2'b00,
        SR_ADDR = 2'b01,
        SR_DATA = 2'b10
    } sr_state_e;

    sr_state_e   sr_state;
    logic [31:0] r_cur_addr;
    logic [7:0]  saved_arlen;
    logic [1:0]  saved_arburst;
    logic [7:0]  r_beat_cnt;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            sr_state      <= SR_IDLE;
            arready       <= 1'b0;
            rvalid        <= 1'b0;
            rdata         <= 32'd0;
            rresp         <= 2'b00;
            rlast         <= 1'b0;
            r_cur_addr    <= 32'd0;
            saved_arlen   <= 8'd0;
            saved_arburst <= 2'b01;
            r_beat_cnt    <= 8'd0;
        end else begin
            case (sr_state)
                SR_IDLE: begin
                    if (arvalid) begin
                        arready  <= 1'b1;
                        sr_state <= SR_ADDR;
                    end
                end

                // Latch AR request and drive first read beat (beat 0)
                SR_ADDR: begin
                    if (arvalid && arready) begin
                        logic [31:0] next_r_addr;
                        next_r_addr   = calc_next_addr(araddr, arburst, arlen);

                        arready       <= 1'b0;
                        r_cur_addr    <= next_r_addr;
                        saved_arlen   <= arlen;
                        saved_arburst <= arburst;
                        r_beat_cnt    <= 8'd0;

                        rvalid        <= 1'b1;
                        rdata         <= (araddr < 32'h0000_0400) ? mem[araddr[9:2]] : 32'hDEAD_BEEF;
                        rresp         <= (araddr < 32'h0000_0400) ? 2'b00 : 2'b11;
                        rlast         <= (arlen == 8'd0);
                        sr_state      <= SR_DATA;
                    end
                end

                // Drive remaining read beats until RLAST handshake completes
                SR_DATA: begin
                    if (rvalid && rready) begin
                        if (rlast) begin
                            rvalid   <= 1'b0;
                            rlast    <= 1'b0;
                            sr_state <= SR_IDLE;
                        end else begin
                            r_beat_cnt <= r_beat_cnt + 8'd1;
                            rdata      <= (r_cur_addr < 32'h0000_0400) ? mem[r_cur_addr[9:2]] : 32'hDEAD_BEEF;
                            rresp      <= (r_cur_addr < 32'h0000_0400) ? 2'b00 : 2'b11;
                            r_cur_addr <= calc_next_addr(r_cur_addr, saved_arburst, saved_arlen);
                            rlast      <= ((r_beat_cnt + 8'd1) == saved_arlen);
                        end
                    end
                end

                default: sr_state <= SR_IDLE;
            endcase
        end
    end

endmodule
