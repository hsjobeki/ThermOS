{ types, ... }:
{
  name = "packages";

  subscribe = [ "/contracts/packages" ];

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  impl =
    { subscriptions, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      packageEntries = subscriptions.packages;
      paths = map (e: e.package) packageEntries;
    in
    {
      derivation = pkgs.buildEnv {
        name = "thermos-system-path";
        inherit paths;
        ignoreCollisions = false;
        extraOutputsToInstall = [
          "man"
          "doc"
        ];
      };
    };
}
