SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

###############################################################################
# Project / Test Configuration
###############################################################################
DUT        ?= sv

ifeq ($(DUT),sv)
DUT_TB_TOP       := tb_top_sv
DUT_FILELIST     := ./script/filelist_sv.f
DUT_RTL_FILELIST := ./rtl-sv/filelist.f
DUT_RTL_TOP      := ppe_top_sv
DUT_RTL_LANGUAGE := 1800-2017
else ifeq ($(DUT),single_fe)
DUT_TB_TOP       := tb_top_single_fe
DUT_FILELIST     := ./script/filelist_single_fe.f
DUT_RTL_FILELIST := ./rtl-sv/filelist_single_fe.f
DUT_RTL_TOP      := ppe_single_fe_inorder
DUT_RTL_LANGUAGE := 1800-2017
else ifeq ($(DUT),legacy)
DUT_TB_TOP       := tb_top
DUT_FILELIST     := ./script/filelist.f
DUT_RTL_FILELIST := ./script/rtl_filelist.f
DUT_RTL_TOP      := ppe_top
DUT_RTL_LANGUAGE := 1364-2001
else
$(error DUT must be 'sv', 'single_fe', or 'legacy')
endif

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

###############################################################################
# Tools / Options
###############################################################################
VCS       ?= vcs
VERILATOR ?= verilator
TIMESCALE ?= 1ns/1ps

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

VERILATOR_LINT_OPTS = --lint-only       \
                      --language $(DUT_RTL_LANGUAGE) \
                      --Wall            \
                      -Wno-fatal        \
                      --top-module $(RTL_TOP)

###############################################################################
# Targets
###############################################################################
.PHONY: all prepare_build prepare_run check_elab lint elab run sim \
	regress regress-functional regress-performance clean clean_all help

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

regress:
	DUT="$(DUT)" BUILD_NAME="$(REGRESS_BUILD_NAME)" \
	FUNC_SEEDS="$(REGRESS_FUNC_SEEDS)" \
	PERF_SEEDS="$(REGRESS_PERF_SEEDS)" \
	RUN_TIME="$(RUN_TIME)" VERB="$(VERB)" \
	./script/run_regression.sh all

regress-functional:
	DUT="$(DUT)" BUILD_NAME="$(REGRESS_BUILD_NAME)" \
	FUNC_SEEDS="$(REGRESS_FUNC_SEEDS)" \
	RUN_TIME="$(RUN_TIME)" VERB="$(VERB)" \
	./script/run_regression.sh functional

regress-performance:
	DUT="$(DUT)" BUILD_NAME="$(REGRESS_BUILD_NAME)" \
	PERF_SEEDS="$(REGRESS_PERF_SEEDS)" \
	RUN_TIME="$(RUN_TIME)" VERB="$(VERB)" \
	./script/run_regression.sh performance

clean:
	rm -rf $(SIM)/run

clean_all:
	rm -rf $(SIM) csrc *.daidir vc_hdrs.h ucli.key

help:
	@echo "Targets:"
	@echo "  make lint    Lint the selected DUT RTL with Verilator"
	@echo "  make elab    Compile/elaborate UVM testbench"
	@echo "  make run     Run existing elaboration"
	@echo "  make sim     Compile and run"
	@echo "  make regress-functional  Run multi-seed functional regression"
	@echo "  make regress-performance Run P0-P6 and mixed-load performance characterization"
	@echo "  make regress             Run functional and performance regressions"
	@echo "Variables:"
	@echo "  DUT=$(DUT) (sv, single_fe, or legacy)"
	@echo "  VERILATOR=$(VERILATOR) RTL_FILELIST=$(RTL_FILELIST) RTL_TOP=$(RTL_TOP)"
	@echo "  TESTNAME=$(TESTNAME) SEED=$(SEED) VERB=$(VERB) BUILD_NAME=$(BUILD_NAME) RUN_TAG=$(RUN_TAG)"
	@echo "  REGRESS_BUILD_NAME=$(REGRESS_BUILD_NAME) REGRESS_FUNC_SEEDS='$(REGRESS_FUNC_SEEDS)' REGRESS_PERF_SEEDS='$(REGRESS_PERF_SEEDS)'"
