{ lib }:
let
  api = import ../lib { inherit lib; };
  catalog = import ../lib/events.nix;
  pairs = catalog.aliases // {
    uSeR = "User";
    fIlEtYpE = "FileType";
  };
  compile =
    alias: canonical:
    api.compile {
      plugins =
        map
          (name: {
            plugin = {
              type = "derivation";
              inherit name;
              outPath = "/nix/store/00000000000000000000000000000000-${name}";
            };
            lazy = true;
            onEvents =
              if name == "a" then
                [
                  alias
                  (lib.toLower alias)
                  canonical
                  (lib.toUpper canonical)
                ]
              else
                [ canonical ];
          })
          [
            "a"
            "b"
            "c"
          ];
    };
in
lib.generators.toLua { } {
  inherit (catalog) names aliases;
  plans = lib.mapAttrs (alias: canonical: {
    inherit canonical;
    plan = (compile alias canonical).plan;
  }) pairs;
}
