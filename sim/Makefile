# ==============================================================================
# AXI4-Full SVA Verification Makefile (Synopsys VCS/Verdi & Cadence Xcelium)
# ==============================================================================

VCS       ?= vcs
VERDI     ?= verdi
URG       ?= urg
XRUN      ?= xrun
SIMVISION ?= simvision

TOP       ?= tb
COV       ?= 0
PLUSARGS  ?=

SYN_WORK  := ./work_vcs
CAD_WORK  := ./xcelium_work

VCS_FLAGS := -full64 -sverilog -timescale=1ns/1ps -kdb -lca \
             -debug_acc+all+dmptf +define+VCS \
             -f rtl.f -f tb.f -top $(TOP) \
             -Mdir=$(SYN_WORK)/csrc -o $(SYN_WORK)/simv \
             -l $(SYN_WORK)/compile.log

ifeq ($(COV),1)
VCS_FLAGS += -cm line+fsm+branch+cond+tgl+assert -cm_dir $(SYN_WORK)/simv.vdb
endif

XRUN_FLAGS := -64bit -sv -timescale 1ns/1ps -access +rwc -abvcoveron \
              -define INCI -f rtl.f -f tb.f -top $(TOP) \
              -xmlibdirname $(CAD_WORK)/xcelium.d \
              -l $(CAD_WORK)/xrun.log

.PHONY: help vcs_run vcs_verdi vcs_cov cad_run cad_simvision clean

help:
	@echo "Targets:"
	@echo "  make vcs_run        - Compile & run simulation with Synopsys VCS (COV=1 for coverage)"
	@echo "  make vcs_verdi      - Open FSDB waveform & SVA results in Synopsys Verdi"
	@echo "  make vcs_cov        - Generate URG HTML/text coverage report (requires COV=1)"
	@echo "  make cad_run        - Compile & run simulation with Cadence Xcelium"
	@echo "  make cad_simvision  - Open SHM waveform in Cadence SimVision"
	@echo "  make clean          - Remove all simulation build & waveform outputs"

vcs_run:
	@mkdir -p $(SYN_WORK)
	$(VCS) $(VCS_FLAGS)
	cd $(SYN_WORK) && ./simv +fsdb+autoflush +fsdb+sva_success $(PLUSARGS) -l sim.log

vcs_verdi:
	cd $(SYN_WORK) && $(VERDI) -dbdir simv.daidir -ssf novas.fsdb &

vcs_cov:
	$(URG) -dir $(SYN_WORK)/simv.vdb -format both -report $(SYN_WORK)/urgReport

cad_run:
	@mkdir -p $(CAD_WORK)/shm
	$(XRUN) $(XRUN_FLAGS) $(PLUSARGS)

cad_simvision:
	$(SIMVISION) $(CAD_WORK)/shm/tb.shm &

clean:
	rm -rf $(SYN_WORK) $(CAD_WORK) csrc verdiLog novas.rc novas.conf .fsm*.xml *.log ucli.key DVEfiles
