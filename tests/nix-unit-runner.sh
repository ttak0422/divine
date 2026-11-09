#!/bin/sh
# Guard the runner contract, including unexpected evaluation errors. None of
# these fixtures needs nixpkgs or a daemon; the real suite runs separately.
set -eu
runner=${NIX_UNIT:-nix-unit}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

"$runner" --eval-store 'dummy://' --expr '{
  testPass = { expr = 1; expected = 1; };
  testExpectedThrow = {
    expr = throw "expected runner fixture";
    expectedError = { type = "ThrownError"; msg = "expected runner fixture"; };
  };
}' >"$work/pass.log" 2>&1

if "$runner" --eval-store 'dummy://' --expr '{
  testMismatch = { expr = 1; expected = 2; };
}' >"$work/mismatch.log" 2>&1; then
  echo 'nix-unit incorrectly accepted a value mismatch' >&2
  exit 1
fi
if "$runner" --eval-store 'dummy://' --expr '{
  testUnexpectedThrow = { expr = throw "unexpected runner fixture"; expected = true; };
}' >"$work/throw.log" 2>&1; then
  echo 'nix-unit incorrectly accepted an unexpected evaluation error' >&2
  exit 1
fi

# Require each intentional failure to identify its case, rather than merely
# accepting an unrelated invocation or setup failure as a successful guard.
grep -q testMismatch "$work/mismatch.log"
grep -q testUnexpectedThrow "$work/throw.log"
echo 'nix-unit runner: success, mismatch and unexpected-error guards passed'
