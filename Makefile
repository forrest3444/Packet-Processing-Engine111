SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

###############################################################################
# Project / Test Configuration
###############################################################################
DUT_TB_TOP       := tb_top_sv
DUT_FILELIST     := ./script/filelist_sv.f
DUT_RTL_FILELIST := ./rtl/filelist.f
DUT_RTL_TOP      := PPE_TOP_SV
DUT_RTL_LANGUAGE := 1800-2017

TB_TOP     ?= $(DUT_TB_TOP)
TESTNAME   ?= ppe_basic_test
SEED       ?= 1
VERB       ?= UVM_MEDIUM
RUN_TIME   ?= 60s
BUILD_NAME ?= default
RUN_TAG    ?= $(TESTNAME)_seed_$(SEED)

REGRESS_BUILD_NAME ?= regression
REGRESS_FUNC_SEEDS ?= 1 23
REGRESS_PERF_SEEDS ?= 1

SIM       ?= sim
BUILD_DIR := $(SIM)/build/$(BUILD_NAME)
RUN_DIR   := $(SIM)/run/$(RUN_TAG)
BUILD_LOG_DIR := $(BUILD_DIR)/log
RUN_LOG_DIR   := $(RUN_DIR)/log
SIMV_DIR      := $(BUILD_DIR)/simv
SIMV_IMAGE    := $(SIMV_DIR)/$(TB_TOP).simv

FILELIST ?= $(DUT_FILELIST)
RTL_FILELIST ?= $(DUT_RTL_FILELIST)
RTL_TOP ?= $(DUT_RTL_TOP)
USER_SIM_OPTS ?=
WAVE          ?= none
FSDB_FILE     ?= $(RUN_DIR)/waves.fsdb

###############################################################################
# Tools / Options
###############################################################################
VCS       ?= vcs
VERILATOR ?= verilator
TIMESCALE ?= 1ns/1ps

ORFS_ROOT       ?= /home/wwh/github/OpenROAD-flow-scripts
ORFS_IMAGE      ?= openroad/orfs:latest
ORFS_WORK_HOME  ?= /work/flow/orfs/work
ORFS_FLOW_MAKE  := /OpenROAD-flow-scripts/flow/Makefile
ORFS_DOCKER     := $(ORFS_ROOT)/flow/util/docker_shell --image $(ORFS_IMAGE)

VCS_OPTS = -full64                 \
           -sverilog               \
           -timescale=$(TIMESCALE) \
           -ntb_opts uvm-1.2       \
           +define+UVM_DISABLE_AUTO_ITEM_RECORDING \
           -nc

SIM_OPTS = +ntb_random_seed=$(SEED)  \
           +UVM_TESTNAME=$(TESTNAME) \
           +UVM_VERBOSITY=$(VERB)    \
	   $(USER_SIM_OPTS)

ifeq ($(WAVE),fsdb)
VERDI_PLI_DIR ?= $(VERDI_HOME)/share/PLI/VCS/linux64
VCS_OPTS += -debug_access+all -kdb +define+PPE_FSDB \
            -P $(VERDI_PLI_DIR)/novas.tab $(VERDI_PLI_DIR)/pli.a
SIM_OPTS += +FSDB +FSDB_FILE=$(FSDB_FILE)
endif

VERILATOR_LINT_OPTS = --lint-only       \
                      --language $(DUT_RTL_LANGUAGE) \
                      --Wall            \
                      -Wno-fatal        \
                      -Wno-DECLFILENAME \
                      --top-module $(RTL_TOP)

define orfs_synth
	sg docker -c '$(ORFS_DOCKER) make --file=$(ORFS_FLOW_MAKE) DESIGN_CONFIG=/work/flow/orfs/config/$(1) WORK_HOME=$(ORFS_WORK_HOME) synth'
endef

define orfs_module_report
	sg docker -c '$(ORFS_DOCKER) env REPORT_DB=$(ORFS_WORK_HOME)/results/nangate45/$(1)/base/1_synth.odb REPORT_SDC=/work/flow/orfs/constraints/$(2) REPORT_OUT=/work/flow/orfs/reports/$(3) REPORT_NAME=$(4) openroad -exit /work/flow/orfs/scripts/report_module_1p25ghz.tcl'
endef

###############################################################################
# Targets
###############################################################################
.PHONY: all prepare_build prepare_run check_elab lint elab run sim sim-fsdb \
	regress regress-functional regress-performance \
	synth synth-top synth-modules synth-ingress synth-scheduler synth-rob \
	synth-retire-output clean clean_all help

all: sim

lint:
	$(VERILATOR) $(VERILATOR_LINT_OPTS) -f $(RTL_FILELIST)

prepare_build:
	mkdir -p $(BUILD_LOG_DIR) $(SIMV_DIR)

prepare_run:
	mkdir -p $(RUN_LOG_DIR)

check_elab:
	@if [ ! -x "$(SIMV_IMAGE)" ]; then \
	  echo "Elaboration output not found: $(SIMV_IMAGE)"; \
	  echo "Run 'make elab BUILD_NAME=$(BUILD_NAME)' first."; \
	  exit 1; \
	fi

elab: prepare_build
	$(VCS) $(VCS_OPTS)       \
	      -f $(FILELIST)     \
	      -top $(TB_TOP)     \
	      -o $(SIMV_IMAGE)   \
	      -l $(BUILD_LOG_DIR)/compile.log

run: check_elab prepare_run
	timeout $(RUN_TIME) $(SIMV_IMAGE) \
	      $(SIM_OPTS)                 \
	      -l $(RUN_LOG_DIR)/run.log

sim: elab run

sim-fsdb:
	$(MAKE) sim WAVE=fsdb BUILD_NAME=fsdb

regress:
	BUILD_NAME="$(REGRESS_BUILD_NAME)" \
	FUNC_SEEDS="$(REGRESS_FUNC_SEEDS)" \
	PERF_SEEDS="$(REGRESS_PERF_SEEDS)" \
	RUN_TIME="$(RUN_TIME)" VERB="$(VERB)" \
	./script/run_regression.sh all

regress-functional:
	BUILD_NAME="$(REGRESS_BUILD_NAME)" \
	FUNC_SEEDS="$(REGRESS_FUNC_SEEDS)" \
	RUN_TIME="$(RUN_TIME)" VERB="$(VERB)" \
	./script/run_regression.sh functional

regress-performance:
	BUILD_NAME="$(REGRESS_BUILD_NAME)" \
	PERF_SEEDS="$(REGRESS_PERF_SEEDS)" \
	RUN_TIME="$(RUN_TIME)" VERB="$(VERB)" \
	./script/run_regression.sh performance

synth: synth-top

synth-top:
	$(call orfs_synth,config_top_sv_1p25ghz.mk)
	sg docker -c '$(ORFS_DOCKER) openroad -exit /work/flow/orfs/scripts/report_top_sv_1p25ghz_functional.tcl'

synth-modules: synth-ingress synth-scheduler synth-rob synth-retire-output

synth-ingress:
	$(call orfs_synth,config_ingress_1p25ghz.mk)
	$(call orfs_module_report,ppe_ingress_1p25ghz,constraint_ingress_1p25ghz.sdc,ppe_ingress_current_1p25ghz_timing.rpt,PPE_INGRESS)

synth-scheduler:
	$(call orfs_synth,config_scheduler_local_pairs_1p25ghz.mk)
	sg docker -c '$(ORFS_DOCKER) openroad -exit /work/flow/orfs/scripts/report_scheduler_local_pairs_1p25ghz.tcl'

synth-rob:
	$(call orfs_synth,config_rob_1p25ghz.mk)
	$(call orfs_module_report,ppe_rob_1p25ghz,constraint_rob_1p25ghz.sdc,ppe_rob_current_1p25ghz_timing.rpt,PPE_ROB)

synth-retire-output:
	$(call orfs_synth,config_retire_output_1p25ghz.mk)
	$(call orfs_module_report,ppe_retire_output_1p25ghz,constraint_retire_output_1p25ghz.sdc,ppe_retire_output_current_1p25ghz_timing.rpt,PPE_RETIRE_OUTPUT)

clean:
	rm -rf $(SIM)/run

clean_all:
	rm -rf $(SIM) verdiLog csrc *.daidir vc_hdrs.h ucli.key novas.conf novas_dump.log novas.rc tr_db.log

help:
	@echo "Targets:"
	@echo "  make lint    Lint the selected DUT RTL with Verilator"
	@echo "  make elab    Compile/elaborate UVM testbench"
	@echo "  make run     Run existing elaboration"
	@echo "  make sim     Compile and run"
	@echo "  make sim-fsdb Compile and run with FSDB waveform dumping"
	@echo "  make regress-functional  Run multi-seed functional regression"
	@echo "  make regress-performance Run peak, random-delay, and mixed-load tests"
	@echo "  make regress             Run functional and performance regressions"
	@echo "  make synth               Synthesize the 1.25 GHz top and refresh its report"
	@echo "  make synth-top           Synthesize the 1.25 GHz top and refresh its report"
	@echo "  make synth-modules       Synthesize all standalone 1.25 GHz RTL modules"
	@echo "  make synth-ingress       Synthesize ingress at 1.25 GHz"
	@echo "  make synth-scheduler     Synthesize scheduler at 1.25 GHz"
	@echo "  make synth-rob           Synthesize ROB at 1.25 GHz"
	@echo "  make synth-retire-output Synthesize retire output at 1.25 GHz"
	@echo "Variables:"
	@echo "  VERILATOR=$(VERILATOR) RTL_FILELIST=$(RTL_FILELIST) RTL_TOP=$(RTL_TOP)"
	@echo "  TESTNAME=$(TESTNAME) SEED=$(SEED) VERB=$(VERB) BUILD_NAME=$(BUILD_NAME) RUN_TAG=$(RUN_TAG)"
	@echo "  WAVE=$(WAVE) FSDB_FILE=$(FSDB_FILE) VERDI_HOME=$(VERDI_HOME)"
	@echo "  REGRESS_BUILD_NAME=$(REGRESS_BUILD_NAME) REGRESS_FUNC_SEEDS='$(REGRESS_FUNC_SEEDS)' REGRESS_PERF_SEEDS='$(REGRESS_PERF_SEEDS)'"
	@echo "  ORFS_ROOT=$(ORFS_ROOT) ORFS_IMAGE=$(ORFS_IMAGE) ORFS_WORK_HOME=$(ORFS_WORK_HOME)"
