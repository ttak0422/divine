{
  description = "divine implementation scaffold";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      git-hooks,
    }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      hooksFor =
        system:
        git-hooks.lib.${system}.run {
          src = self;
          package = nixpkgs.legacyPackages.${system}.prek;
          hooks = {
            nixfmt.enable = true;
            stylua.enable = true;
            luacheck.enable = true;
          };
        };
    in
    {
      # TODO(API): implementation scaffolding, not a stable consumer interface.
      lib = import ./lib { lib = nixpkgs.lib; };
      checks = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          pre-commit-check = hooksFor system;
          input-eval =
            assert (import ./tests/eval.nix { lib = pkgs.lib; }).passed;
            pkgs.runCommand "divine-input-eval" { } "touch $out";
          bundle =
            let
              bundle = import ./tests/bundle.nix { inherit pkgs; };
            in
            pkgs.runCommand "divine-bundle-tests" { nativeBuildInputs = [ pkgs.neovim ]; } ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              export NVIM_LOG_FILE="$TMPDIR/nvim.log"
              test ! -e ${bundle}/pack/divine/start
              test "$(find ${bundle}/pack/divine/opt -type l | wc -l | tr -d ' ')" = 3
              nvim --headless -n -i NONE -u ${bundle}/init.lua \
                -c 'lua dofile("${./tests/bundle.lua}")' -c 'qa!'
              touch "$out"
            '';
          runtime =
            pkgs.runCommand "divine-runtime-tests"
              {
                nativeBuildInputs = [ pkgs.neovim ];
              }
              ''
                cp -R ${self} source
                cd source
                export NVIM_LOG_FILE="$TMPDIR/nvim.log"
                nvim -u NONE --noplugin -n -i NONE -l tests/runtime.lua
                nvim -u NONE --noplugin -n -i NONE -l tests/runtime-plan.lua
                nvim -u NONE --noplugin -n -i NONE -l tests/triggers.lua
                touch "$out"
              '';
        }
      );
      devShells = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          hooks = hooksFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.neovim
              pkgs.nixdoc
              pkgs.git
              pkgs.gnumake
            ]
            ++ hooks.enabledPackages;
            inherit (hooks) shellHook;
          };
        }
      );
      formatter = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          cfg = (hooksFor system).config;
        in
        pkgs.writeShellScriptBin "divine-format" ''
          exec ${pkgs.lib.getExe cfg.package} run --all-files --config ${cfg.configFile} "$@"
        ''
      );
    };
}
