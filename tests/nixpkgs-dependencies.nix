{ pkgs }:
let
  inherit (pkgs) lib;
  api = import ../lib { inherit lib; };
  inherit (pkgs.vimPlugins) vim-textobj-entire vim-textobj-line vim-textobj-user;

  # A user-selected variant must not also pull in the unmodified dependency.
  selectedUser = vim-textobj-user.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      touch "$out/divine-selected-dependency"
    '';
  });
  tool = pkgs.writeShellScriptBin "divine-dependency-tool" "printf 'dependency-tool-ok'";
  dependency = {
    plugin = selectedUser;
    lazy = true;
    extraPackages = [ tool ];
    config = # lua
      ''
        vim.g.divine_dependency_configs = (vim.g.divine_dependency_configs or 0) + 1
      '';
  };
  implicit = api.mkBundle {
    inherit pkgs;
    configuration.plugins =
      map
        (plugin: {
          inherit plugin;
          lazy = true;
        })
        [
          vim-textobj-entire
          vim-textobj-line
        ];
  };
  explicit = api.mkBundle {
    inherit pkgs;
    configuration.plugins = [
      {
        plugin = vim-textobj-entire;
        lazy = false;
        dependPlugins = [ dependency ];
      }
      {
        plugin = vim-textobj-line;
        lazy = true;
        onEvents = "User";
        dependPlugins = [ dependency ];
      }
    ];
  };

  # Reference reproduction: nixpkgs promotes the original dependency into start,
  # even when a different output of the same plugin is explicitly placed in opt.
  reference = pkgs.vimUtils.packDir {
    reference.opt = [
      vim-textobj-entire
      vim-textobj-line
      selectedUser
    ];
  };
  referenceInit = pkgs.writeText "divine-dependency-reference.lua" ''
    vim.opt.packpath:prepend(${lib.generators.toLua { } (toString reference)})
    vim.cmd.packloadall()
    vim.cmd.packadd("vim-textobj-user")
  '';
  id = package: builtins.unsafeDiscardStringContext (toString package);
  graph = explicit.graph;
  originalNode = graph.nodes.${id vim-textobj-entire}.package;
in
assert vim-textobj-entire.dependencies == [ vim-textobj-user ];
assert vim-textobj-line.dependencies == [ vim-textobj-user ];
assert toString selectedUser != toString vim-textobj-user;
assert originalNode.drvPath == vim-textobj-entire.drvPath;
assert originalNode.dependencies == vim-textobj-entire.dependencies;
assert originalNode.nativeBuildInputs == vim-textobj-entire.nativeBuildInputs;
assert !(graph.nodes ? ${id vim-textobj-user});
assert builtins.length (builtins.attrNames graph.nodes) == 3;
pkgs.runCommand "divine-nixpkgs-dependency-tests" { nativeBuildInputs = [ pkgs.neovim ]; } ''
  export HOME="$TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
  export XDG_STATE_HOME="$HOME/state" XDG_CACHE_HOME="$HOME/cache"
  export NVIM_LOG_FILE="$TMPDIR/nvim.log"
  mkdir -p "$HOME"
  test ! -e ${implicit}/pack/divine/start
  test ! -e ${explicit}/pack/divine/start
  test "$(find ${implicit}/pack/divine/opt -type l | wc -l | tr -d ' ')" = 2
  test "$(find ${explicit}/pack/divine/opt -type l | wc -l | tr -d ' ')" = 3
  test "$(readlink ${reference}/pack/reference/start/vim-textobj-user)" = ${vim-textobj-user}
  test "$(readlink ${reference}/pack/reference/opt/vim-textobj-user)" = ${selectedUser}
  export DIVINE_SELECTED_USER=${selectedUser}
  for mode in reference implicit explicit; do
    export DIVINE_DEPENDENCY_MODE="$mode"
    case "$mode" in
      reference) init=${referenceInit} ;;
      implicit) init=${implicit}/init.lua ;;
      explicit) init=${explicit}/init.lua ;;
    esac
    nvim --headless -n -i NONE -u "$init" \
      -c 'lua dofile("${./nixpkgs-dependencies.lua}")' -c 'qa!'
  done
  touch "$out"
''
