# Provisional input example, not an executable load plan.
{ pkgs, ... }:
{
  plugins = [
    # トップレベルでも依存でも package 単体を使える。
    pkgs.vimPlugins.vim-repeat

    {
      plugin = pkgs.vimPlugins.telescope-nvim;
      lazy = true;
      dependPlugins = [
        pkgs.vimPlugins.plenary-nvim
        # 依存にも同じ詳細定義を書き、さらに依存をネストできる。
        {
          plugin = pkgs.vimPlugins.vim-startuptime;
          lazy = false; # この定義も opt のまま起動時にロードする。
          preConfig = # lua
            ''
              vim.g.startuptime_tries = 10
            '';
          config = # lua
            ''
              vim.keymap.set("n", "<leader>st", "<cmd>StartupTime<cr>")
            '';
          dependPlugins = [ pkgs.vimPlugins.vim-repeat ];
        }
      ];
      onCommands = [ "Telescope" ];
      extraPackages = [
        pkgs.ripgrep
        pkgs.fd
      ];
      config = builtins.readFile ./lua/telescope.lua;
    }
  ];
}
