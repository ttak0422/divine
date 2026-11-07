{ pkgs }:
let
  api = import ../lib { inherit (pkgs) lib; };
  a = pkgs.runCommand "divine-fixture-a" { } ''
    mkdir -p "$out/plugin" "$out/lua" "$out/after/plugin"
    echo 'if vim.g.divine_a then return end; vim.g.divine_a = 1' > "$out/plugin/a.lua"
    echo 'vim.g.divine_native_scans = (vim.g.divine_native_scans or 0) + 1' > "$out/plugin/native-scan.lua"
    echo 'return { value = "a" }' > "$out/lua/divine_fixture_a.lua"
    echo 'vim.g.divine_a_after = (vim.g.divine_a_after or 0) + 1' > "$out/after/plugin/a.lua"
  '';
  b = pkgs.runCommand "divine-fixture-b" { } ''
    mkdir -p "$out/plugin" "$out/lua"
    echo 'if vim.g.divine_b then return end; vim.g.divine_b = 1' > "$out/plugin/b.lua"
    echo 'return { value = "b" }' > "$out/lua/divine_fixture_b.lua"
  '';
  deferred = pkgs.runCommand "divine-fixture-deferred" { } ''
    mkdir -p "$out/plugin" "$out/after/plugin" "$out/lua"
    cat > "$out/plugin/deferred.lua" <<'LUA'
    vim.g.divine_deferred = (vim.g.divine_deferred or 0) + 1
    vim.api.nvim_create_user_command("DivineFixture", function(args)
      vim.g.divine_command_args = args.args
      vim.g.divine_command_bang = args.bang
    end, { nargs = "*", bang = true })
    LUA
    echo 'vim.g.divine_deferred_after = true' > "$out/after/plugin/deferred.lua"
    echo 'return { value = "deferred" }' > "$out/lua/divine_fixture_deferred.lua"
  '';
  tool = pkgs.writeShellScriptBin "divine-fixture-tool" "printf 'divine-tool-ok'";
in
api.mkBundle {
  inherit pkgs;
  configuration = {
    plugins = [
      {
        plugin = a;
        lazy = false;
        dependPlugins = [ b ];
        preConfig = # lua
          ''
            assert(require("divine_fixture_b").value == "b")
            vim.g.divine_pre = true
          '';
        config = # lua
          ''
            assert(vim.g.divine_a == 1 and vim.g.divine_b == 1)
            assert(not vim.g.divine_a_after)
            vim.g.divine_config = true
          '';
      }
      {
        plugin = b;
        lazy = true;
        dependPlugins = [ a ];
      }
      {
        plugin = deferred;
        lazy = true;
        onCommands = "DivineFixture";
        onModules = "divine_fixture_deferred";
      }
    ];
    extraPackages = [ tool ];
    startupConfig = # lua
      ''
        assert(not vim.g.divine_a)
        vim.g.divine_startup = true
      '';
  };
}
