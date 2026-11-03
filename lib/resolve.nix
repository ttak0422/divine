{ lib, inspectDefinitions }:
request@{
  plugins,
  extraPackages ? [ ],
  ...
}:
let
  inherit (builtins)
    attrNames
    concatLists
    deepSeq
    foldl'
    listToAttrs
    mapAttrs
    ;
  fail = message: throw "divine resolver: ${message}";
  # Provisional identity, not a final consumer API: see docs/resolution.md.
  # IDs must be context-free; original package values retain their build dependencies.
  key = package: builtins.unsafeDiscardStringContext (toString package);
  sameValue =
    a: b:
    if builtins.typeOf a != builtins.typeOf b then
      false
    else if builtins.isString a then
      a == b && builtins.getContext a == builtins.getContext b
    else if builtins.isList a then
      builtins.length a == builtins.length b && lib.all lib.id (lib.zipListsWith sameValue a b)
    else if builtins.isAttrs a then
      if lib.isDerivation a && lib.isDerivation b then
        sameValue (toString a) (toString b)
      else
        attrNames a == attrNames b && lib.all (name: sameValue a.${name} b.${name}) (attrNames a)
    else
      a == b;
  sortedUnique =
    values:
    attrNames (
      listToAttrs (
        map (v: {
          name = v;
          value = true;
        }) values
      )
    );
  packageSet =
    context: values:
    if !builtins.isList values || !lib.all lib.isDerivation values then
      fail "${context} must be a list of packages"
    else
      let
        indexed = foldl' (
          acc: p: if builtins.hasAttr (key p) acc then acc else acc // { ${key p} = p; }
        ) { } values;
      in
      map (id: indexed.${id}) (attrNames indexed);

  collect =
    origin: node:
    [
      {
        inherit origin;
        inherit (node) definition;
        id = key node.definition.plugin;
      }
    ]
    ++ concatLists (
      lib.imap0 (i: child: collect "${origin}.dependPlugins[${toString i}]" child) node.dependencies
    );
  trees = inspectDefinitions plugins;
  occurrences = concatLists (lib.imap0 (i: node: collect "plugins[${toString i}]" node) trees);
  groups = foldl' (
    acc: occurrence: acc // { ${occurrence.id} = (acc.${occurrence.id} or [ ]) ++ [ occurrence ]; }
  ) { } occurrences;

  mergeSettings =
    id: declarations:
    foldl'
      (
        acc: occurrence:
        let
          fields = builtins.removeAttrs occurrence.definition [
            "plugin"
            "dependPlugins"
            "extraPackages"
          ];
        in
        foldl' (
          state: field:
          if builtins.hasAttr field state.values then
            let
              comparison = builtins.tryEval (sameValue state.values.${field} fields.${field});
            in
            if comparison.success && comparison.value then
              state
            else
              fail "conflicting field '${field}' for '${id}' at ${state.origins.${field}} and ${occurrence.origin}"
          else
            {
              values = state.values // {
                ${field} = fields.${field};
              };
              origins = state.origins // {
                ${field} = occurrence.origin;
              };
            }
        ) acc (attrNames fields)
      )
      {
        values = { };
        origins = { };
      }
      declarations;

  nodes = mapAttrs (
    id: declarations:
    let
      settings = (mergeSettings id declarations).values;
      dependencies = concatLists (
        map (
          o:
          map (entry: key (if lib.isDerivation entry then entry else entry.plugin)) (
            o.definition.dependPlugins or [ ]
          )
        ) declarations
      );
    in
    {
      inherit id settings;
      package = (builtins.head declarations).definition.plugin;
      placement = "opt";
      dependencies = sortedUnique dependencies;
      extraPackages = packageSet "extraPackages for '${id}'" (
        concatLists (map (o: o.definition.extraPackages or [ ]) declarations)
      );
      origins = map (o: o.origin) declarations;
    }
  ) groups;
  ids = attrNames nodes;

  closure =
    edges: starts:
    map (entry: entry.key) (
      builtins.genericClosure {
        startSet = map (id: { key = id; }) starts;
        operator = item: map (id: { key = id; }) (edges item.key);
      }
    );
  # shortcut: mutual reachability stores O(V^2) reachability; benchmark before large migrations.
  reachable = listToAttrs (
    map (id: {
      name = id;
      value = listToAttrs (
        map (other: {
          name = other;
          value = true;
        }) (closure (n: nodes.${n}.dependencies) [ id ])
      );
    }) ids
  );
  components =
    foldl'
      (
        acc: id:
        if builtins.elem id acc.assigned then
          acc
        else
          let
            members = builtins.filter (
              other: (reachable.${id}.${other} or false) && (reachable.${other}.${id} or false)
            ) ids;
          in
          {
            assigned = acc.assigned ++ members;
            values = acc.values ++ [ members ];
          }
      )
      {
        assigned = [ ];
        values = [ ];
      }
      ids;
  owner = listToAttrs (
    lib.concatMap (
      members:
      map (id: {
        name = id;
        value = builtins.head members;
      }) members
    ) components.values
  );
  unitsById = listToAttrs (
    map (
      members:
      let
        id = builtins.head members;
      in
      {
        name = id;
        value = {
          inherit id members;
          dependencies = builtins.filter (other: other != id) (
            sortedUnique (lib.concatMap (member: map (d: owner.${d}) nodes.${member}.dependencies) members)
          );
          cyclic = builtins.length members > 1 || builtins.elem id nodes.${id}.dependencies;
        };
      }
    ) components.values
  );
  sorted = lib.toposort (a: b: builtins.elem a.id b.dependencies) (builtins.attrValues unitsById);
  ordered =
    if sorted ? result then sorted.result else fail "internal error: SCC condensation is cyclic";
  startupSeeds = sortedUnique (
    map (id: owner.${id}) (
      builtins.filter (id: nodes.${id}.settings ? lazy && nodes.${id}.settings.lazy == false) ids
    )
  );
  startupClosure = closure (id: unitsById.${id}.dependencies) startupSeeds;
  units = map (unit: unit // { startup = builtins.elem unit.id startupClosure; }) ordered;

  # Force validation without recursively forcing derivation passthru attributes.
  validation = mapAttrs (_: node: {
    fields = attrNames node.settings;
    inherit (node) dependencies;
    tools = map key node.extraPackages;
  }) nodes;
  rootTools = packageSet "root extraPackages" extraPackages;
  tools = packageSet "extraPackages" (rootTools ++ lib.concatMap (id: nodes.${id}.extraPackages) ids);
in
deepSeq validation (
  deepSeq (map key tools) {
    inherit nodes units;
    roots = lib.unique (map (node: key node.definition.plugin) trees);
    startupUnits = map (unit: unit.id) (builtins.filter (unit: unit.startup) units);
    unresolvedTiming = builtins.filter (id: !(nodes.${id}.settings ? lazy)) ids;
    extraPackages = tools;
    metadata = builtins.removeAttrs request [
      "plugins"
      "extraPackages"
    ];
  }
)
