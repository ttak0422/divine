{ pkgs }:
let
  api = import ../lib { inherit (pkgs) lib; };
  python = pkgs.python3.withPackages (ps: [ ps.pynvim ]);
  bundleFor =
    lazy:
    api.mkBundle {
      inherit pkgs;
      configuration = {
        plugins = [
          {
            plugin = pkgs.vimPlugins.vim-lastplace;
            inherit lazy;
            onEvents = "BufReadPost";
            config = # lua
              ''
                vim.g.divine_lastplace_configs = (vim.g.divine_lastplace_configs or 0) + 1
              '';
          }
          {
            packages = [
              pkgs.vimPlugins.nvim-cmp
              pkgs.vimPlugins.cmp-buffer
            ];
            inherit lazy;
            loadAfter = true;
            onEvents = "InsertEnter";
            config = # lua
              ''
                vim.g.divine_cmp_configs = (vim.g.divine_cmp_configs or 0) + 1
                local cmp = require("cmp")
                cmp.setup({
                  mapping = {
                    ["<F12>"] = cmp.mapping.complete(),
                    ["<F13>"] = cmp.mapping.confirm({ select = true }),
                  },
                  sources = { { name = "buffer", option = { indexing_interval = 1 } } },
                })
              '';
          }
        ];
        startupConfig = # lua
          ''
            local group = vim.api.nvim_create_augroup("divine_existing_observers", { clear = true })
            vim.api.nvim_create_autocmd("BufReadPre", {
              group = group,
              callback = function()
                vim.g.divine_reads = (vim.g.divine_reads or 0) + 1
                vim.fn.setpos("'\"", { 0, 6, 2, 0 })
              end,
            })
            for _, event in ipairs({ "InsertEnter", "TextChangedI", "TextChangedP" }) do
              vim.api.nvim_create_autocmd(event, {
                group = group,
                callback = function()
                  vim.g["divine_" .. event] = (vim.g["divine_" .. event] or 0) + 1
                end,
              })
            end
          '';
      };
    };
in
pkgs.runCommand "divine-real-plugin-events-tests"
  {
    nativeBuildInputs = [
      pkgs.neovim
      pkgs.coreutils
      python
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
    export XDG_STATE_HOME="$HOME/state" XDG_CACHE_HOME="$HOME/cache"
    export NVIM_LOG_FILE="$TMPDIR/nvim.log"
    mkdir -p "$HOME"
    timeout 90s python ${./real-plugin-events.py} ${bundleFor false} ${bundleFor true}
    touch "$out"
  ''
