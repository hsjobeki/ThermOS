{ nixpkgs, adios }:
{
  system ? builtins.currentSystem,
  options ? { },
}:
let
  pkgs = nixpkgs { inherit system; };
  lib = pkgs.lib;

  contractModules = adios.adios.lib.importModules ./modules/contracts;
  builderModules = adios.adios.lib.importModules ./modules/builders;
  coreModules = adios.adios.lib.importModules ./modules/core;
  serviceModules = adios.adios.lib.importModules ./modules/services;
  middlewareModules = adios.adios.lib.importModules ./modules/middleware;

  # Makes pkgs and lib available at /nixpkgs
  nixpkgsModule =
    { ... }:
    {
      name = "nixpkgs";
      options = {
        pkgs = {
          type = adios.adios.types.any;
          default = pkgs;
        };
        lib = {
          type = adios.adios.types.any;
          default = lib;
        };
      };
      impl = { options, ... }: options;
    };

  tree = adios.adios {
    name = "thermos";
    modules = {
      nixpkgs = nixpkgsModule adios.adios;
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
  };

  evaluated = tree { inherit options; };
in
{
  inherit
    pkgs
    lib
    tree
    evaluated
    ;

  toplevel = (evaluated.modules.builders.modules.toplevel { }).derivation;
  rootfs = (evaluated.modules.builders.modules.rootfs { }).derivation;
}
