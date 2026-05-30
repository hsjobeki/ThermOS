{
  name = "thermos";
  description = "A Linux system built with Nix and Adios";

  entrypoint = ./entrypoint.nix;

  dependencies = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    adios.url = "github:hsjobeki/adios/pubsub";
  };

  shares = [ "nixpkgs" ];
}
