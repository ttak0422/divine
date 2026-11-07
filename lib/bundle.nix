/**
  Construct the opt-only bundle builder from the library and plan compiler.

  Named types are documented in ../docs/nix-types.md. The result is a
  derivation whose passthru graph is the resolved Graph; it is not a wrapped
  Neovim package.

  # Type

  ```
  import ./bundle.nix :: { lib :: AttrSet, compile :: CompilationConfiguration -> Compiled } -> { pkgs :: PackageSet, configuration :: CompilationConfiguration } -> Derivation
  ```
*/
{ lib, compile }:
{ pkgs, configuration }:
let
  compiled = compile configuration;
  planFile = pkgs.writeText "divine-plan.lua" "return ${compiled.lua}\n";
  initFile = pkgs.writeText "divine-init.lua" ''
    local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
    vim.opt.runtimepath:prepend(root)
    vim.opt.packpath:prepend(root)
    for _, path in ipairs(${lib.generators.toLua { } compiled.runtimePaths}) do
      vim.opt.runtimepath:append(path)
      if vim.fn.isdirectory(path .. "/after") == 1 then vim.opt.runtimepath:append(path .. "/after") end
    end
    local tools = ${lib.generators.toLua { } (lib.makeBinPath compiled.graph.extraPackages)}
    if tools ~= "" then
      local previous = vim.env.PATH or ""
      vim.env.PATH = tools .. (previous ~= "" and ":" .. previous or "")
    end
    return require("divine").setup(dofile(root .. "/plan.lua"))
  '';
in
# Keep package derivations intact. Only the explicit graph controls loading;
# nixpkgs packDir would promote their implicit plugin dependencies into start.
pkgs.runCommand "divine-bundle" { passthru = { inherit (compiled) graph; }; } ''
  mkdir -p "$out/pack/divine/opt" "$out/lua"
  cp -R ${../lua/divine} "$out/lua/divine"
  cp ${planFile} "$out/plan.lua"
  cp ${initFile} "$out/init.lua"
  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (id: node: ''
      test -d ${lib.escapeShellArg (toString node.package)}
      ln -s ${lib.escapeShellArg (toString node.package)} "$out/pack/divine/opt/${compiled.plan.nodes.${id}.name}"
    '') compiled.graph.nodes
  )}
''
