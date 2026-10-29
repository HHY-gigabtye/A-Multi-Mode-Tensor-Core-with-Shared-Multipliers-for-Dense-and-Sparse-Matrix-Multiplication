VERILATOR ?= verilator

TOP       := tb_du_tia
BUILD_DIR ?= build/obj_dir
SIM       := $(BUILD_DIR)/V$(TOP)

SOURCES := \
	rtl/du_tia_pkg.sv \
	rtl/du_tia.sv \
	tb/tb_du_tia.sv

WARN_FLAGS := \
	-Wall -Wno-fatal \
	-Wno-UNUSEDSIGNAL \
	-Wno-UNUSEDPARAM \
	-Wno-BLKSEQ \
	-Wno-SYNCASYNCNET

.PHONY: all build sim lint lint-rtl vcd clean

all: lint-rtl sim

build: $(SIM)

$(SIM): $(SOURCES)
	mkdir -p $(BUILD_DIR)
	$(VERILATOR) --binary --timing --trace \
		$(WARN_FLAGS) --top-module $(TOP) --Mdir $(BUILD_DIR) \
		$(SOURCES)

sim: $(SIM)
	$(SIM)

lint:
	$(VERILATOR) --lint-only --timing \
		$(WARN_FLAGS) --top-module $(TOP) $(SOURCES)

lint-rtl:
	$(VERILATOR) --lint-only \
		$(WARN_FLAGS) --top-module du_tia \
		rtl/du_tia_pkg.sv rtl/du_tia.sv

vcd: $(SIM)
	mkdir -p build
	$(SIM) +VCD

clean:
	@echo "Remove '$(BUILD_DIR)' and 'build/' manually if desired."
