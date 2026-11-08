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
                assert(count == (vim.v.vim_did_enter == 1 and 1 or 0))
                vim.g.divine_cmp_config = true
              '';
          }
        ];
        startupConfig = # lua
          ''
            vim.cmd("filetype plugin on")
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
  nvim --headless -n -i NONE -u ${checkFor false}
  nvim --headless -n -i NONE -u ${checkFor true}
  touch "$out"
''
