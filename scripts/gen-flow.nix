# Extracts module tree metadata for the docs flow diagram.
# Usage: ./scripts/gen-flow.sh
let
  # Stub types so module files can be imported without adios. Each stub carries
  # its `kind` so extractMeta can report option shapes to the docs renderer.
  stubType = kind: {
    verify = _: true;
    _kind = kind;
  };
  types = {
    str = stubType "str";
    int = stubType "int";
    bool = stubType "bool";
    any = stubType "any";
    listOf = elem: (stubType "listOf") // { _elem = elem; };
    attrsOf = elem: (stubType "attrsOf") // { _elem = elem; };
    # Contract option types. Not rendered as settings (only modules/services are),
    # but module files must import without forcing a missing attribute.
    derivation = stubType "derivation";
    struct = _name: _fields: stubType "struct";
    union = _members: stubType "union";
    optionalAttr = _inner: stubType "optionalAttr";
  };

  # Import a module file and extract structural metadata
  extractMeta =
    path:
    let
      mod = import path { inherit types; };
      inputPaths = builtins.filter (p: p != "/nixpkgs") (
        builtins.map (i: mod.inputs.${i}.path) (builtins.attrNames (mod.inputs or { }))
      );
      # Flatten each option into { name, kind, elem?, default? }. `kind` and
      # `elem` come from the stub type; `default` is emitted only when present
      # and JSON-serializable (defaultFunc, a lambda, is skipped).
      extractOption =
        name: o:
        let
          t = o.type or null;
          kind = if t == null then "any" else (t._kind or "any");
          base = { inherit name kind; };
          withElem = if t != null && t ? _elem then base // { elem = t._elem._kind or "any"; } else base;
        in
        if o ? default && builtins.typeOf o.default != "lambda" then
          withElem // { default = o.default; }
        else
          withElem;
      options = builtins.attrValues (builtins.mapAttrs extractOption (mod.options or { }));
    in
    {
      name = mod.name or (builtins.baseNameOf path);
      publish = mod.publish or [ ];
      subscribe = mod.subscribe or [ ];
      inputs = inputPaths;
      inherit options;
    };

  # Scan a directory for .nix files and extract metadata from each
  scanDir =
    dir:
    let
      entries = builtins.readDir dir;
      nixFiles = builtins.filter (n: builtins.match ".*\\.nix" n != null) (builtins.attrNames entries);
    in
    map (f: extractMeta (dir + "/${f}")) nixFiles;

  modules = scanDir ../modules/core ++ scanDir ../modules/services;
  middleware = scanDir ../modules/middleware;
  contracts = scanDir ../modules/contracts;
  builders = scanDir ../modules/builders;
in
{
  inherit
    modules
    middleware
    contracts
    builders
    ;
}
