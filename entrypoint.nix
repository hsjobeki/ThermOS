{ nixpkgs, adios }:
{
  system ? builtins.currentSystem,
  options ? { },
}:
let
  pkgs = nixpkgs { inherit system; };
  nixpkgs-lib = pkgs.lib;

  contractModules = adios.adios.lib.importModules ./modules/contracts;
  builderModules = adios.adios.lib.importModules ./modules/builders;
  coreModules = adios.adios.lib.importModules ./modules/core;
  serviceModules = adios.adios.lib.importModules ./modules/services;
  middlewareModules = adios.adios.lib.importModules ./modules/middleware;

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

  baseModules = {
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
    services = {
      modules = serviceModules;
    };
    middleware = {
      modules = middlewareModules;
    };
  };

  /**
    Produces an adios module tree.

    `modules` are merged into the base set before evaluation, letting callers
    add modules beyond the shipped set. Tests use it to inject a synthetic
    publisher and drive subscriber builders through the real contract +
    subscription path. Child modules live under a group `modules` attr, so a
    test publisher goes at `modules.<group>.modules.<name>`.

    Example

    ```nix
    configure {
      options."/core/base".rootHashedPassword = "sha...";
      modules.tests.modules.foo = extraPublisherModule;
    };
    ```

    Type

    system :: { options, modules } -> tree
  */
  configure =
    {
      options ? { },
      modules ? { },
    }:
    (adios.adios {
      name = "thermos";
      modules = baseModules // modules;
    })
      { inherit options; };

  tree = configure { inherit options; };

in
{
  inherit
    nixpkgs-lib
    pkgs
    configure
    tree
    ;

  # The adios, korora type constructors.
  types = adios.adios.types;
}
