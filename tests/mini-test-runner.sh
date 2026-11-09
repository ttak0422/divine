#!/bin/sh
# Exercise the same entry point used by Make and the flake check.
set -eu

# NVIM is Neovim's server address in child processes, not an executable.
runner=${NVIM_BIN:-nvim}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
export NVIM_LOG_FILE="$work/nvim.log"
export DIVINE_RUNNER_MARKER="$work/cleanup"

cat >"$work/pass.lua" <<'LUA'
local T, case = require("tests.helpers").new_child_set("native")
T["runner pass"] = case(function() assert(1 == 1) end)
return T
LUA
cat >"$work/failure.lua" <<'LUA'
local T, case = require("tests.helpers").new_child_set("native")
T["intentional runner failure"] = case(function(f)
  vim.fn.writefile({ f.root }, vim.env.DIVINE_RUNNER_MARKER)
  assert(false, "intentional runner assertion")
end)
return T
LUA
cat >"$work/empty.lua" <<'LUA'
return require("mini.test").new_set()
LUA
cat >"$work/collection.lua" <<'LUA'
error("intentional runner collection error")
LUA

run() { "$runner" --headless -u NONE --noplugin -n -i NONE -l tests/run.lua "$1"; }
run "$work/pass.lua" >"$work/pass.log" 2>&1
for scenario in failure empty collection; do
  if run "$work/$scenario.lua" >"$work/$scenario.log" 2>&1; then
    echo "mini.test incorrectly accepted $scenario" >&2
    exit 1
  fi
done

# Reject unrelated startup/dependency failures as a false-positive guard result.
grep -q 'runner pass' "$work/pass.log"
grep -q 'intentional runner failure' "$work/failure.log"
grep -q 'intentional runner assertion' "$work/failure.log"
grep -q 'empty test suite' "$work/empty.log"
grep -q 'intentional runner collection error' "$work/collection.log"
test -s "$DIVINE_RUNNER_MARKER"
test ! -e "$(cat "$DIVINE_RUNNER_MARKER")"
echo 'mini.test runner: pass, assertion, empty-suite, collection-error and cleanup guards passed'
