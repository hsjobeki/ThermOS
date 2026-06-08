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
  nixpkgsModule = {
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

  /**
    system :: userConfig -> tree
  */
  configure = adios.adios {
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
      services = {
        modules = serviceModules;
      };
      middleware = {
        modules = middlewareModules;
      };
    };
  };

  tree = configure { inherit options; };

  initrdResult = tree.modules.builders.modules.initrd { };
in
{
  inherit
    pkgs
    lib
    configure
    tree
    ;

  image = (tree.modules.builders.modules.image { }).derivation;
  toplevel = (tree.modules.builders.modules.toplevel { }).derivation;
  rootfs = (tree.modules.builders.modules.rootfs { }).derivation;
  kernel = initrdResult.kernel;
  initrd = initrdResult.derivation;
}
