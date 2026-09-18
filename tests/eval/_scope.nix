let
  entrypoint = import ../../default.nix { };
  # Shared tree for impl-level tests: every service selected, hardware left out
  # so kernel-modules stays publisher-free (the dormant-by-default test).
  tree = entrypoint.configure {
    modules = [
      "/services/getty"
      "/services/dbus"
      "/services/openssh"
      "/services/networkd"
    ];
  };
in
{
  inherit entrypoint tree;
  inherit (entrypoint) nixpkgs-lib;
}
