NIX_UNIT ?= nix-unit
NIXPKGS_LIB ?=

.PHONY: test test-nix test-lua test-graph
test: test-nix test-lua test-graph

# The default evaluates the suite through the locked flake's nixpkgs library.
# An explicit library path supports offline runs without evaluating the flake.
test-nix:
	@if test -n "$(NIXPKGS_LIB)"; then \
	  $(NIX_UNIT) --arg lib 'import $(NIXPKGS_LIB)' tests/default.nix; \
	else $(NIX_UNIT) --flake .#tests; fi
	@NIX_UNIT="$(NIX_UNIT)" sh tests/nix-unit-runner.sh

test-lua:
	@NVIM_LOG_FILE="$${TMPDIR:-/tmp}/divine-test-nvim.log" nvim --headless -u NONE --noplugin -n -i NONE -l tests/run.lua
	@sh tests/mini-test-runner.sh
	@nvim --headless -u NONE --noplugin -n -i NONE -l tests/mini-test-environment.lua
	@nvim --headless -u NONE --noplugin -n -i NONE -l tests/after-startup.lua

# Dependency-free viewer DOM-contract tests; built HTML is checked by the flake.
test-graph:
	@node --test tests/graph-viewer.test.js
