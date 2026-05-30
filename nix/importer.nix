{
  groups ? [ "eval" ],
  manifest ? import ../mana.nix,
  lock ? builtins.fromJSON (builtins.readFile ../lock.json),
}:
let
  debug = manifest.debug or false;
  trace = msg: v: if debug then builtins.trace msg v else v;
  # Keep up to date with lib.nix
  normalizeManifest =
    {
      defaultFn ? x: x,
    }:
    manifest:
    let
      dependencies = manifest.dependencies or { };
      checkName =
        name:
        builtins.seq (
          if builtins.match ".*/.*" name != null then
            let
              parts = builtins.filter builtins.isString (builtins.split "/" name);
              suggested = builtins.concatStringsSep "-" parts;
            in
            throw "Invalid dependency name \"${name}\". \"/\" is not allowed. Try \"${suggested}\" instead."
          else
            null
        );
    in
    {
      name = manifest.name or "<unknown-project>";
      # Should we add a default?
      description = manifest.description or "";
      dependencies = builtins.mapAttrs (
        name: dep:
        dep
        // checkName name {
          url = dep.url;
          overrides = dep.overrides or defaultFn;
          pins = dep.pins or [ ];
        }
      ) dependencies;
      pins = manifest.pins or [ ];
      shares = manifest.shares or [ ];
      entrypoint = manifest.entrypoint or "entrypoint.nix";
      groups =
        manifest.groups or {
          eval = builtins.mapAttrs (n: v: [ "eval" ]) dependencies;
        };
    };
  /**
    Import a dependency tree from the flat lock format { sources, deps }.

    For each node, looks up its dependency mapping in `deps`,
    fetches sources from `sources`, and imports entrypoints.
  */
  importNode =
    {
      nodeLockKey, # lock key of this node ("" for root)
      nodeManifest, # this node's manifest (from mana.nix)
      nodeGroups, # [ "eval" "dev" ] enabled groups for this node
    }:
    let
      normalizedManifest = normalizeManifest { } nodeManifest;
      availableGroups = normalizedManifest.groups;
      # { {groupName} :: [ "eval" "dev" ] }
      printableLockKey = if nodeLockKey == "" then "<root>" else nodeLockKey;
      groupsByName = trace ''
        [mana] ${printableLockKey}
          groups: ${builtins.concatStringsSep ", " nodeGroups}
          deps: ${builtins.concatStringsSep ", " (builtins.attrNames groupsResult)}'' groupsResult;
      groupsResult = builtins.zipAttrsWith (name: vs: builtins.concatMap (v: v) vs) (
        map (groupName: availableGroups.${groupName}) nodeGroups
      );

      dependencies = nodeManifest.dependencies or { };

      # This node's dep mapping from the lock: { depName -> lockKey }
      depMapping = lock.deps.${nodeLockKey} or { };
    in
    builtins.mapAttrs (
      ident: lockKey:
      let
        enabled = groupsByName ? ${ident};
        sourceEntry = lock.sources.${lockKey};
        source = fetchTree (
          (removeAttrs sourceEntry.args [ "ref" ])
          // (removeAttrs sourceEntry.locked [
            "lastModified"
            "lastModifiedDate"
            "shortRev"
          ])
        );

        # Read the dep's manifest (if it has one)
        depManifestPath = "${source}/mana.nix";
        manifestExists = builtins.pathExists depManifestPath;
        depManifest = if manifestExists then import depManifestPath else { };

        # Recursively import this dep's own dependencies
        scope = importNode {
          nodeLockKey = lockKey;
          nodeManifest = depManifest;
          nodeGroups = groupsByName.${ident};
        };

        # Consumer can override the entrypoint
        consumerSpec = dependencies.${ident} or { };
        # hasConsumerEntrypoint = consumerSpec.entrypoint != null;
        consumerEntrypoint = consumerSpec.entrypoint;

        # Import the entrypoint, passing resolved deps as args
        importEntrypoint =
          f: if builtins.isFunction f then f (builtins.intersectAttrs (builtins.functionArgs f) scope) else f;
        # Classify how we resolve this dependency's entrypoint
        resolution =
          if manifestExists then
            if dependencies.${ident} ? entrypoint then
              if dependencies.${ident}.entrypoint == null then
                "raw"
              else
                "custom: ${dependencies.${ident}.entrypoint}"
            else if consumerEntrypoint == null then
              "raw"
            else
              "entrypoint: ${consumerEntrypoint}"
          else if dependencies.${ident} ? entrypoint && dependencies.${ident}.entrypoint == null then
            "raw"
          else
            "default.nix";

        resolutionKind = builtins.head (builtins.split ":" resolution);

        resolved = trace "[mana] ${printableLockKey}/${ident} [${resolution}]" (
          if resolutionKind == "raw" then
            source
          else if resolutionKind == "custom" then
            importEntrypoint (import "${source}/${dependencies.${ident}.entrypoint}")
          else if resolutionKind == "entrypoint" then
            importEntrypoint (import "${source}/${consumerEntrypoint}")
          else
            import "${source}/default.nix"
        );
      in
      if enabled then
        resolved
      else
        # Dep not enabled: throw with helpful message
        throw (
          let
            projectName = nodeManifest.name or null;
            projectLabel = if projectName != null then " in '${projectName}'" else "";
            enabledGroups = if nodeGroups != [ ] then builtins.toString nodeGroups else "<None>";
            recommendedGroups = builtins.filter (
              group: availableGroups ? ${group} && availableGroups.${group} ? ${ident}
            ) (builtins.attrNames availableGroups);
          in
          ''
            Dependency '${ident}' is not included${projectLabel}.

            Currently enabled groups: ${enabledGroups}

            To include '${ident}', add one of these groups:
              ${builtins.concatStringsSep "\n  " recommendedGroups}

            Example usage:
              (import ./nix/importer.nix) {
                 groups = [ "${if recommendedGroups != [ ] then builtins.head recommendedGroups else "eval"}" ];
              }
          ''
        )
    ) depMapping;

  scope = importNode {
    nodeLockKey = ""; # Start from "root"
    nodeManifest = normalizeManifest { } manifest;
    nodeGroups = groups;
  };

  f = import manifest.entrypoint;
in
f (builtins.intersectAttrs (builtins.functionArgs f) scope)
