let
  s = import ./_scope.nix;
in
{
  contracts = import ./contracts.nix s;
  tree = import ./tree.nix s;
  builders = import ./builders.nix s;
  dbus = import ./dbus.nix s;
  networkd = import ./networkd.nix s;
  kernelModules = import ./kernel-modules.nix s;
  services = import ./services.nix s;
  options = import ./options.nix s;
  pipeline = import ./pipeline.nix s;
  pamProvider = import ./pam-provider.nix s;
  entrypoint = import ./entrypoint.nix s;
  openssh = import ./openssh.nix s;
}
