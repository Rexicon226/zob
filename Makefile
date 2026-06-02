# Behaviour test harness for rv64 backend.
#
# For each tests/<name>.c this:
# 	1. compiles its `foo` to RISCV-V asm via Zob
# 	2. Links that asm with tests/_driver.c, and injects the test's
# 	   `// CHECK: <expr>` comment as the CHECK macro, using `zig cc` to
#      cross-compile against riscv64-musl.
#   3. Runs the resulting ELF with qemu; a zero exit status means CHECK held.
#
# Usage:
#   make    	    # build + run ever test
#   make run-{test}  # build + run {test}
#   make build/add.s # just see the generated assembly for a test

ZIG    ?= zig
QEMU   ?= qemu-riscv64
TARGET ?= riscv64-linux-musl
BUILD  := build

TESTS := $(filter-out tests/_driver.c,$(wildcard tests/*.c))
NAMES := $(basename $(notdir $(TESTS)))
ELVES := $(NAMES:%=$(BUILD)/%.elf)
RUNS  := $(addprefix run-,$(NAMES))

.DEFAULT_GOAL := test
.PHONY: test clean FORCE $(RUNS)
.SECONDARY:

FORCE:

test: $(ELVES)
	@fail=0; \
	for name in $(NAMES); do \
	  if $(QEMU) $(BUILD)/$$name.elf; then echo "PASS  $$name"; \
	  else echo "FAIL  $$name (exit $$?)"; fail=1; fi; \
	done; \
	if [ $$fail -ne 0 ]; then echo "*** some tests failed"; exit 1; fi; \
	echo "All $(words $(NAMES)) tests passed."

$(RUNS): run-%: $(BUILD)/%.elf
	@if $(QEMU) $< ; then echo "PASS  $*"; else echo "FAIL  $* (exit $$?)"; exit 1; fi

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/%.s: tests/%.c FORCE | $(BUILD)
	@echo "ASM   $*"
	@$(ZIG) build arocc -- $< 2>/dev/null | sed -n '/^\.text/,/^\.size/p' > $@
	@test -s $@ || { echo "  no assembly produced for $<"; rm -f $@; exit 1; }

$(BUILD)/%.elf: $(BUILD)/%.s tests/_driver.c
	@echo "LINK  $*"
	@CHECK=$$(sed -n 's|^// *CHECK: *||p' tests/$*.c); \
	 if [ -z "$$CHECK" ]; then echo "  tests/$*.c: missing '// CHECK:' comment"; exit 1; fi; \
	 $(ZIG) cc -target $(TARGET) \
	   -Wno-unused-command-line-argument \
	   -Wno-deprecated-non-prototype \
	   tests/_driver.c $< -o $@ -DCHECK="$$CHECK"

clean:
	rm -rf $(BUILD)
