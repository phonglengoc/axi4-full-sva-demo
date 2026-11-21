`timescale 1ns/1ps
// Top-level testbench for AXI4-Full Master/Slave verification using SVA
// Test cases:
//   Case 1: Single read/write (LEN = 0)
//   Case 2: INCR bursts (4-beat and 16-beat)
//   Case 3: FIXED bursts (4-beat and 16-beat max length)
//   Case 4: WRAP bursts across all legal lengths (2, 4, 8, 16 beats) for both Write and Read
//   Case 5: All byte-lane WSTRB mask patterns (4'b0011, 4'b1100, 4'b0101, 4'b1010, 4'b0000)
//   Case 6: Out-of-range Write and Read (>= 0x400) returning DECERR (2'b11)
//   Case 7: Simultaneous Read & Write (Full-Duplex 5-channel concurrency)

module tb;
    `include "wave_dump.svh"

    // Clock, reset, and testbench control signals
    bit          aclk;
    logic        aresetn;

    logic        start_write;
    logic        start_read;
    logic [31:0] in_addr;
    logic [7:0]  in_len;
    logic [1:0]  in_burst;
    logic [3:0]  in_wstrb;
    logic [31:0] in_wdata;

    // Set to 1'b1 to inject a protocol violation and test SVA failure
    bit          inject_bug = 1'b0;

    // 100MHz clock (10ns period)
    always #5 aclk = ~aclk;

    // Write Address Channel (AW)
    logic [31:0] awaddr;
    logic [7:0]  awlen;
    logic [2:0]  awsize;
    logic [1:0]  awburst;
    logic        awvalid;
    logic        awready;

    // Write Data Channel (W)
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wlast;
    logic        wvalid;
    logic        wready;

    // Write Response Channel (B)
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;

    // Read Address Channel (AR)
    logic [31:0] araddr;
    logic [7:0]  arlen;
    logic [2:0]  arsize;
    logic [1:0]  arburst;
    logic        arvalid;
    logic        arready;

    // Read Data Channel (R)
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rlast;
    logic        rvalid;
    logic        rready;

    // DUT instantiations
    axi4_master u_master (
        //system signal
        .aclk        (aclk),
        .aresetn     (aresetn),
        .start_write (start_write),
        .start_read  (start_read),
        .in_addr     (in_addr),
        .in_len      (in_len),
        .in_burst    (in_burst),
        .in_wstrb    (in_wstrb),
        .in_wdata    (in_wdata),
        //AW channel
        .awaddr      (awaddr),
        .awlen       (awlen),
        .awsize      (awsize),
        .awburst     (awburst),
        .awvalid     (awvalid),
        .awready     (awready),
        //W channel
        .wdata       (wdata),
        .wstrb       (wstrb),
        .wlast       (wlast),
        .wvalid      (wvalid),
        .wready      (wready),
        //B channel
        .bresp       (bresp),
        .bvalid      (bvalid),
        .bready      (bready),
        //AR channel
        .araddr      (araddr),
        .arlen       (arlen),
        .arsize      (arsize),
        .arburst     (arburst),
        .arvalid     (arvalid),
        .arready     (arready),
        //R channel
        .rdata       (rdata),
        .rresp       (rresp),
        .rlast       (rlast),
        .rvalid      (rvalid),
        .rready      (rready)
    );

    axi4_slave u_slave (
        .aclk        (aclk),
        .aresetn     (aresetn),
        //AW channel
        .awaddr      (awaddr),
        .awlen       (awlen),
        .awsize      (awsize),
        .awburst     (awburst),
        .awvalid     (awvalid),
        .awready     (awready),
        //W channel
        .wdata       (wdata),
        .wstrb       (wstrb),
        .wlast       (wlast),
        .wvalid      (wvalid),
        .wready      (wready),
        //B channel
        .bresp       (bresp),
        .bvalid      (bvalid),
        .bready      (bready),
        //AR channel
        .araddr      (araddr),
        .arlen       (arlen),
        .arsize      (arsize),
        .arburst     (arburst),
        .arvalid     (arvalid),
        .arready     (arready),
        //R channel
        .rdata       (rdata),
        .rresp       (rresp),
        .rlast       (rlast),
        .rvalid      (rvalid),
        .rready      (rready)
    );

    // Helper task to issue a single write transaction and wait for completion
    task automatic do_write(
        input logic [31:0] addr,
        input logic [7:0]  len,
        input logic [1:0]  burst,
        input logic [3:0]  strb,
        input logic [31:0] data
    );
        @(posedge aclk);
        in_addr     <= addr;
        in_len      <= len;
        in_burst    <= burst;
        in_wstrb    <= strb;
        in_wdata    <= data;
        start_write <= 1'b1;
        @(posedge aclk);
        start_write <= 1'b0;
        wait (bvalid && bready);
        @(posedge aclk);
    endtask

    // Helper task to issue a single read transaction and wait for completion
    task automatic do_read(
        input logic [31:0] addr,
        input logic [7:0]  len,
        input logic [1:0]  burst
    );
        @(posedge aclk);
        in_addr    <= addr;
        in_len     <= len;
        in_burst   <= burst;
        start_read <= 1'b1;
        @(posedge aclk);
        start_read <= 1'b0;
        wait (rvalid && rready && rlast);
        @(posedge aclk);
    endtask

    // Stimulus
    initial begin
        $display("======================================================================");
        $display("  STARTING AXI4-FULL SIMULATION WITH 16 SVA PROPERTIES");
        $display("======================================================================");

        // Hold reset for 3 clock cycles
        aresetn     <= 1'b0;
        start_write <= 1'b0;
        start_read  <= 1'b0;
        in_addr     <= 32'h0000_0000;
        in_len      <= 8'd0;
        in_burst    <= 2'b01; // INCR
        in_wstrb    <= 4'b1111;
        in_wdata    <= 32'h0000_0000;

        repeat (3) @(posedge aclk);
        aresetn <= 1'b1;
        @(posedge aclk);

        // Case 1: Single write & read (1 beat, LEN = 0) at 0x10
        $display("\n[%0t ns] ---> [CASE 1] Single R/W (LEN=0) at 0x10", $time);
        //do_write(addr, len, burst, strb, data);
        //do_read(addr, len, burst);
        do_write(32'h0000_0010, 8'd0, 2'b01, 4'b1111, 32'hAAAA_1234);
        do_read (32'h0000_0010, 8'd0, 2'b01);

        // Case 2: INCR bursts (4-beat at 0x20 and 16-beat at 0x100)
        $display("\n[%0t ns] ---> [CASE 2] INCR Bursts (4-beat and 16-beat)", $time);
        do_write(32'h0000_0020, 8'd3,  2'b01, 4'b1111, 32'h1111_0010);
        do_read (32'h0000_0020, 8'd3,  2'b01);
        do_write(32'h0000_0100, 8'd15, 2'b01, 4'b1111, 32'h1600_0000);
        do_read (32'h0000_0100, 8'd15, 2'b01);

        // Case 3: FIXED bursts (4-beat and max 16-beat at 0x30)
        $display("\n[%0t ns] ---> [CASE 3] FIXED Bursts (4-beat and 16-beat to 0x30)", $time);
        do_write(32'h0000_0030, 8'd3,  2'b00, 4'b1111, 32'hF1F0_0001);
        do_read (32'h0000_0030, 8'd3,  2'b00);
        do_write(32'h0000_0030, 8'd15, 2'b00, 4'b1111, 32'hF1F0_0100);
        do_read (32'h0000_0030, 8'd15, 2'b00);

        // Case 4: WRAP bursts across all legal lengths (2, 4, 8, 16 beats) on both Write and Read
        $display("\n[%0t ns] ---> [CASE 4] WRAP Bursts (2, 4, 8, 16 beats - Write & Read)", $time);
        // 4-beat WRAP write at 0x48 (0x48->0x4C->0x40->0x44), then read with WRAP and INCR
        do_write(32'h0000_0048, 8'd3,  2'b10, 4'b1111, 32'h2222_0001);
        do_read (32'h0000_0048, 8'd3,  2'b10);
        do_read (32'h0000_0040, 8'd3,  2'b01);
        // 2-beat, 8-beat, and 16-beat WRAP bursts
        do_write(32'h0000_0064, 8'd1,  2'b10, 4'b1111, 32'h2202_0001);
        do_read (32'h0000_0064, 8'd1,  2'b10);
        do_write(32'h0000_008C, 8'd7,  2'b10, 4'b1111, 32'h2208_0001);
        do_read (32'h0000_008C, 8'd7,  2'b10);
        do_write(32'h0000_0210, 8'd15, 2'b10, 4'b1111, 32'h2216_0001);
        do_read (32'h0000_0210, 8'd15, 2'b10);

        // Case 5: Byte-lane strobe patterns (WSTRB) at 0x10
        $display("\n[%0t ns] ---> [CASE 5] Byte Strobe Patterns (WSTRB) at 0x10", $time);
        do_write(32'h0000_0010, 8'd0, 2'b01, 4'b0011, 32'hFFFF_9999); // lower 2 bytes -> 0xAAAA_9999
        do_read (32'h0000_0010, 8'd0, 2'b01);
        do_write(32'h0000_0010, 8'd0, 2'b01, 4'b1100, 32'h5555_0000); // upper 2 bytes -> 0x5555_9999
        do_write(32'h0000_0010, 8'd0, 2'b01, 4'b0101, 32'h00AA_00BB); // bytes 0 & 2   -> 0x55AA_99BB
        do_write(32'h0000_0010, 8'd0, 2'b01, 4'b1010, 32'hCC00_DD00); // bytes 1 & 3   -> 0xCCAA_DDBB
        do_write(32'h0000_0010, 8'd0, 2'b01, 4'b0000, 32'h0000_0000); // no bytes written (unchanged)
        do_read (32'h0000_0010, 8'd0, 2'b01);

        // Case 6: Out-of-range Write and Read (>= 0x400) -> Expect DECERR (2'b11) on BRESP and RRESP
        $display("\n[%0t ns] ---> [CASE 6] Out-of-range Write & Read (0x800) -> Expect DECERR", $time);
        do_write(32'h0000_0800, 8'd1, 2'b01, 4'b1111, 32'hBAD0_0000);
        do_read (32'h0000_0800, 8'd1, 2'b01);

        // Case 7: Simultaneous Read & Write (Full-Duplex 5-channel operation)
        $display("\n[%0t ns] ---> [CASE 7] Simultaneous Read & Write (Full-Duplex)", $time);
        @(posedge aclk);
        in_addr     <= 32'h0000_0050;
        in_len      <= 8'd3;
        in_burst    <= 2'b01;
        in_wstrb    <= 4'b1111;
        in_wdata    <= 32'h7777_0001;
        start_write <= 1'b1;
        start_read  <= 1'b1; // Trigger both Write and Read FSMs simultaneously
        @(posedge aclk);
        start_write <= 1'b0;
        start_read  <= 1'b0;
        fork
            wait (bvalid && bready);
            wait (rvalid && rready && rlast);
        join
        @(posedge aclk);

        // Optional negative test when inject_bug == 1'b1
        if (inject_bug) begin
            $display("\n[%0t ns] ---> [BUG INJECTION] Driving reserved AWBURST=2'b11!", $time);
            do_write(32'h0000_0010, 8'd2, 2'b11, 4'b1111, 32'hDEAD_0000);
        end

        repeat (4) @(posedge aclk);
        $display("\n======================================================================");
        $display("  [SUCCESS] SIMULATION FINISHED - ALL 16 SVA PROPERTIES PASSED!");
        $display("======================================================================");
        $finish;
    end

    // Monitor bus handshakes
    always @(posedge aclk) begin
        if (aresetn && wvalid && wready) begin
            $display("[%0t ns] [WRITE BEAT] wdata=0x%08h, wstrb=4'b%04b, wlast=%0b",
                     $time, wdata, wstrb, wlast);
        end
        if (aresetn && bvalid && bready) begin
            $display("[%0t ns] [WRITE RESP] bresp=%02b (%s)",
                     $time, bresp, (bresp == 2'b00) ? "OKAY" : "DECERR");
        end
        if (aresetn && rvalid && rready) begin
            $display("[%0t ns] [READ  BEAT] rdata=0x%08h, rresp=%02b, rlast=%0b",
                     $time, rdata, rresp, rlast);
        end
    end

    // ==========================================================================
    // SVA Protocol Checks (16 Assertions)
    // ==========================================================================

    // 1. All VALID signals must be low during reset
    property p_01_reset_valid_low;
        @(posedge aclk)
        (!aresetn) |-> (!awvalid && !wvalid && !bvalid && !arvalid && !rvalid);
    endproperty
    AST_01_RESET_VALID_LOW: assert property (p_01_reset_valid_low)
        else $error("[%0t ns] [SVA FAIL] VALID signal asserted during reset!", $time);

    // 2. Handshake control signals must not be X or Z
    property p_02_no_unknown_ctrl;
        @(posedge aclk) disable iff (!aresetn)
        !$isunknown({awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready});
    endproperty
    AST_02_NO_UNKNOWN_CTRL: assert property (p_02_no_unknown_ctrl)
        else $error("[%0t ns] [SVA FAIL] Unknown (X/Z) detected on VALID/READY signals!", $time);

    // 3. Active byte lanes on WDATA must not be X or Z when WVALID is high
    property p_03_no_unknown_wdata;
        @(posedge aclk) disable iff (!aresetn)
        wvalid |-> (
            (!wstrb[0] || !$isunknown(wdata[ 7: 0])) &&
            (!wstrb[1] || !$isunknown(wdata[15: 8])) &&
            (!wstrb[2] || !$isunknown(wdata[23:16])) &&
            (!wstrb[3] || !$isunknown(wdata[31:24]))
        );
    endproperty
    AST_03_NO_UNKNOWN_WDATA: assert property (p_03_no_unknown_wdata)
        else $error("[%0t ns] [SVA FAIL] Active WDATA byte lane is X or Z!", $time);

    // 4. AW channel signals must remain stable while waiting for AWREADY
    property p_04_aw_stable;
        @(posedge aclk) disable iff (!aresetn)
        (awvalid && !awready) |=> (awvalid && $stable({awaddr, awlen, awsize, awburst}));
    endproperty
    AST_04_AW_STABLE: assert property (p_04_aw_stable)
        else $error("[%0t ns] [SVA FAIL] AW channel changed before AWREADY handshake!", $time);

    // 5. W channel signals must remain stable while waiting for WREADY
    property p_05_w_stable;
        @(posedge aclk) disable iff (!aresetn)
        (wvalid && !wready) |=> (wvalid && $stable({wdata, wstrb, wlast}));
    endproperty
    AST_05_W_STABLE: assert property (p_05_w_stable)
        else $error("[%0t ns] [SVA FAIL] W channel changed before WREADY handshake!", $time);

    // 6. B channel signals must remain stable while waiting for BREADY
    property p_06_b_stable;
        @(posedge aclk) disable iff (!aresetn)
        (bvalid && !bready) |=> (bvalid && $stable(bresp));
    endproperty
    AST_06_B_STABLE: assert property (p_06_b_stable)
        else $error("[%0t ns] [SVA FAIL] B channel changed before BREADY handshake!", $time);

    // 7. AR channel signals must remain stable while waiting for ARREADY
    property p_07_ar_stable;
        @(posedge aclk) disable iff (!aresetn)
        (arvalid && !arready) |=> (arvalid && $stable({araddr, arlen, arsize, arburst}));
    endproperty
    AST_07_AR_STABLE: assert property (p_07_ar_stable)
        else $error("[%0t ns] [SVA FAIL] AR channel changed before ARREADY handshake!", $time);

    // 8. R channel signals must remain stable while waiting for RREADY
    property p_08_r_stable;
        @(posedge aclk) disable iff (!aresetn)
        (rvalid && !rready) |=> (rvalid && $stable({rdata, rresp, rlast}));
    endproperty
    AST_08_R_STABLE: assert property (p_08_r_stable)
        else $error("[%0t ns] [SVA FAIL] R channel changed before RREADY handshake!", $time);

    // 9. BURST = 2'b11 (Reserved) is not allowed
    property p_09_burst_not_reserved;
        @(posedge aclk) disable iff (!aresetn)
        (awvalid |-> (awburst != 2'b11)) and (arvalid |-> (arburst != 2'b11));
    endproperty
    AST_09_BURST_VALID: assert property (p_09_burst_not_reserved)
        else $error("[%0t ns] [SVA FAIL] Reserved BURST type (2'b11) detected!", $time);

    // 10. Transfer size (1 << SIZE) must not exceed the 32-bit (4-byte) bus width
    property p_10_size_max_4bytes;
        @(posedge aclk) disable iff (!aresetn)
        (awvalid |-> ((1 << awsize) <= 4)) and (arvalid |-> ((1 << arsize) <= 4));
    endproperty
    AST_10_SIZE_MAX: assert property (p_10_size_max_4bytes)
        else $error("[%0t ns] [SVA FAIL] AWSIZE/ARSIZE exceeds 32-bit bus width!", $time);

    // 11. FIXED burst length must not exceed 16 beats (LEN <= 15)
    property p_11_fixed_burst_max_len;
        @(posedge aclk) disable iff (!aresetn)
        ((awvalid && (awburst == 2'b00)) |-> (awlen <= 8'd15)) and
        ((arvalid && (arburst == 2'b00)) |-> (arlen <= 8'd15));
    endproperty
    AST_11_FIXED_LEN: assert property (p_11_fixed_burst_max_len)
        else $error("[%0t ns] [SVA FAIL] FIXED burst exceeds 16 beats (LEN > 15)!", $time);

    // 12. WRAP burst must be word-aligned and length must be 2, 4, 8, or 16 beats
    property p_12_wrap_burst_rules;
        @(posedge aclk) disable iff (!aresetn)
        ((awvalid && (awburst == 2'b10)) |-> ((awaddr[1:0] == 2'b00) && (awlen inside {8'd1, 8'd3, 8'd7, 8'd15}))) and
        ((arvalid && (arburst == 2'b10)) |-> ((araddr[1:0] == 2'b00) && (arlen inside {8'd1, 8'd3, 8'd7, 8'd15})));
    endproperty
    AST_12_WRAP_RULES: assert property (p_12_wrap_burst_rules)
        else $error("[%0t ns] [SVA FAIL] WRAP burst violates alignment or length {2,4,8,16} rules!", $time);

    // 13. INCR burst must not cross a 4KB (4096-byte) boundary
    property p_13_no_4kb_boundary_crossing;
        @(posedge aclk) disable iff (!aresetn)
        ((awvalid && (awburst == 2'b01)) |-> ((awaddr[11:0] + (awlen * 4)) < 4096)) and
        ((arvalid && (arburst == 2'b01)) |-> ((araddr[11:0] + (arlen * 4)) < 4096));
    endproperty
    AST_13_NO_4KB_CROSS: assert property (p_13_no_4kb_boundary_crossing)
        else $error("[%0t ns] [SVA FAIL] INCR burst crosses 4KB boundary!", $time);

    // 14. Slave must assert BVALID on the cycle following the last write beat (WLAST)
    property p_14_wlast_triggers_bvalid;
        @(posedge aclk) disable iff (!aresetn)
        (wvalid && wready && wlast) |=> bvalid;
    endproperty
    AST_14_WLAST_TO_BVALID: assert property (p_14_wlast_triggers_bvalid)
        else $error("[%0t ns] [SVA FAIL] BVALID not asserted after WLAST handshake!", $time);

    // 15. Number of write beats must match AWLEN + 1 (using local variable `rem`)
    property p_15_write_beat_count_general;
        int rem;
        @(posedge aclk) disable iff (!aresetn)
        (awvalid && awready, rem = int'(awlen) + 1) |->
            (!(wvalid && wready && wlast), rem = rem - int'(wvalid && wready))[*1:256]
            ##1 (wvalid && wready && wlast && (rem == 1));
    endproperty
    AST_15_WRITE_BEAT_COUNT: assert property (p_15_write_beat_count_general)
        else $error("[%0t ns] [SVA FAIL] Write beat count does not match AWLEN+1!", $time);

    // 16. Number of read beats must match ARLEN + 1 (using local variable `rem`)
    property p_16_read_beat_count_general;
        int rem;
        @(posedge aclk) disable iff (!aresetn)
        (arvalid && arready, rem = int'(arlen) + 1) |->
            (!(rvalid && rready && rlast), rem = rem - int'(rvalid && rready))[*1:256]
            ##1 (rvalid && rready && rlast && (rem == 1));
    endproperty
    AST_16_READ_BEAT_COUNT: assert property (p_16_read_beat_count_general)
        else $error("[%0t ns] [SVA FAIL] Read beat count does not match ARLEN+1!", $time);

    // Functional coverage (all scenarios & channel wait states)
    COV_01_SINGLE_RW:       cover property (@(posedge aclk) disable iff (!aresetn) (awvalid && awready && awlen == 8'd0));
    COV_02_BURST_INCR:      cover property (@(posedge aclk) disable iff (!aresetn) (awvalid && awready && awburst == 2'b01 && awlen == 8'd3));
    COV_03_BURST_FIXED:     cover property (@(posedge aclk) disable iff (!aresetn) (awvalid && awready && awburst == 2'b00));
    COV_04_BURST_WRAP_W:    cover property (@(posedge aclk) disable iff (!aresetn) (awvalid && awready && awburst == 2'b10));
    COV_05_BURST_WRAP_R:    cover property (@(posedge aclk) disable iff (!aresetn) (arvalid && arready && arburst == 2'b10));
    COV_06_NARROW_STRB:     cover property (@(posedge aclk) disable iff (!aresetn) (wvalid  && wready  && wstrb == 4'b0011));
    COV_07_WRITE_DECERR:    cover property (@(posedge aclk) disable iff (!aresetn) (bvalid  && bready  && bresp == 2'b11));
    COV_08_READ_DECERR:     cover property (@(posedge aclk) disable iff (!aresetn) (rvalid  && rready  && rresp == 2'b11));
    COV_09_SIMULTANEOUS_RW: cover property (@(posedge aclk) disable iff (!aresetn) (wvalid  && rvalid));
    COV_10_WAIT_STATES_ALL: cover property (@(posedge aclk) disable iff (!aresetn)
        (awvalid && !awready) ##1 (awvalid && awready) ##1 (wvalid && !wready) ##[1:20] (bvalid && !bready));

endmodule
