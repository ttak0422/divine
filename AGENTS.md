# Working on divine

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing the repository or writing
an issue, commit, or pull request. It is the shared contribution guide for human
contributors and coding agents; use the linked templates rather than inventing
agent-specific formats.

Read relevant documentation and existing checks before implementation. Keep
proposals and unresolved questions explicit; do not turn them into accepted
decisions as a side effect of implementation. Report the checks actually run and
any remaining limitations.

Read docs/design.md and TODO.md before changing behavior. All current API names
are provisional; do not settle unknown defaults, identity/merge/conflict rules or
cycle representation merely to make a check pass. Root and dependency definitions
must retain the same recursive expressiveness.

Run make test for changes to input inspection or runtime sequencing. Use the
git-hooks.nix/prek checks for Nix/Lua style. Nix functions use nixdoc comments.
Keep first-trigger and real-plugin tests distinct from isolated fixture checks.
Do not introduce an external loader or automatically source after/plugin.
