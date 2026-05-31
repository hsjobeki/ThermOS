{ types, ... }:
{
  name = "tmpfiles";

  subscribe = [ "/contracts/tmpfiles" ];

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  impl =
    { subscriptions, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      lib = inputs.nixpkgs.lib;
      rules = subscriptions.tmpfiles;
      content = lib.concatMapStringsSep "\n" (r: r.rule) rules + "\n";
    in
    {
      derivation = pkgs.writeTextDir "etc/tmpfiles.d/thermos.conf" content;
    };
}
