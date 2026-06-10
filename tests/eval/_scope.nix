let
  entrypoint = import ../../default.nix { };
in
{
  inherit entrypoint;
  inherit (entrypoint) nixpkgs-lib tree;
}
