SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

###############################################################################
# Project / Test Configuration
###############################################################################
TB_TOP     ?= tb_top
TESTNAME   ?= ppe_basic_test
SEED       ?= 1
VERB       ?= UVM_MEDIUM
RUN_TIME   ?= 1ms
BUILD_NAME ?= default

SIM       ?= sim
BUILD_DIR := $(SIM)/build/$(BUILD_NAME)
RUN_DIR   := $(SIM)/run/$(TESTNAME)_seed_$(SEED)
BUILD_LOG_DIR := $(BUILD_DIR)/log
RUN_LOG_DIR   := $(RUN_DIR)/log
SIMV_DIR      := $(BUILD_DIR)/simv
SIMV_IMAGE    := $(SIMV_DIR)/$(TB_TOP).simv

FILELIST ?= ./script/filelist.f
RTL_FILELIST ?= ./script/rtl_filelist.f
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
                      --language 1364-2001 \
                      --Wall            \
                      --top-module ppe_top

###############################################################################
# Targets
###############################################################################
.PHONY: all prepare_build prepare_run check_elab lint elab run sim clean clean_all help

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

clean:
	rm -rf $(SIM)/run

clean_all:
	rm -rf $(SIM) csrc *.daidir vc_hdrs.h ucli.key

help:
	@echo "Targets:"
	@echo "  make lint    Lint Verilog-2001 RTL with Verilator"
	@echo "  make elab    Compile/elaborate UVM testbench"
	@echo "  make run     Run existing elaboration"
	@echo "  make sim     Compile and run"
	@echo "Variables:"
	@echo "  VERILATOR=$(VERILATOR) RTL_FILELIST=$(RTL_FILELIST)"
	@echo "  TESTNAME=$(TESTNAME) SEED=$(SEED) VERB=$(VERB) BUILD_NAME=$(BUILD_NAME)"
