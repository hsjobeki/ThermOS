# Extracts module tree metadata for the docs flow diagram.
# Usage: ./scripts/gen-flow.sh
let
  # Stub types so module files can be imported without adios
  stubType = {
    verify = _: true;
  };
  types = {
    str = stubType;
    int = stubType;
    bool = stubType;
    any = stubType;
    listOf = _: stubType;
    attrsOf = _: stubType;
  };

  # Import a module file and extract structural metadata
  extractMeta = path:
    let
      mod = import path { inherit types; };
    in {
      name = mod.name or (builtins.baseNameOf path);
      publish = mod.publish or [ ];
      subscribe = mod.subscribe or [ ];
    };

  # Scan a directory for .nix files and extract metadata from each
  scanDir = dir:
    let
      entries = builtins.readDir dir;
      nixFiles = builtins.filter (n: builtins.match ".*\\.nix" n != null) (builtins.attrNames entries);
    in map (f: extractMeta (dir + "/${f}")) nixFiles;

  modules = scanDir ../modules/core ++ scanDir ../modules/services;
  middleware = scanDir ../modules/middleware;
  contracts = scanDir ../modules/contracts;
  builders = scanDir ../modules/builders;
in {
  inherit modules middleware contracts builders;
}
