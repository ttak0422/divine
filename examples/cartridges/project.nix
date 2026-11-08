/**
  Configure the projects picker with a package reference to the Telescope group.

  Pin the original ahmedkhalf plugin; locked Nixpkgs packages a different fork.

  # Type

  ```
  import ./project.nix :: { pkgs :: PackageSet, telescope :: AttrsOf Definition } -> AttrsOf Definition
  ```
*/
{ pkgs, telescope }:
{
  project = {
    plugin = pkgs.vimUtils.buildVimPlugin {
      pname = "project.nvim";
      version = "2023-04-04";
      src = pkgs.fetchFromGitHub {
        owner = "ahmedkhalf";
        repo = "project.nvim";
        rev = "8c6bad7d22eef1b71144b401c9f74ed01526a4fb";
        hash = "sha256-avV3wMiDbraxW4mqlEsKy0oeewaRj9Q33K8NzWoaptU=";
      };
    };
    # This configuration uses Telescope; project.nvim itself also works without it.
    dependPlugins = [ telescope.telescope.plugin ];
    config = # lua
      ''
        require("project_nvim").setup({
          manual_mode = true,
          detection_methods = { "pattern" },
        })
        require("telescope").load_extension("projects")
      '';
    doc = ''
      Use `:ProjectRoot` to record a project, then `:Telescope projects` to
      revisit it. This configuration uses pattern-based root detection and
      explicitly enables the optional Telescope integration.
    '';
    test =
      {
        pkgs,
        neovim,
        bundle,
      }:
      let
        script =
          pkgs.writeText "project-telescope.lua" # lua
            ''
              assert(require("project_nvim.config").options.manual_mode, "project setup did not run")
              local root = vim.fn.resolve(vim.env.HOME) .. "/fixture"
              vim.fn.mkdir(root .. "/.git", "p")
              vim.cmd.edit(root .. "/example.lua")
              vim.bo.filetype = "lua"
              vim.cmd("ProjectRoot")
              assert(vim.fn.getcwd() == root, "project root was not selected")
              assert(vim.tbl_contains(require("project_nvim").get_recent_projects(), root),
                "project was not added to history")
              vim.cmd("Telescope projects")
              local state = require("telescope.actions.state")
              local prompt = vim.api.nvim_get_current_buf()
              local picker = state.get_current_picker(prompt)
              assert(vim.wait(5000, function() return picker.manager and picker.manager:num_results() > 0 end),
                "projects picker has no results")
              assert(picker.manager:get_entry(1).value == root, "picker omitted the project")
              require("telescope.actions").close(prompt)
              vim.cmd("qa!")
            '';
      in
      assert pkgs.lib.any (
        node:
        (node.package.pname or "") == "project.nvim"
        && builtins.elem (toString telescope.telescope.plugin) node.dependencies
      ) (builtins.attrValues bundle.graph.nodes);
      pkgs.runCommand "project-telescope" { } ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
        export XDG_STATE_HOME="$HOME/state" XDG_CACHE_HOME="$HOME/cache"
        mkdir -p "$HOME"
        ${neovim}/bin/nvim --headless -n -i NONE -l ${script}
        touch "$out"
      '';
  };
}
