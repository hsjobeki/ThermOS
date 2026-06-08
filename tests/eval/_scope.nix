let
  entrypoint = import ../../default.nix { };
in
{
  inherit entrypoint;
  inherit (entrypoint) lib tree;
}
