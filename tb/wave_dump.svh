// Waveform dump helper for Synopsys VCS (FSDB) and Cadence Xcelium (SHM)

initial begin
    // Synopsys VCS / Verdi
    `ifdef VCS
        $display("[WAVE_DUMP] Dumping FSDB waveform -> novas.fsdb");
        $fsdbDumpfile("novas.fsdb");
        $fsdbDumpvars(0, tb);
        $fsdbDumpSVA;
        $fsdbDumpflush;
    `endif

    // Cadence Xcelium / SimVision
    `ifdef INCI
        $display("[WAVE_DUMP] Dumping SHM waveform -> xcelium_work/shm/tb.shm");
        $shm_open("xcelium_work/shm/tb.shm");
        $shm_probe("ACMTF");
    `endif
end
