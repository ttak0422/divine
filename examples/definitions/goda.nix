/**
  Illustrate a package reference across files without duplicating test ownership.

  Supply the actual Goda package; no plugin source or setup API is assumed here.

  # Type

  ```
  import ./goda.nix :: { packages :: { goda :: Package }, telescope :: AttrsOf Definition } -> AttrsOf Definition
  ```
*/
{
  packages,
  telescope,
}:
{
  goda = {
    plugin = packages.goda;
    # Illustrative edge only, not a real Goda dependency requirement.
    dependPlugins = [ telescope.telescope.plugin ];
    doc = ''
      This example uses a caller-supplied Goda package. Its dependency edge to
      Telescope demonstrates cross-file composition, not upstream requirements.
      Add the real plugin's dependencies and configuration for your own use.
    '';
    test.goda-package =
      { pkgs }:
      pkgs.runCommand "goda-package" { } ''
        test -d ${packages.goda}
        touch "$out"
      '';
  };
}
