{ pkgs, lib }:
lib.mkBundle {
  inherit pkgs;
  configuration = {
    plugins = [
      {
        plugin = pkgs.vimPlugins.telescope-nvim;
        dependPlugins = [
          pkgs.vimPlugins.plenary-nvim
        ];
        config = # lua
          ''
            require("telescope").setup({})
          '';
      }
    ];
    extraPackages = [
      pkgs.ripgrep
      pkgs.fd
    ];
    startupConfig = # lua
      ''
        vim.g.mapleader = " "
        vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>")
      '';
  };
}
