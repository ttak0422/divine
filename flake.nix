{
  description = "divine implementation scaffold";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  /**
    Define the library, test suite and per-system development/build outputs.

    # Type

    ```
    outputs :: { self :: AttrSet, nixpkgs :: AttrSet, nixpkgs-stable :: AttrSet, git-hooks :: AttrSet } -> AttrSet
    ```
  */
  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-stable,
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
      packages = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          example = self.lib.mkBundle {
            inherit pkgs;
            configuration = import ./examples/example.nix { inherit pkgs; };
          };
          graph = self.lib.mkGraph {
            inherit pkgs;
            configuration = import ./examples/example.nix { inherit pkgs; };
          };
        }
      );
      checks = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          exampleConfiguration = import ./examples/example.nix { inherit pkgs; };
          exampleBundle = self.packages.${system}.example;
          eventPlans = pkgs.writeText "divine-event-plans.lua" (
            "return " + import ./tests/events.nix { inherit (pkgs) lib; }
          );

          /**
            Run compiled event plans on a runtime, optionally checking its source catalog.

            # Type

            ```
            eventCheck :: PackageSet -> String -> Derivation
            ```
          */
          eventCheck =
            packages: source:
            packages.runCommand "divine-compiled-events-tests"
              {
                nativeBuildInputs = [ packages.neovim ];
              }
              ''
                cp -R ${self} source
                cd source
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                nvim --headless -u NONE --noplugin -n -i NONE -l tests/events.lua ${eventPlans} ${source}
                touch "$out"
              '';
        in
        (import ./tests/definition-checks.nix { inherit pkgs; })
        // (self.lib.mkChecks {
          inherit pkgs;
          configuration = exampleConfiguration;
          bundle = exampleBundle;
        })
        // {
          pre-commit-check = hooksFor system;
          graph =
            let
              fixture = self.lib.mkGraph {
                inherit pkgs;
                configuration = import ./tests/graph-fixture.nix;
              };
              empty = self.lib.mkGraph {
                inherit pkgs;
                configuration.plugins = [ ];
              };
            in
            pkgs.runCommand "divine-graph-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
              cp -R ${self} source
              cd source
              node --test tests/graph-viewer.test.js
              node tests/graph-html.test.js ${fixture} ${empty}
              touch "$out"
            '';
          example =
            assert builtins.elem (toString pkgs.vimPlugins.mini-pairs) exampleBundle.graph.roots;
            assert
              toString exampleBundle == toString (
                self.lib.mkBundle {
                  inherit pkgs;
                  configuration = exampleConfiguration;
                }
              );
            pkgs.runCommand "divine-example-test" { nativeBuildInputs = [ pkgs.neovim ]; } ''
              export HOME="$TMPDIR/home"
              export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
              export XDG_STATE_HOME="$HOME/state" XDG_CACHE_HOME="$HOME/cache"
              mkdir -p "$HOME"
              nvim --headless -n -i NONE -u ${exampleBundle}/init.lua -l ${./tests/example.lua}
              if nvim --headless -n -i NONE -u NONE -l ${./tests/example.lua} > negative.log 2>&1; then
                echo "example smoke test unexpectedly accepted an unconfigured editor" >&2
                exit 1
              fi
              touch "$out"
            '';
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
          after-bundle = import ./tests/after-bundle.nix { inherit pkgs; };
          real-plugin-events = import ./tests/real-plugin-events.nix { inherit pkgs; };
          events = eventCheck pkgs "";
          events-stable =
            eventCheck nixpkgs-stable.legacyPackages.${system}
              "${nixpkgs-stable.legacyPackages.${system}.neovim-unwrapped.src}/src/nvim/auevents.lua";
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
                nvim --headless -u NONE --noplugin -n -i NONE -l tests/mini-test-environment.lua
                nvim --headless -u NONE --noplugin -n -i NONE -l tests/after-startup.lua
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
              pkgs.nodejs
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
