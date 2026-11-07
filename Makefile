NIX_UNIT ?= nix-unit
NIXPKGS_LIB ?=

.PHONY: test test-nix test-lua
test: test-nix test-lua

# The default evaluates the suite through the locked flake's nixpkgs library.
# An explicit library path supports offline runs without evaluating the flake.
test-nix:
	@if test -n "$(NIXPKGS_LIB)"; then \
	  $(NIX_UNIT) --arg lib 'import $(NIXPKGS_LIB)' tests/default.nix; \
	else $(NIX_UNIT) --flake .#tests; fi
	@NIX_UNIT="$(NIX_UNIT)" sh tests/nix-unit-runner.sh

test-lua:
	@NVIM_LOG_FILE="$${TMPDIR:-/tmp}/divine-test-nvim.log" nvim -u NONE --noplugin -n -i NONE -l tests/runtime.lua
	@NVIM_LOG_FILE="$${TMPDIR:-/tmp}/divine-test-nvim.log" nvim -u NONE --noplugin -n -i NONE -l tests/runtime-plan.lua
	@NVIM_LOG_FILE="$${TMPDIR:-/tmp}/divine-test-nvim.log" nvim -u NONE --noplugin -n -i NONE -l tests/triggers.lua
