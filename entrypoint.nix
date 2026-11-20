{ nixpkgs, adios }:
{
  system ? builtins.currentSystem,
}:
let
  pkgs = nixpkgs { inherit system; };
  nixpkgs-lib = pkgs.lib;

  contractModules = adios.adios.lib.importModules ./modules/contracts;
  builderModules = adios.adios.lib.importModules ./modules/builders;
  coreModules = adios.adios.lib.importModules ./modules/core;
  middlewareModules = adios.adios.lib.importModules ./modules/middleware;

  # Selectable modules. Presence in the tree is enablement: a selected module
  # publishes, an unselected module does not exist. There is no enable option.
  catalog = {
    services = adios.adios.lib.importModules ./modules/services;
    hardware = adios.adios.lib.importModules ./modules/hardware;
  };

  catalogPaths = nixpkgs-lib.concatLists (
    nixpkgs-lib.mapAttrsToList (
      group: mods: map (name: "/${group}/${name}") (builtins.attrNames mods)
    ) catalog
  );

  # Resolves a list of catalog paths ("/services/openssh") into module groups.
  # Every catalog group is present in the tree, possibly empty, so the tree
  # shape does not depend on the selection.
  selectModules =
    paths:
    let
      parse =
        path:
        let
          m = builtins.match "/([^/]+)/([^/]+)" path;
          group = builtins.elemAt m 0;
          name = builtins.elemAt m 1;
        in
        if m == null || !(catalog ? ${group}) || !(catalog.${group} ? ${name}) then
          throw "thermos: unknown module '${path}'. Available: ${builtins.concatStringsSep ", " catalogPaths}"
        else
          { inherit group name; };
      picked = map parse paths;
    in
    builtins.mapAttrs (group: mods: {
      modules = nixpkgs-lib.filterAttrs (
        name: _: builtins.any (p: p.group == group && p.name == name) picked
      ) mods;
    }) catalog;

  # Makes pkgs and lib available at /nixpkgs
  nixpkgsModule = {
    name = "nixpkgs";
    options = {
      pkgs = {
        type = adios.adios.types.any;
        default = pkgs;
      };
      lib = {
        type = adios.adios.types.any;
        default = nixpkgs-lib;
      };
    };
    impl = { options, ... }: options;
  };

  /**
    Produces an adios module tree.

    `modules` selects catalog modules by path. Core, contracts, builders, and
    middleware are always in the tree; everything else is a module a system
    drops in. An unknown path throws with the available list.

    `extraModules` is an attrset merged over the group set, letting callers
    add modules beyond the shipped catalog. Tests use it to inject a synthetic
    publisher and drive subscriber builders through the real contract +
    subscription path. Child modules live under a group `modules` attr, so a
    test publisher goes at `extraModules.<group>.modules.<name>`.

    Example

    ```nix
    configure {
      modules = [
        "/services/openssh"
        "/hardware/initrd-storage"
      ];
      options."/core/base".rootHashedPassword = "sha...";
      extraModules.tests.modules.foo = extraPublisherModule;
    };
    ```

    Type

    system :: { modules, options, extraModules } -> tree
  */
  configure =
    {
      modules ? [ ],
      options ? { },
      extraModules ? { },
    }:
    (adios.adios {
      name = "thermos";
      modules = {
        nixpkgs = nixpkgsModule;
        contracts = {
          modules = contractModules;
        };
        builders = {
          modules = builderModules;
        };
        core = {
          modules = coreModules;
        };
        middleware = {
          modules = middlewareModules;
        };
      }
      // selectModules modules
      // extraModules;
    })
      { inherit options; };

in
{
  inherit
    nixpkgs-lib
    pkgs
    configure
    catalogPaths
    catalog
    ;

  # The adios, korora type constructors.
  types = adios.adios.types;
}
