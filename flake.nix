{
  description = "divine implementation scaffold";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  /**
    Define the library, test suite and per-system development/build outputs.

    # Type

    ```
    outputs :: { self :: AttrSet, nixpkgs :: AttrSet, git-hooks :: AttrSet } -> AttrSet
    ```
  */
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
      /**
        Map a function over the supported system strings into a system-keyed set.

        # Type

        ```
        eachSystem :: (String -> a) -> AttrsOf a
        ```
      */
      eachSystem = nixpkgs.lib.genAttrs systems;
      /**
        Build the style-check derivation for one supported system.

        The git-hooks.nix result also exposes config, enabledPackages and
        shellHook through passthru for the development shell and formatter.

        # Type

        ```
        hooksFor :: String -> Derivation
        ```
      */
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
      tests = import ./tests { lib = nixpkgs.lib; };
      checks = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          pre-commit-check = hooksFor system;
          input-eval = pkgs.runCommand "divine-nix-unit-tests" { nativeBuildInputs = [ pkgs.nix-unit ]; } ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            nix-unit --eval-store "$TMPDIR/store" \
              --arg lib 'import ${nixpkgs}/lib' ${self}/tests/default.nix
            sh ${./tests/nix-unit-runner.sh}
            touch "$out"
          '';
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
          nixpkgs-dependencies = import ./tests/nixpkgs-dependencies.nix { inherit pkgs; };
          runtime =
            pkgs.runCommand "divine-runtime-tests"
              {
                nativeBuildInputs = [ pkgs.neovim ];
                MINI_TEST = "${pkgs.vimPlugins.mini-test}";
              }
              ''
                cp -R ${self} source
                cd source
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                export NVIM_LOG_FILE="$TMPDIR/nvim.log"
                nvim --headless -u NONE --noplugin -n -i NONE -l tests/run.lua
                sh tests/mini-test-runner.sh
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
            MINI_TEST = "${pkgs.vimPlugins.mini-test}";
            packages = [
              pkgs.neovim
              pkgs.nixdoc
              pkgs.nix-unit
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
