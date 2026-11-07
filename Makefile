NIXPKGS_LIB ?=

.PHONY: test test-nix test-lua
test: test-nix test-lua

test-nix:
	@if test -n "$(NIXPKGS_LIB)"; then \
	  nix-instantiate --eval --strict tests/eval.nix --arg lib 'import $(NIXPKGS_LIB)' ; \
	else nix-instantiate --eval --strict tests/eval.nix; fi

test-lua:
	@NVIM_LOG_FILE="$${TMPDIR:-/tmp}/divine-test-nvim.log" nvim -u NONE --noplugin -n -i NONE -l tests/runtime.lua
	@NVIM_LOG_FILE="$${TMPDIR:-/tmp}/divine-test-nvim.log" nvim -u NONE --noplugin -n -i NONE -l tests/runtime-plan.lua
	@NVIM_LOG_FILE="$${TMPDIR:-/tmp}/divine-test-nvim.log" nvim -u NONE --noplugin -n -i NONE -l tests/triggers.lua
