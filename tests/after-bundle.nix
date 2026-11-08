{ pkgs }:
let
  api = import ../lib { inherit (pkgs) lib; };
  overrides = pkgs.runCommand "divine-after-runtime-overrides" { } ''
    mkdir -p "$out/after/ftplugin" "$out/after/ftdetect"
    echo 'vim.b.divine_runtime_order = "after"' > "$out/after/ftplugin/divinefixture.lua"
    echo 'autocmd BufNewFile *.divinefixture setfiletype divinefixture' > "$out/after/ftdetect/divinefixture.vim"
  '';
  base = pkgs.runCommand "divine-after-runtime-base" { } ''
    mkdir -p "$out/ftplugin"
    echo 'vim.b.divine_runtime_order = "base"' > "$out/ftplugin/divinefixture.lua"
  '';
  fixture = pkgs.runCommand "divine-managed-after-fixture" { } ''
    mkdir -p "$out/plugin" "$out/after"/{plugin,ftdetect,ftplugin,indent,syntax,custom}
    echo 'vim.g.divine_fixture_plugin = true' > "$out/plugin/main.lua"
    echo 'assert(vim.g.divine_fixture_plugin); vim.g.divine_fixture_after = (vim.g.divine_fixture_after or 0) + 1' > "$out/after/plugin/main.lua"
    echo 'autocmd BufNewFile *.divinefixture setfiletype divinefixture' > "$out/after/ftdetect/divinefixture.vim"
    echo 'vim.b.divine_fixture_ftplugin = true' > "$out/after/ftplugin/divinefixture.lua"
    echo 'vim.bo.shiftwidth = 7' > "$out/after/indent/divinefixture.lua"
    echo 'vim.b.divine_fixture_syntax = true' > "$out/after/syntax/divinefixture.lua"
    echo 'preserved' > "$out/after/custom/data"
    echo 'preserved' > "$out/.hidden"
    echo 'preserved' > "$out/after/.hidden"
  '';
  bundleFor =
    lazy:
    api.mkBundle {
      inherit pkgs;
      configuration = {
        runtimePaths = [
          overrides
          base
        ];
        plugins = [
          {
            plugin = fixture;
            inherit lazy;
            loadAfter = true;
            onFiletypes = [ "divinefixture" ];
            config = # lua
              ''
                assert(vim.g.divine_fixture_after == 1)
                vim.g.divine_fixture_config = true
              '';
          }
          {
            plugin = pkgs.vimPlugins.cmp-buffer;
            inherit lazy;
            loadAfter = true;
            dependPlugins = [ pkgs.vimPlugins.nvim-cmp ];
            config = # lua
              ''
                local count = 0
                for _, source in pairs(require("cmp").get_registered_sources()) do
                  if source.name == "buffer" then count = count + 1 end
                end
                assert(count == 1, "cmp-buffer must register before config")
                vim.g.divine_cmp_config = true
              '';
          }
        ];
        startupConfig = # lua
          ''
            vim.cmd("filetype plugin indent on")
            vim.cmd("syntax on")
          '';
      };
    };
  checkFor =
    lazy:
    let
      bundle = bundleFor lazy;
    in
    pkgs.writeText "divine-after-cmp-init.lua" ''
      local controller = dofile("${bundle}/init.lua")
      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        nested = true,
        callback = function()
          local ok, err = xpcall(function()
            local function count()
              local result = 0
              for _, source in pairs(require("cmp").get_registered_sources()) do
                if source.name == "buffer" then result = result + 1 end
              end
              return result
            end
            assert(vim.g.divine_fixture_after == 1 and vim.g.divine_fixture_config)
            assert(vim.bo.filetype == "divinefixture", "first file must be detected")
            assert(vim.b.divine_fixture_ftplugin and vim.b.divine_fixture_syntax)
            assert(vim.bo.shiftwidth == 7)
            assert(count() == ${if lazy then "0" else "1"})
            controller.load("${pkgs.vimPlugins.cmp-buffer}")
            assert(count() == 1 and vim.g.divine_cmp_config)
            controller.load("${pkgs.vimPlugins.cmp-buffer}")
            assert(count() == 1, "cmp-buffer must register only once")
            vim.cmd.edit(vim.fn.fnameescape(vim.env.HOME .. "/new.divinefixture"))
            assert(vim.bo.filetype == "divinefixture")
            assert(vim.b.divine_runtime_order == "after")
          end, debug.traceback)
          if not ok then io.stderr:write(tostring(err) .. "\n") end
          vim.cmd(ok and "qa!" or "cquit 1")
        end,
      })
    '';
in
pkgs.runCommand "divine-after-bundle-tests" { nativeBuildInputs = [ pkgs.neovim ]; } ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  export NVIM_LOG_FILE="$TMPDIR/nvim.log"
  for bundle in ${bundleFor false} ${bundleFor true}; do
    fixtureView="$bundle/pack/divine/opt/divine-${builtins.hashString "sha256" (toString fixture)}"
    test -n "$fixtureView"
    test ! -e "$fixtureView/after/plugin"
    for relative in plugin/main.lua after/ftdetect/divinefixture.vim after/ftplugin/divinefixture.lua after/indent/divinefixture.lua after/syntax/divinefixture.lua after/custom/data .hidden after/.hidden; do
      cmp "$fixtureView/$relative" "${fixture}/$relative"
    done
  done
  nvim --headless -n -i NONE -u ${checkFor false} "$HOME/initial.divinefixture"
  nvim --headless -n -i NONE -u ${checkFor true} "$HOME/initial.divinefixture"
  touch "$out"
''
