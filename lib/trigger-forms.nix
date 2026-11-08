/**
  Normalize known trigger forms for Nix comparison and runtime-plan compilation.

  Omission belongs to the caller. Return ordered lists without deduplication;
  key duplicates remain significant and string equality may include build context.

  # Type

  ```
  import ./trigger-forms.nix :: { lib :: AttrSet, fail :: String -> a } -> AttrsOf (a -> [a])
  ```
*/
{ lib, fail }:
let
  /**
    Validate and wrap one nonempty condition or list, preserving order and context.

    The first argument is the diagnostic context. An empty list is valid;
    empty strings and non-string list elements throw.

    # Type

    ```
    conditions :: String -> (String | [String]) -> [String]
    ```
  */
  conditions =
    context: value:
    let
      values = if builtins.isString value then [ value ] else value;
    in
    if builtins.isList values && lib.all (v: builtins.isString v && v != "") values then
      values
    else
      fail "${context} must be a string or a list of nonempty strings";
  /**
    Normalize one key declaration or a list of declarations.

    The first argument is the diagnostic context. An empty list is valid.

    # Type

    ```
    keys :: String -> (KeyInput | [KeyInput]) -> [Key]
    ```
  */
  keys =
    context: value:
    let
      entries = if builtins.isString value || builtins.isAttrs value then [ value ] else value;
      /**
        Normalize one nonempty key, defaulting an omitted mode to normal mode.

        Only lhs and mode are accepted in an attribute-set declaration.

        # Type

        ```
        normalize :: KeyInput -> Key
        ```
      */
      normalize =
        entry:
        if builtins.isString entry && entry != "" then
          {
            lhs = entry;
            mode = "n";
          }
        else if
          builtins.isAttrs entry
          && entry ? lhs
          && builtins.isString entry.lhs
          && entry.lhs != ""
          &&
            builtins.attrNames (
              builtins.removeAttrs entry [
                "lhs"
                "mode"
              ]
            ) == [ ]
          && builtins.elem (entry.mode or "n") [
            "n"
            "i"
            "x"
            "s"
            "o"
            "t"
          ]
        then
          {
            inherit (entry) lhs;
            mode = entry.mode or "n";
          }
        else
          fail "${context} entries need lhs and an optional single mode (n/i/x/s/t/o)";
    in
    if builtins.isList entries then
      map normalize entries
    else
      fail "${context} must be a key or a list of keys";
  eventNames = import ./events.nix;
  eventLookup = builtins.listToAttrs (
    map (name: {
      name = lib.toLower name;
      value = name;
    }) eventNames.names
    ++ lib.mapAttrsToList (name: value: {
      name = lib.toLower name;
      inherit value;
    }) eventNames.aliases
  );
  /**
    Canonicalize event spellings while preserving order, duplicates and context.

    # Type

    ```
    events :: (String | [String]) -> [String]
    ```
  */
  events =
    value:
    map (
      name:
      let
        lookupName = builtins.unsafeDiscardStringContext (lib.toLower name);
        canonical = eventLookup.${lookupName} or (fail "unknown onEvents event '${name}' (Neovim 0.12.4)");
      in
      builtins.appendContext canonical (builtins.getContext name)
    ) (conditions "onEvents" value);
in
{
  onEvents = events;
  onCommands = conditions "onCommands";
  onFiletypes = conditions "onFiletypes";
  onModules = conditions "onModules";
  onKeys = keys "onKeys";
}
